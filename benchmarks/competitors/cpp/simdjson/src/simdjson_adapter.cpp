/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#include "flyology_json_cpp_bench_adapters.h"
#include "simdjson.h"

#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <string_view>

namespace {

using Observation = flyology_json_cpp_bench_observation;

static_assert(sizeof(Observation) == 40);
static_assert(alignof(Observation) == alignof(uint64_t));
static_assert(offsetof(Observation, checksum) == 0);
static_assert(offsetof(Observation, event_count) == 8);
static_assert(offsetof(Observation, scalar_count) == 16);
static_assert(offsetof(Observation, member_name_count) == 24);
static_assert(offsetof(Observation, input_bytes) == 32);

void mix_bytes(Observation &result, uint64_t kind, std::string_view bytes) {
  result.event_count += 1;
  result.checksum = result.checksum * UINT64_C(0x9e3779b185ebca87) + kind;
  result.checksum += static_cast<uint64_t>(bytes.size());
  for (unsigned char byte : bytes) {
    result.checksum = result.checksum * UINT64_C(0x100000001b3) + byte;
  }
}

void mix_event(Observation &result, uint64_t kind, uint64_t count = 0) {
  result.event_count += 1;
  result.checksum = result.checksum * UINT64_C(0x9e3779b185ebca87) + kind + count;
}

void traverse(simdjson::dom::element value, Observation &result) {
  switch (value.type()) {
  case simdjson::dom::element_type::ARRAY: {
    const simdjson::dom::array array = value.get_array();
    mix_event(result, 8, array.size());
    for (simdjson::dom::element child : array) {
      traverse(child, result);
    }
    mix_event(result, 9, array.size());
    return;
  }
  case simdjson::dom::element_type::OBJECT: {
    const simdjson::dom::object object = value.get_object();
    mix_event(result, 10, object.size());
    for (const simdjson::dom::key_value_pair field : object) {
      result.member_name_count += 1;
      mix_bytes(result, 11, field.key);
      traverse(field.value, result);
    }
    mix_event(result, 12, object.size());
    return;
  }
  case simdjson::dom::element_type::INT64:
  case simdjson::dom::element_type::UINT64:
  case simdjson::dom::element_type::DOUBLE:
  case simdjson::dom::element_type::BIGINT:
    result.scalar_count += 1;
    mix_event(result, 4);
    return;
  case simdjson::dom::element_type::STRING:
    result.scalar_count += 1;
    mix_bytes(result, 7, value.get_string());
    return;
  case simdjson::dom::element_type::BOOL:
    result.scalar_count += 1;
    mix_event(result, value.get_bool() ? 3 : 2);
    return;
  case simdjson::dom::element_type::NULL_VALUE:
    result.scalar_count += 1;
    mix_event(result, 1);
    return;
  }
}

} // namespace

extern "C" uint64_t flyology_json_bench_simdjson_padding(void) {
  return simdjson::SIMDJSON_PADDING;
}

extern "C" int32_t flyology_json_bench_simdjson_dom(
    const uint8_t *input,
    uint64_t length,
    uint64_t capacity,
    Observation *observation) {
  if (input == nullptr || observation == nullptr || length > capacity ||
      length > std::numeric_limits<size_t>::max() ||
      capacity > std::numeric_limits<size_t>::max() ||
      capacity - length < simdjson::SIMDJSON_PADDING) {
    return FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT;
  }

  try {
    //  The maintained harness performs one untimed preflight call for each
    //  population.  Reusing this thread-local parser keeps its ordinary DOM
    //  buffers outside subsequent timed initialization and cleanup while
    //  retaining no caller input.
    static thread_local simdjson::dom::parser parser;
    simdjson::dom::element document;
    const simdjson::error_code error =
        parser.parse(input, static_cast<size_t>(length), false).get(document);
    if (error != simdjson::SUCCESS) {
      return FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR;
    }

    Observation result = {
        UINT64_C(0xcbf29ce484222325), 0, 0, 0, length};
    traverse(document, result);
    result.checksum ^= length;
    *observation = result;
    return FLYOLOGY_JSON_CPP_BENCH_OK;
  } catch (const std::bad_alloc &) {
    return FLYOLOGY_JSON_CPP_BENCH_ALLOCATION_FAILURE;
  } catch (...) {
    return FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR;
  }
}
