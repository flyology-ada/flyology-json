/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#ifndef FLYOLOGY_JSON_RUST_BENCH_ADAPTERS_H
#define FLYOLOGY_JSON_RUST_BENCH_ADAPTERS_H

#include <stddef.h>
#include <stdint.h>
#include <limits.h>

#ifdef __cplusplus
#define FLYOLOGY_JSON_RUST_ABI_ASSERT(condition, message) static_assert(condition, message)
#else
#define FLYOLOGY_JSON_RUST_ABI_ASSERT(condition, message) _Static_assert(condition, message)
#endif

FLYOLOGY_JSON_RUST_ABI_ASSERT(CHAR_BIT == 8, "benchmark ABI requires 8-bit bytes");
FLYOLOGY_JSON_RUST_ABI_ASSERT(sizeof(int) == 4, "benchmark ABI requires 32-bit C int");
FLYOLOGY_JSON_RUST_ABI_ASSERT(sizeof(uint64_t) == 8,
                              "benchmark ABI requires 64-bit uint64_t");
FLYOLOGY_JSON_RUST_ABI_ASSERT(sizeof(size_t) == sizeof(void *),
                              "benchmark ABI requires pointer-sized size_t");

#undef FLYOLOGY_JSON_RUST_ABI_ASSERT

#ifdef __cplusplus
extern "C" {
#endif

enum flyology_json_rust_bench_status {
  FLYOLOGY_JSON_RUST_BENCH_OK = 0,
  FLYOLOGY_JSON_RUST_BENCH_INVALID_ARGUMENT = 1,
  FLYOLOGY_JSON_RUST_BENCH_PARSE_ERROR = 2,
  FLYOLOGY_JSON_RUST_BENCH_PANIC = 3,
  FLYOLOGY_JSON_RUST_BENCH_WRITE_ERROR = 4
};

/* Each function handles one complete document per call. On success it writes
 * checksum and items. On failure it leaves both outputs unchanged. Input and
 * output ranges must be valid, live, and mutually unaliased for the call.
 */
int flyology_json_bench_serde_json_traverse(const uint8_t *input,
                                             size_t length,
                                             uint64_t *checksum,
                                             size_t *items);

int flyology_json_bench_sonic_rs_traverse(const uint8_t *input,
                                           size_t length,
                                           uint64_t *checksum,
                                           size_t *items);

/* simd-json requires mutable storage. This coarse call copies the read-only
 * input into a private Vec before parsing; the copy is timed with the call. */
int flyology_json_bench_simd_json_traverse(const uint8_t *input,
                                           size_t length,
                                           uint64_t *checksum,
                                           size_t *items);

/* Writer preparation requires `input` to identify `length` readable bytes and
 * `context` to identify one writable pointer slot. The input range and context
 * slot must not overlap. Input is borrowed only for this call. Preparation
 * does not modify the slot on failure. On success it publishes unique ownership
 * of an opaque crate DOM; the caller must pass that pointer only to the matching
 * implementation's write/check/release functions and release it exactly once.
 *
 * A write call requires a live context from the matching prepare call plus
 * writable `checksum` and `output_length` scalars. The context allocation and
 * both output scalars must be pairwise disjoint. No write/check/release call may
 * use the context concurrently with another such call.
 *
 * A check call additionally requires `expected` to identify `expected_length`
 * readable bytes and `matches` to identify one writable int. The expected range,
 * context allocation, checksum, output-length, and matches storage must all be
 * mutually nonoverlapping. Write and check allocate and serialize a complete
 * output, observe every byte, and release that output before returning.
 *
 * Release accepts null as a no-op. A nonnull argument transfers the unique
 * context ownership back to Rust and is consumed regardless of returned status;
 * it must be live, must not have concurrent users, and must never be used again. */
int flyology_json_bench_serde_json_prepare_write(const uint8_t *input,
                                                  size_t length,
                                                  void **context);
int flyology_json_bench_sonic_rs_prepare_write(const uint8_t *input,
                                                size_t length,
                                                void **context);
int flyology_json_bench_serde_json_write(const void *context,
                                          uint64_t *checksum,
                                          size_t *output_length);
int flyology_json_bench_sonic_rs_write(const void *context,
                                        uint64_t *checksum,
                                        size_t *output_length);
int flyology_json_bench_serde_json_check_write(
    const void *context, const uint8_t *expected, size_t expected_length,
    uint64_t *checksum, size_t *output_length, int *matches);
int flyology_json_bench_sonic_rs_check_write(
    const void *context, const uint8_t *expected, size_t expected_length,
    uint64_t *checksum, size_t *output_length, int *matches);
int flyology_json_bench_serde_json_release_write(void *context);
int flyology_json_bench_sonic_rs_release_write(void *context);

#ifdef __cplusplus
}
#endif

#endif
