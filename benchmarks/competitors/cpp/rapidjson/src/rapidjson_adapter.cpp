/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#include "flyology_json_cpp_bench_adapters.h"

#include "rapidjson/document.h"

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

void traverse(const rapidjson::Value &value, Observation &result) {
  if (value.IsArray()) {
    mix_event(result, 8, value.Size());
    for (const rapidjson::Value &child : value.GetArray()) {
      traverse(child, result);
    }
    mix_event(result, 9, value.Size());
  } else if (value.IsObject()) {
    mix_event(result, 10, value.MemberCount());
    for (rapidjson::Value::ConstMemberIterator field = value.MemberBegin();
         field != value.MemberEnd(); ++field) {
      result.member_name_count += 1;
      mix_bytes(result, 11,
                std::string_view(field->name.GetString(), field->name.GetStringLength()));
      traverse(field->value, result);
    }
    mix_event(result, 12, value.MemberCount());
  } else if (value.IsString()) {
    result.scalar_count += 1;
    mix_bytes(result, 7,
              std::string_view(value.GetString(), value.GetStringLength()));
  } else if (value.IsBool()) {
    result.scalar_count += 1;
    mix_event(result, value.GetBool() ? 3 : 2);
  } else if (value.IsNull()) {
    result.scalar_count += 1;
    mix_event(result, 1);
  } else {
    result.scalar_count += 1;
    mix_event(result, 4);
  }
}

} // namespace

extern "C" int32_t flyology_json_bench_rapidjson_dom(
    const uint8_t *input,
    uint64_t length,
    Observation *observation) {
  if (input == nullptr || observation == nullptr ||
      length > std::numeric_limits<size_t>::max()) {
    return FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT;
  }

  try {
    rapidjson::Document document;
    document.Parse<rapidjson::kParseValidateEncodingFlag>(
        reinterpret_cast<const char *>(input), static_cast<size_t>(length));
    if (document.HasParseError()) {
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
