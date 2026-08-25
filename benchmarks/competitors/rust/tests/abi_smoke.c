/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#include "flyology_json_rust_bench_adapters.h"

#include <stdint.h>

typedef int (*read_only_parser)(const uint8_t *, size_t, uint64_t *, size_t *);
typedef int (*prepare_writer)(const uint8_t *, size_t, void **);
typedef int (*write_document)(const void *, uint64_t *, size_t *);
typedef int (*check_document)(const void *, const uint8_t *, size_t,
                              uint64_t *, size_t *, int *);
typedef int (*release_writer)(void *);

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

static int check_writer(prepare_writer prepare, write_document write,
                        check_document check, release_writer release) {
  static const uint8_t valid[] = "{\"a\":[null,true,-1,1.5,\"x\"]}";
  static const uint8_t invalid[] = "[";
  static const uint8_t different[] = "null";
  void *context = NULL;
  void *sentinel = (void *)(uintptr_t)1;
  uint64_t checksum = 0;
  size_t length = 0;
  int matches = 0;

  if (prepare(valid, sizeof(valid) - 1, &context) !=
          FLYOLOGY_JSON_RUST_BENCH_OK || context == NULL) return 1;
  if (check(context, valid, sizeof(valid) - 1, &checksum, &length, &matches) !=
          FLYOLOGY_JSON_RUST_BENCH_OK || !matches || length != sizeof(valid) - 1) return 2;
  if (check(context, different, sizeof(different) - 1, &checksum, &length, &matches) !=
          FLYOLOGY_JSON_RUST_BENCH_OK || matches || length != sizeof(valid) - 1) return 6;
  if (write(context, &checksum, &length) != FLYOLOGY_JSON_RUST_BENCH_OK ||
      checksum == 0 || length != sizeof(valid) - 1) return 3;
  if (prepare(invalid, sizeof(invalid) - 1, &sentinel) !=
          FLYOLOGY_JSON_RUST_BENCH_PARSE_ERROR || sentinel != (void *)(uintptr_t)1) return 7;
  if (release(context) != FLYOLOGY_JSON_RUST_BENCH_OK) return 4;
  if (release(NULL) != FLYOLOGY_JSON_RUST_BENCH_OK) return 5;
  return 0;
}

int main(void) {
  static const uint8_t source[] = "{\"a\":[null,true,-1,1.5,\"x\"]}";
  static const uint8_t invalid[] = "[";
  uint64_t checksum = 0;
  size_t items = 0;

  if (check_read_only(flyology_json_bench_serde_json_traverse,
                      UINT64_C(9979358259564605272)) != 0) {
    return 10;
  }
  if (check_read_only(flyology_json_bench_sonic_rs_traverse,
                      UINT64_C(5624672763124767306)) != 0) {
    return 20;
  }
  if (check_writer(flyology_json_bench_serde_json_prepare_write,
                   flyology_json_bench_serde_json_write,
                   flyology_json_bench_serde_json_check_write,
                   flyology_json_bench_serde_json_release_write) != 0) return 21;
  if (check_writer(flyology_json_bench_sonic_rs_prepare_write,
                   flyology_json_bench_sonic_rs_write,
                   flyology_json_bench_sonic_rs_check_write,
                   flyology_json_bench_sonic_rs_release_write) != 0) return 22;

  if (flyology_json_bench_simd_json_traverse(
      source, sizeof(source) - 1, &checksum, &items) !=
          FLYOLOGY_JSON_RUST_BENCH_OK ||
      checksum != UINT64_C(9979358259564605272) || items != 10) {
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
