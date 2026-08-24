// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::slice;

const _: () = assert!(size_of::<i32>() == 4);
const _: () = assert!(size_of::<u64>() == 8);
const _: () = assert!(size_of::<usize>() == size_of::<*const u8>());

const STATUS_OK: i32 = 0;
const STATUS_INVALID_ARGUMENT: i32 = 1;
const STATUS_PARSE_ERROR: i32 = 2;
const STATUS_PANIC: i32 = 3;

#[derive(Clone, Copy, Default)]
struct Observation {
    checksum: u64,
    items: usize,
}

impl Observation {
    #[inline]
    fn mix(&mut self, kind: u64, length: usize) {
        self.items = self.items.wrapping_add(1);
        self.checksum = self
            .checksum
            .wrapping_mul(0x9e37_79b1_85eb_ca87)
            .wrapping_add(kind)
            .wrapping_add(length as u64);
    }
}

fn traverse_serde(value: &serde_json::Value, observation: &mut Observation) {
    match value {
        serde_json::Value::Null => observation.mix(1, 0),
        serde_json::Value::Bool(value) => observation.mix(2 + u64::from(*value), 0),
        serde_json::Value::Number(value) => {
            let kind = if value.is_i64() {
                4
            } else if value.is_u64() {
                5
            } else {
                6
            };
            observation.mix(kind, 0);
        }
        serde_json::Value::String(value) => observation.mix(7, value.len()),
        serde_json::Value::Array(values) => {
            observation.mix(8, values.len());
            for value in values {
                traverse_serde(value, observation);
            }
            observation.mix(9, values.len());
        }
        serde_json::Value::Object(values) => {
            observation.mix(10, values.len());
            for (name, value) in values {
                observation.mix(11, name.len());
                traverse_serde(value, observation);
            }
            observation.mix(12, values.len());
        }
    }
}

fn traverse_sonic(value: &sonic_rs::Value, observation: &mut Observation) {
    use sonic_rs::{JsonContainerTrait, JsonValueTrait};

    if value.is_null() {
        observation.mix(1, 0);
    } else if let Some(value) = value.as_bool() {
        observation.mix(2 + u64::from(value), 0);
    } else if value.is_number() {
        observation.mix(4, 0);
    } else if let Some(value) = value.as_str() {
        observation.mix(7, value.len());
    } else if let Some(values) = value.as_array() {
        observation.mix(8, values.len());
        for value in values {
            traverse_sonic(value, observation);
        }
        observation.mix(9, values.len());
    } else if let Some(values) = value.as_object() {
        observation.mix(10, values.len());
        for (name, value) in values {
            observation.mix(11, name.len());
            traverse_sonic(value, observation);
        }
        observation.mix(12, values.len());
    } else {
        unreachable!("sonic-rs Value has an unknown JSON kind");
    }
}

fn traverse_simd(value: &simd_json::BorrowedValue<'_>, observation: &mut Observation) {
    use simd_json::prelude::*;

    match value {
        simd_json::BorrowedValue::Static(value) => match value {
            simd_json::StaticNode::Null => observation.mix(1, 0),
            simd_json::StaticNode::Bool(value) => observation.mix(2 + u64::from(*value), 0),
            simd_json::StaticNode::I64(_) => observation.mix(4, 0),
            simd_json::StaticNode::U64(_) => observation.mix(5, 0),
            simd_json::StaticNode::F64(_) => observation.mix(6, 0),
        },
        simd_json::BorrowedValue::String(value) => observation.mix(7, value.len()),
        simd_json::BorrowedValue::Array(values) => {
            observation.mix(8, values.len());
            for value in values.iter() {
                traverse_simd(value, observation);
            }
            observation.mix(9, values.len());
        }
        simd_json::BorrowedValue::Object(values) => {
            observation.mix(10, values.len());
            for (name, value) in values.iter() {
                observation.mix(11, name.len());
                traverse_simd(value, observation);
            }
            observation.mix(12, values.len());
        }
    }
}

unsafe fn publish(observation: Observation, checksum: *mut u64, items: *mut usize) -> i32 {
    // SAFETY: non-null output pointers are required by the C contract and are
    // written only after parsing and traversal have completed successfully.
    unsafe {
        *checksum = observation.checksum;
        *items = observation.items;
    }
    STATUS_OK
}

unsafe fn input<'a>(input: *const u8, length: usize) -> Result<&'a [u8], i32> {
    if input.is_null() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    // SAFETY: the C contract requires a readable range of exactly `length`
    // bytes that remains live for the duration of this coarse call.
    Ok(unsafe { slice::from_raw_parts(input, length) })
}

fn outputs_are_valid(checksum: *mut u64, items: *mut usize) -> bool {
    !checksum.is_null() && !items.is_null()
}

fn run(operation: impl FnOnce() -> Result<Observation, i32>) -> Result<Observation, i32> {
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(result) => result,
        Err(_) => Err(STATUS_PANIC),
    }
}

/// Parses and completely traverses one JSON document with serde_json.
///
/// # Safety
///
/// `input_pointer` must identify `length` readable bytes. `checksum` and
/// `items` must be valid writable pointers. All ranges must remain live and
/// unaliased as required for their access for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn flyology_json_bench_serde_json_traverse(
    input_pointer: *const u8,
    length: usize,
    checksum: *mut u64,
    items: *mut usize,
) -> i32 {
    if !outputs_are_valid(checksum, items) {
        return STATUS_INVALID_ARGUMENT;
    }
    match run(|| {
        let input = unsafe { input(input_pointer, length) }?;
        let value: serde_json::Value =
            serde_json::from_slice(input).map_err(|_| STATUS_PARSE_ERROR)?;
        let mut observation = Observation::default();
        traverse_serde(&value, &mut observation);
        Ok::<Observation, i32>(observation)
    }) {
        Ok(observation) => unsafe { publish(observation, checksum, items) },
        Err(status) => status,
    }
}

/// Parses and completely traverses one JSON document with sonic-rs.
///
/// # Safety
///
/// `input_pointer` must identify `length` readable bytes. `checksum` and
/// `items` must be valid writable pointers. All ranges must remain live and
/// unaliased as required for their access for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn flyology_json_bench_sonic_rs_traverse(
    input_pointer: *const u8,
    length: usize,
    checksum: *mut u64,
    items: *mut usize,
) -> i32 {
    if !outputs_are_valid(checksum, items) {
        return STATUS_INVALID_ARGUMENT;
    }
    match run(|| {
        let input = unsafe { input(input_pointer, length) }?;
        let value: sonic_rs::Value = sonic_rs::from_slice(input).map_err(|_| STATUS_PARSE_ERROR)?;
        let mut observation = Observation::default();
        traverse_sonic(&value, &mut observation);
        Ok::<Observation, i32>(observation)
    }) {
        Ok(observation) => unsafe { publish(observation, checksum, items) },
        Err(status) => status,
    }
}

/// Copies, parses, and completely traverses one JSON document with simd-json.
///
/// # Safety
///
/// `input_pointer` must identify `length` readable bytes. `checksum` and
/// `items` must be valid writable pointers. All ranges must remain live and
/// mutually unaliased for the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn flyology_json_bench_simd_json_traverse(
    input_pointer: *const u8,
    length: usize,
    checksum: *mut u64,
    items: *mut usize,
) -> i32 {
    if !outputs_are_valid(checksum, items) {
        return STATUS_INVALID_ARGUMENT;
    }
    match run(|| {
        let source = unsafe { input(input_pointer, length) }?;
        let mut private_input = source.to_vec();
        let value =
            simd_json::to_borrowed_value(&mut private_input).map_err(|_| STATUS_PARSE_ERROR)?;
        let mut observation = Observation::default();
        traverse_simd(&value, &mut observation);
        Ok::<Observation, i32>(observation)
    }) {
        Ok(observation) => unsafe { publish(observation, checksum, items) },
        Err(status) => status,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use simd_json::prelude::*;
    use sonic_rs::{JsonContainerTrait, JsonValueTrait};

    const SAMPLE: &[u8] = br#"{"a":[null,true,-1,1.5,"x"]}"#;

    unsafe fn call_read_only(
        parser: unsafe extern "C" fn(*const u8, usize, *mut u64, *mut usize) -> i32,
        input: &[u8],
    ) -> (i32, u64, usize) {
        let mut checksum = 0;
        let mut items = 0;
        let status = unsafe { parser(input.as_ptr(), input.len(), &mut checksum, &mut items) };
        (status, checksum, items)
    }

    fn simd_status(input: &[u8]) -> i32 {
        let mut checksum = 0;
        let mut items = 0;
        unsafe {
            flyology_json_bench_simd_json_traverse(
                input.as_ptr(),
                input.len(),
                &mut checksum,
                &mut items,
            )
        }
    }

    #[test]
    fn read_only_adapters_agree_on_valid_shape() {
        let serde = unsafe { call_read_only(flyology_json_bench_serde_json_traverse, SAMPLE) };
        let sonic = unsafe { call_read_only(flyology_json_bench_sonic_rs_traverse, SAMPLE) };
        assert_eq!(serde.0, STATUS_OK);
        assert_eq!(sonic.0, STATUS_OK);
        assert_eq!(serde.2, 10);
        assert_eq!(sonic.2, 10);
        assert_eq!(serde.1, 8_276_310_347_018_424_111);
        assert_eq!(sonic.1, 5_302_750_202_477_362_561);
    }

    #[test]
    fn simd_adapter_copies_and_preserves_read_only_input() {
        let sample = SAMPLE.to_vec();
        let original = sample.clone();
        let mut checksum = 0;
        let mut items = 0;
        let status = unsafe {
            flyology_json_bench_simd_json_traverse(
                sample.as_ptr(),
                sample.len(),
                &mut checksum,
                &mut items,
            )
        };
        assert_eq!(status, STATUS_OK);
        assert_eq!(checksum, 8_276_310_347_018_424_111);
        assert_eq!(items, 10);
        assert_eq!(sample, original);
    }

    #[test]
    fn simd_error_does_not_publish_outputs() {
        let malformed = b"[".to_vec();
        let mut checksum = 17;
        let mut items = 23;
        let status = unsafe {
            flyology_json_bench_simd_json_traverse(
                malformed.as_ptr(),
                malformed.len(),
                &mut checksum,
                &mut items,
            )
        };
        assert_eq!(status, STATUS_PARSE_ERROR);
        assert_eq!(checksum, 17);
        assert_eq!(items, 23);
    }

    #[test]
    fn errors_do_not_publish_outputs() {
        for parser in [
            flyology_json_bench_serde_json_traverse,
            flyology_json_bench_sonic_rs_traverse,
        ] {
            let mut checksum = 17;
            let mut items = 23;
            let status = unsafe { parser(b"[".as_ptr(), 1, &mut checksum, &mut items) };
            assert_eq!(status, STATUS_PARSE_ERROR);
            assert_eq!(checksum, 17);
            assert_eq!(items, 23);
        }
    }

    #[test]
    fn null_arguments_are_rejected_without_publication() {
        for parser in [
            flyology_json_bench_serde_json_traverse,
            flyology_json_bench_sonic_rs_traverse,
            flyology_json_bench_simd_json_traverse,
        ] {
            let mut checksum = 17;
            let mut items = 23;
            let status = unsafe { parser(std::ptr::null(), 0, &mut checksum, &mut items) };
            assert_eq!(status, STATUS_INVALID_ARGUMENT);
            assert_eq!(checksum, 17);
            assert_eq!(items, 23);

            let status = unsafe { parser(b"null".as_ptr(), 4, std::ptr::null_mut(), &mut items) };
            assert_eq!(status, STATUS_INVALID_ARGUMENT);
            assert_eq!(items, 23);

            let status =
                unsafe { parser(b"null".as_ptr(), 4, &mut checksum, std::ptr::null_mut()) };
            assert_eq!(status, STATUS_INVALID_ARGUMENT);

            let empty: &[u8] = &[];
            let status = unsafe { parser(empty.as_ptr(), 0, &mut checksum, &mut items) };
            assert_eq!(status, STATUS_PARSE_ERROR);
        }
    }

    #[test]
    fn strict_profile_extensions_are_rejected() {
        let rejected: &[&[u8]] = &[
            b"\xef\xbb\xbfnull",
            b"\xff",
            b"/*x*/null",
            b"[0,]",
            b"\"\n\"",
            b"+1",
            b"01",
            b"NaN",
        ];

        for input in rejected {
            let serde = unsafe { call_read_only(flyology_json_bench_serde_json_traverse, input) };
            let sonic = unsafe { call_read_only(flyology_json_bench_sonic_rs_traverse, input) };
            assert_eq!(serde.0, STATUS_PARSE_ERROR, "serde_json accepted {input:?}");
            assert_eq!(sonic.0, STATUS_PARSE_ERROR, "sonic-rs accepted {input:?}");
            assert_eq!(
                simd_status(input),
                STATUS_PARSE_ERROR,
                "simd-json accepted {input:?}"
            );
        }
    }

    #[test]
    fn documented_duplicate_object_name_behaviors_are_observed() {
        let input = br#"{"a":1,"\u0061":2}"#;

        let serde: serde_json::Value = serde_json::from_slice(input).unwrap();
        assert_eq!(serde["a"].as_u64(), Some(2));
        assert_eq!(serde.as_object().unwrap().len(), 1);

        let sonic: sonic_rs::Value = sonic_rs::from_slice(input).unwrap();
        let sonic_values: Vec<_> = sonic
            .as_object()
            .unwrap()
            .iter()
            .filter(|(name, _)| *name == "a")
            .map(|(_, value)| value.as_u64())
            .collect();
        assert_eq!(sonic_values, [Some(1), Some(2)]);

        let mut simd_input = input.to_vec();
        assert!(simd_json::to_borrowed_value(&mut simd_input).is_ok());
    }

    #[test]
    fn unpaired_surrogate_behavior_is_explicit() {
        let high = br#""\uD800""#;
        let low = br#""\uDC00""#;

        assert!(serde_json::from_slice::<serde_json::Value>(high).is_err());
        assert!(sonic_rs::from_slice::<sonic_rs::Value>(high).is_err());

        let mut simd_high = high.to_vec();
        let value = simd_json::to_borrowed_value(&mut simd_high).unwrap();
        assert_eq!(value.as_str(), Some("\0"));

        let mut simd_low = low.to_vec();
        assert!(simd_json::to_borrowed_value(&mut simd_low).is_err());
    }

    #[test]
    fn configured_depth_boundaries_are_stable() {
        fn nested(depth: usize) -> Vec<u8> {
            let mut input = vec![b'['; depth];
            input.extend(std::iter::repeat_n(b']', depth));
            input
        }

        assert!(serde_json::from_slice::<serde_json::Value>(&nested(127)).is_ok());
        assert!(serde_json::from_slice::<serde_json::Value>(&nested(128)).is_err());

        assert!(sonic_rs::from_slice::<sonic_rs::Value>(&nested(256)).is_ok());

        let mut simd_maximum = nested(1_024);
        assert!(simd_json::to_borrowed_value(&mut simd_maximum).is_ok());
        let mut simd_excess = nested(1_025);
        assert!(simd_json::to_borrowed_value(&mut simd_excess).is_err());
    }

    #[test]
    fn panic_is_converted_to_status() {
        let result = run(|| -> Result<Observation, i32> { panic!("controlled adapter test") });
        assert!(matches!(result, Err(STATUS_PANIC)));
    }
}
