/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#include "flyology_json_rust_bench_adapters.h"

#include <stdint.h>

typedef int (*read_only_parser)(const uint8_t *, size_t, uint64_t *, size_t *);

static int check_read_only(read_only_parser parser, uint64_t expected_checksum) {
  static const uint8_t valid[] = "{\"a\":[null,true,-1,1.5,\"x\"]}";
  static const uint8_t invalid[] = "[";
  uint64_t checksum = 17;
  size_t items = 23;

  if (parser(valid, sizeof(valid) - 1, &checksum, &items) !=
          FLYOLOGY_JSON_RUST_BENCH_OK ||
      checksum == 0 || items == 0) {
    return 1;
  }
  if (checksum != expected_checksum || items != 10) {
    return 3;
  }

  checksum = 17;
  items = 23;
  if (parser(invalid, sizeof(invalid) - 1, &checksum, &items) !=
          FLYOLOGY_JSON_RUST_BENCH_PARSE_ERROR ||
      checksum != 17 || items != 23) {
    return 2;
  }

  return 0;
}

int main(void) {
  static const uint8_t source[] = "{\"a\":[null,true,-1,1.5,\"x\"]}";
  static const uint8_t invalid[] = "[";
  uint64_t checksum = 0;
  size_t items = 0;

  if (check_read_only(flyology_json_bench_serde_json_traverse,
                      UINT64_C(8276310347018424111)) != 0) {
    return 10;
  }
  if (check_read_only(flyology_json_bench_sonic_rs_traverse,
                      UINT64_C(5302750202477362561)) != 0) {
    return 20;
  }

  if (flyology_json_bench_simd_json_traverse(
          source, sizeof(source) - 1, &checksum, &items) !=
          FLYOLOGY_JSON_RUST_BENCH_OK ||
      checksum != UINT64_C(8276310347018424111) || items != 10) {
    return 30;
  }

  checksum = 17;
  items = 23;
  if (flyology_json_bench_simd_json_traverse(
          invalid, sizeof(invalid) - 1, &checksum, &items) !=
          FLYOLOGY_JSON_RUST_BENCH_PARSE_ERROR ||
      checksum != 17 || items != 23) {
    return 31;
  }

  if (flyology_json_bench_simd_json_traverse(NULL, 0, &checksum, &items) !=
      FLYOLOGY_JSON_RUST_BENCH_INVALID_ARGUMENT) {
    return 32;
  }

  return 0;
}
