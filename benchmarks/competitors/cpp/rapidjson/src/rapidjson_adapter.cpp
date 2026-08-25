/* Copyright (c) 2026 Yurii Rashkovskii
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#include "flyology_json_cpp_bench_adapters.h"

#include "rapidjson/document.h"
#include "rapidjson/memorystream.h"
#include "rapidjson/reader.h"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/writer.h"

#include <cstring>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <string_view>

namespace {

using Observation = flyology_json_cpp_bench_observation;
using WriteObservation = flyology_json_cpp_bench_write_observation;

static_assert(sizeof(Observation) == 40);
static_assert(alignof(Observation) == alignof(uint64_t));
static_assert(offsetof(Observation, checksum) == 0);
static_assert(offsetof(Observation, event_count) == 8);
static_assert(offsetof(Observation, scalar_count) == 16);
static_assert(offsetof(Observation, member_name_count) == 24);
static_assert(offsetof(Observation, input_bytes) == 32);
static_assert(sizeof(WriteObservation) == 16);
static_assert(alignof(WriteObservation) == alignof(uint64_t));
static_assert(offsetof(WriteObservation, output_bytes) == 0);
static_assert(offsetof(WriteObservation, checksum) == 8);

struct PreparedWrite final {
  rapidjson::Document document;
};

uint64_t fnv1a64(const char *data, size_t length) {
  uint64_t result = UINT64_C(0xcbf29ce484222325);
  for (size_t index = 0; index < length; ++index) {
    result = (result ^ static_cast<unsigned char>(data[index])) *
             UINT64_C(0x100000001b3);
  }
  return result;
}

bool serialize(const PreparedWrite &prepared,
               rapidjson::StringBuffer &output,
               WriteObservation &observation) {
  rapidjson::Writer<rapidjson::StringBuffer> writer(output);
  if (!prepared.document.Accept(writer) || !writer.IsComplete()) {
    return false;
  }
  observation = {static_cast<uint64_t>(output.GetSize()),
                 fnv1a64(output.GetString(), output.GetSize())};
  return true;
}

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

class EventHandler final
    : public rapidjson::BaseReaderHandler<rapidjson::UTF8<>, EventHandler> {
public:
  explicit EventHandler(uint64_t input_bytes)
      : result_{UINT64_C(0xcbf29ce484222325), 0, 0, 0, input_bytes} {}

  bool Null() {
    scalar(1);
    return true;
  }
  bool Bool(bool value) {
    scalar(value ? 3 : 2);
    return true;
  }
  bool Int(int) { return unexpected_converted_number(); }
  bool Uint(unsigned) { return unexpected_converted_number(); }
  bool Int64(int64_t) { return unexpected_converted_number(); }
  bool Uint64(uint64_t) { return unexpected_converted_number(); }
  bool Double(double) { return unexpected_converted_number(); }
  bool RawNumber(const char *, rapidjson::SizeType length, bool) {
    result_.scalar_count += 1;
    mix_event(result_, 4, length);
    return true;
  }
  bool String(const char *, rapidjson::SizeType length, bool) {
    result_.scalar_count += 1;
    mix_event(result_, 7, length);
    return true;
  }
  bool StartObject() {
    mix_event(result_, 10);
    return true;
  }
  bool Key(const char *, rapidjson::SizeType length, bool) {
    result_.member_name_count += 1;
    mix_event(result_, 11, length);
    return true;
  }
  bool EndObject(rapidjson::SizeType members) {
    mix_event(result_, 12, members);
    return true;
  }
  bool StartArray() {
    mix_event(result_, 8);
    return true;
  }
  bool EndArray(rapidjson::SizeType elements) {
    mix_event(result_, 9, elements);
    return true;
  }

  const Observation &result() const { return result_; }

private:
  void scalar(uint64_t kind) {
    result_.scalar_count += 1;
    mix_event(result_, kind);
  }

  static bool unexpected_converted_number() { return false; }

  Observation result_;
};

rapidjson::Reader &event_reader() {
  static thread_local rapidjson::Reader reader;
  return reader;
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

extern "C" int32_t flyology_json_bench_rapidjson_events(
    const uint8_t *input,
    uint64_t length,
    Observation *observation) {
  if (input == nullptr || observation == nullptr ||
      length > std::numeric_limits<size_t>::max()) {
    return FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT;
  }

  try {
    rapidjson::MemoryStream stream(reinterpret_cast<const char *>(input),
                                   static_cast<size_t>(length));
    EventHandler handler(length);
    constexpr unsigned flags = rapidjson::kParseValidateEncodingFlag |
                               rapidjson::kParseNumbersAsStringsFlag;
    if (!event_reader().Parse<flags>(stream, handler)) {
      return FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR;
    }
    Observation result = handler.result();
    result.checksum ^= length;
    *observation = result;
    return FLYOLOGY_JSON_CPP_BENCH_OK;
  } catch (const std::bad_alloc &) {
    return FLYOLOGY_JSON_CPP_BENCH_ALLOCATION_FAILURE;
  } catch (...) {
    return FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR;
  }
}

extern "C" int32_t flyology_json_bench_rapidjson_prepare_write(
    const uint8_t *input,
    uint64_t length,
    void **prepared) {
  if (input == nullptr || prepared == nullptr ||
      length > std::numeric_limits<size_t>::max()) {
    return FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT;
  }

  try {
    std::unique_ptr<PreparedWrite> result(new PreparedWrite);
    result->document.Parse<rapidjson::kParseValidateEncodingFlag>(
        reinterpret_cast<const char *>(input), static_cast<size_t>(length));
    if (result->document.HasParseError()) {
      return FLYOLOGY_JSON_CPP_BENCH_PARSE_ERROR;
    }
    *prepared = result.release();
    return FLYOLOGY_JSON_CPP_BENCH_OK;
  } catch (const std::bad_alloc &) {
    return FLYOLOGY_JSON_CPP_BENCH_ALLOCATION_FAILURE;
  } catch (...) {
    return FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR;
  }
}

extern "C" int32_t flyology_json_bench_rapidjson_write_dom(
    const void *prepared,
    WriteObservation *observation) {
  if (prepared == nullptr || observation == nullptr) {
    return FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT;
  }

  try {
    rapidjson::StringBuffer output;
    WriteObservation result{};
    if (!serialize(*static_cast<const PreparedWrite *>(prepared), output, result)) {
      return FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR;
    }
    *observation = result;
    return FLYOLOGY_JSON_CPP_BENCH_OK;
  } catch (const std::bad_alloc &) {
    return FLYOLOGY_JSON_CPP_BENCH_ALLOCATION_FAILURE;
  } catch (...) {
    return FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR;
  }
}

extern "C" int32_t flyology_json_bench_rapidjson_check_write(
    const void *prepared,
    const uint8_t *expected,
    uint64_t expected_length,
    WriteObservation *observation,
    int32_t *matches) {
  if (prepared == nullptr || observation == nullptr || matches == nullptr ||
      (expected == nullptr && expected_length != 0) ||
      expected_length > std::numeric_limits<size_t>::max()) {
    return FLYOLOGY_JSON_CPP_BENCH_INVALID_ARGUMENT;
  }

  try {
    rapidjson::StringBuffer output;
    WriteObservation result{};
    if (!serialize(*static_cast<const PreparedWrite *>(prepared), output, result)) {
      return FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR;
    }
    const size_t length = static_cast<size_t>(expected_length);
    const bool equal = output.GetSize() == length &&
                       (length == 0 ||
                        std::memcmp(output.GetString(), expected, length) == 0);
    *observation = result;
    *matches = equal ? 1 : 0;
    return FLYOLOGY_JSON_CPP_BENCH_OK;
  } catch (const std::bad_alloc &) {
    return FLYOLOGY_JSON_CPP_BENCH_ALLOCATION_FAILURE;
  } catch (...) {
    return FLYOLOGY_JSON_CPP_BENCH_INTERNAL_ERROR;
  }
}

extern "C" void flyology_json_bench_rapidjson_release_write(void *prepared) {
  delete static_cast<PreparedWrite *>(prepared);
}
