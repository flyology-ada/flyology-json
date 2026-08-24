/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#ifndef FLYOLOGY_JSON_CPP_BENCH_ADAPTERS_H
#define FLYOLOGY_JSON_CPP_BENCH_ADAPTERS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum flyology_json_cpp_bench_status {
  FLYOLOGY_JSON_CPP_BENCH_OK = 0,
  FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT = 1,
  FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR = 2,
  FLYOLOGY_JSON_CPP_BENCH_ALLOCATION_FAILURE = 3,
  FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR = 4
};

struct flyology_json_cpp_bench_observation {
  uint64_t checksum;
  uint64_t event_count;
  uint64_t scalar_count;
  uint64_t member_name_count;
  uint64_t input_bytes;
};

/* Parses and recursively visits one complete document with simdjson's DOM
 * API. `input` must identify `capacity` readable bytes and `length` must be no
 * greater than capacity. The capacity must include the padding reported by
 * flyology_json_bench_simdjson_padding(). The function does not retain input.
 * `observation` is written only on success and must not overlap input.
 */
int32_t flyology_json_bench_simdjson_dom(
    const uint8_t *input,
    uint64_t length,
    uint64_t capacity,
    struct flyology_json_cpp_bench_observation *observation);

uint64_t flyology_json_bench_simdjson_padding(void);

/* Parses and recursively visits one complete document with RapidJSON's DOM
 * API. `input` must identify `length` readable bytes. The function does not
 * retain input. `observation` is written only on success and must not overlap
 * input.
 */
int32_t flyology_json_bench_rapidjson_dom(
    const uint8_t *input,
    uint64_t length,
    struct flyology_json_cpp_bench_observation *observation);

/* Parses one complete document through RapidJSON's Reader/SAX API and visits
 * every structural token, member name, and scalar. Numbers are reported as
 * exact lexical spans instead of being converted. `input` must identify
 * `length` readable bytes. The function does not retain input. `observation`
 * is written only on success and must not overlap input.
 */
int32_t flyology_json_bench_rapidjson_events(
    const uint8_t *input,
    uint64_t length,
    struct flyology_json_cpp_bench_observation *observation);

#ifdef __cplusplus
}
#endif

#endif
