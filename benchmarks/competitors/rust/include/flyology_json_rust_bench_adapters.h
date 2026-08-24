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
  FLYOLOGY_JSON_RUST_BENCH_PANIC = 3
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

#ifdef __cplusplus
}
#endif

#endif
