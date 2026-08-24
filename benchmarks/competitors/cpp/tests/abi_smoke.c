/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#include "flyology_json_cpp_bench_adapters.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

_Static_assert(sizeof(struct flyology_json_cpp_bench_observation) == 40,
               "observation size changed");
_Static_assert(offsetof(struct flyology_json_cpp_bench_observation, checksum) == 0,
               "checksum offset changed");
_Static_assert(offsetof(struct flyology_json_cpp_bench_observation, event_count) == 8,
               "event count offset changed");
_Static_assert(offsetof(struct flyology_json_cpp_bench_observation, scalar_count) == 16,
               "scalar count offset changed");
_Static_assert(offsetof(struct flyology_json_cpp_bench_observation, member_name_count) == 24,
               "member-name count offset changed");
_Static_assert(offsetof(struct flyology_json_cpp_bench_observation, input_bytes) == 32,
               "input-byte count offset changed");

typedef int32_t (*simdjson_function)(
    const uint8_t *, uint64_t, uint64_t,
    struct flyology_json_cpp_bench_observation *);
typedef int32_t (*rapidjson_function)(
    const uint8_t *, uint64_t,
    struct flyology_json_cpp_bench_observation *);

static int simdjson_status(const uint8_t *input, size_t length) {
  uint8_t storage[512];
  struct flyology_json_cpp_bench_observation observation;
  const uint64_t padding = flyology_json_bench_simdjson_padding();

  if (length + padding > sizeof(storage)) {
    return FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT;
  }
  memcpy(storage, input, length);
  memset(storage + length, 0, (size_t)padding);
  return flyology_json_bench_simdjson_dom(
      storage, (uint64_t)length, (uint64_t)length + padding, &observation);
}

static int rapidjson_status(const uint8_t *input, size_t length) {
  struct flyology_json_cpp_bench_observation observation;
  return flyology_json_bench_rapidjson_dom(
      input, (uint64_t)length, &observation);
}

static int rapidjson_events_status(const uint8_t *input, size_t length) {
  struct flyology_json_cpp_bench_observation observation;
  return flyology_json_bench_rapidjson_events(
      input, (uint64_t)length, &observation);
}

static int expect_both(const uint8_t *input, size_t length, int32_t status) {
  return simdjson_status(input, length) == status &&
         rapidjson_status(input, length) == status &&
         rapidjson_events_status(input, length) == status;
}

static int expect_simdjson(const uint8_t *input, size_t length, int32_t status) {
  return simdjson_status(input, length) == status;
}

int main(void) {
  static const uint8_t valid[] = "{\"a\":[null,true,-1,1.5,\"x\"]}";
  static const uint8_t duplicate[] = "{\"a\":1,\"\\u0061\":2}";
  static const uint8_t malformed[] = "[";
  static const uint8_t bom[] = "\xef\xbb\xbfnull";
  static const uint8_t bad_utf8[] = {'\"', 0xc0, 0xaf, '\"'};
  static const uint8_t raw_control[] = {'\"', '\n', '\"'};
  static const uint8_t unpaired[] = "\"\\uD800\"";
  static const uint8_t comment[] = "/*x*/null";
  static const uint8_t trailing_comma[] = "[0,]";
  static const uint8_t leading_plus[] = "+1";
  static const uint8_t leading_zero[] = "01";
  static const uint8_t nonfinite[] = "NaN";
  uint8_t padded[sizeof(valid) - 1 + 64];
  uint8_t original[sizeof(padded)];
  struct flyology_json_cpp_bench_observation simd = {17, 19, 23, 29, 31};
  struct flyology_json_cpp_bench_observation rapid = {17, 19, 23, 29, 31};
  struct flyology_json_cpp_bench_observation events = {17, 19, 23, 29, 31};
  simdjson_function simd_symbol = flyology_json_bench_simdjson_dom;
  rapidjson_function rapid_symbol = flyology_json_bench_rapidjson_dom;
  rapidjson_function events_symbol = flyology_json_bench_rapidjson_events;
  const uint64_t padding = flyology_json_bench_simdjson_padding();

  if (simd_symbol == NULL || rapid_symbol == NULL || events_symbol == NULL ||
      padding != 64) {
    return 1;
  }
  memcpy(padded, valid, sizeof(valid) - 1);
  memset(padded + sizeof(valid) - 1, 0, (size_t)padding);
  memcpy(original, padded, sizeof(padded));

  if (simd_symbol(padded, sizeof(valid) - 1, sizeof(padded), &simd) !=
          FLYOLOGY_JSON_CPP_BENCH_OK ||
      rapid_symbol(valid, sizeof(valid) - 1, &rapid) !=
          FLYOLOGY_JSON_CPP_BENCH_OK ||
      events_symbol(valid, sizeof(valid) - 1, &events) !=
          FLYOLOGY_JSON_CPP_BENCH_OK ||
      simd.checksum != rapid.checksum || simd.event_count != 10 ||
      simd.scalar_count != 5 || simd.member_name_count != 1 ||
      simd.input_bytes != sizeof(valid) - 1 || events.event_count != 10 ||
      events.scalar_count != 5 || events.member_name_count != 1 ||
      events.input_bytes != sizeof(valid) - 1 ||
      memcmp(padded, original, sizeof(padded)) != 0) {
    return 2;
  }

  simd = (struct flyology_json_cpp_bench_observation){17, 19, 23, 29, 31};
  rapid = simd;
  if (simd_symbol(malformed, sizeof(malformed) - 1,
                  sizeof(malformed) - 1, &simd) !=
          FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT ||
      memcmp(&simd, &rapid, sizeof(simd)) != 0) {
    return 3;
  }

  memset(padded, 0, sizeof(padded));
  memcpy(padded, malformed, sizeof(malformed) - 1);
  events = rapid;
  if (simd_symbol(padded, sizeof(malformed) - 1,
                  sizeof(malformed) - 1 + padding, &simd) !=
          FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR ||
      memcmp(&simd, &rapid, sizeof(simd)) != 0 ||
      rapid_symbol(malformed, sizeof(malformed) - 1, &rapid) !=
          FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR ||
      rapid.checksum != 17 || rapid.event_count != 19 ||
      rapid.scalar_count != 23 || rapid.member_name_count != 29 ||
      rapid.input_bytes != 31 ||
      events_symbol(malformed, sizeof(malformed) - 1, &events) !=
          FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR ||
      memcmp(&events, &rapid, sizeof(events)) != 0) {
    return 4;
  }

  if (simd_symbol(NULL, 0, padding, &simd) !=
          FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT ||
      rapid_symbol(NULL, 0, &rapid) !=
          FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT ||
      events_symbol(NULL, 0, &events) !=
          FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT ||
      simd_symbol(padded, 1, sizeof(padded), NULL) !=
          FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT ||
      rapid_symbol(valid, sizeof(valid) - 1, NULL) !=
          FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT ||
      events_symbol(valid, sizeof(valid) - 1, NULL) !=
          FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT) {
    return 5;
  }

  if (!expect_both((const uint8_t *)"null", 4, FLYOLOGY_JSON_CPP_BENCH_OK)) {
    return 60;
  }
  if (!expect_both(duplicate, sizeof(duplicate) - 1,
                   FLYOLOGY_JSON_CPP_BENCH_OK)) {
    return 61;
  }
  if (!expect_simdjson(bom, sizeof(bom) - 1,
                       FLYOLOGY_JSON_CPP_BENCH_OK) ||
      rapidjson_status(bom, sizeof(bom) - 1) !=
          FLYOLOGY_JSON_CPP_BENCH_OK ||
      rapidjson_events_status(bom, sizeof(bom) - 1) !=
          FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR) {
    return 62;
  }
  if (!expect_both(bad_utf8, sizeof(bad_utf8),
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 63;
  }
  if (!expect_both(raw_control, sizeof(raw_control),
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 64;
  }
  if (!expect_both(unpaired, sizeof(unpaired) - 1,
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 65;
  }
  if (!expect_both(comment, sizeof(comment) - 1,
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 66;
  }
  if (!expect_both(trailing_comma, sizeof(trailing_comma) - 1,
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 67;
  }
  if (!expect_both(leading_plus, sizeof(leading_plus) - 1,
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 68;
  }
  if (!expect_both(leading_zero, sizeof(leading_zero) - 1,
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 69;
  }
  if (!expect_both(nonfinite, sizeof(nonfinite) - 1,
                   FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR)) {
    return 70;
  }

  return 0;
}
