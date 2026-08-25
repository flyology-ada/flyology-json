#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$#" -ne 1 ]; then
  echo "usage: ./scripts/test-benchmark-competitors.sh portable|native" >&2
  exit 2
fi

track=$1
case "$track" in
  portable)
    native_switch=not-applied
    ;;
  native)
    case "$(uname -m)" in
      arm64 | aarch64) native_switch=-mcpu=native ;;
      x86_64 | amd64) native_switch=-march=native ;;
      *)
        echo "unsupported native benchmark architecture: $(uname -m)" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "benchmark track must be portable or native" >&2
    exit 2
    ;;
esac

cd "$project_root/benchmarks/comparison"
npm ci --ignore-scripts
npm test
npm run validate:schemas
npm run verify:tooling

cd "$project_root"
./scripts/verify-benchmark-sources.sh

for adapter in yyjson cpp rust; do
  "$project_root/benchmarks/competitors/$adapter/test.sh" "$track"
done

cd "$project_root/benchmarks/comparison"
npm run validate:capabilities

case "$(uname -s)" in
  Darwin) system_libraries= ;;
  Linux) system_libraries='-ldl -lpthread -lm' ;;
  *)
    echo "unsupported comparison benchmark host: $(uname -s)" >&2
    exit 2
    ;;
esac

preflight_output=$(mktemp "${TMPDIR:-/tmp}/flyology-json-preflight.XXXXXX")
parser_preflight_output=$(mktemp "${TMPDIR:-/tmp}/flyology-json-parser-preflight.XXXXXX")
selection_output=$(mktemp "${TMPDIR:-/tmp}/flyology-json-selection.XXXXXX")
selection_error=$(mktemp "${TMPDIR:-/tmp}/flyology-json-selection-error.XXXXXX")
trap 'rm -f "$preflight_output" "$parser_preflight_output" "$selection_output" "$selection_error"' EXIT HUP INT TERM

cd "$project_root/benchmarks"
FLYOLOGY_JSON_BENCH_TUNING="$track" \
FLYOLOGY_JSON_BENCH_NATIVE_SWITCH="$native_switch" \
  alr build --release
FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
  bin/flyology_json-parser_benchmark >"$parser_preflight_output"
node "$project_root/scripts/validate-parser-preflight.mjs" "$parser_preflight_output"
FLYOLOGY_JSON_BENCH_TUNING="$track" \
FLYOLOGY_JSON_BENCH_NATIVE_SWITCH="$native_switch" \
FLYOLOGY_JSON_BENCH_SYSTEM_LIBRARIES="$system_libraries" \
RUST_ADAPTER_DIR="$project_root/benchmarks/competitors/rust/target/$track/release" \
  alr exec -- gprbuild -f -p -P flyology_json_comparison_benchmarks.gpr
FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
FLYOLOGY_JSON_BENCH_IMPLEMENTATION= \
FLYOLOGY_JSON_BENCH_FIXTURE= \
  "comparison_bin/$track/flyology_json-comparison_benchmark" >"$preflight_output"
node "$project_root/scripts/validate-comparison-preflight.mjs" "$preflight_output"
FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
FLYOLOGY_JSON_BENCH_IMPLEMENTATION=flyology_json \
FLYOLOGY_JSON_BENCH_FIXTURE=large_array \
  "comparison_bin/$track/flyology_json-comparison_benchmark" >"$selection_output"
test "$(wc -l <"$selection_output" | tr -d ' ')" -eq 1
grep -Fqx 'implementation=flyology_json fixture=large_array value=14497054742' \
  "$selection_output"
FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
FLYOLOGY_JSON_BENCH_IMPLEMENTATION=rapidjson \
FLYOLOGY_JSON_BENCH_FIXTURE= \
  "comparison_bin/$track/flyology_json-comparison_benchmark" >"$selection_output"
test "$(wc -l <"$selection_output" | tr -d ' ')" -eq 8
test "$(grep -c '^implementation=rapidjson ' "$selection_output")" -eq 8
! grep -q '^implementation=rapidjson-sax ' "$selection_output"
FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
FLYOLOGY_JSON_BENCH_IMPLEMENTATION=simd-json \
FLYOLOGY_JSON_BENCH_FIXTURE= \
  "comparison_bin/$track/flyology_json-comparison_benchmark" >"$selection_output"
test "$(wc -l <"$selection_output" | tr -d ' ')" -eq 8
test "$(grep -c '^implementation=simd-json ' "$selection_output")" -eq 8
! grep -q '^implementation=simdjson ' "$selection_output"
FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
FLYOLOGY_JSON_BENCH_IMPLEMENTATION= \
FLYOLOGY_JSON_BENCH_FIXTURE=large_array \
  "comparison_bin/$track/flyology_json-comparison_benchmark" >"$selection_output"
test "$(wc -l <"$selection_output" | tr -d ' ')" -eq 8
test "$(grep -c ' fixture=large_array ' "$selection_output")" -eq 8
if FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
   FLYOLOGY_JSON_BENCH_IMPLEMENTATION=not-a-parser \
     "comparison_bin/$track/flyology_json-comparison_benchmark" \
     >"$selection_output" 2>"$selection_error"; then
  echo "unknown comparison implementation selector was accepted" >&2
  exit 1
fi
grep -Fq 'unknown FLYOLOGY_JSON_BENCH_IMPLEMENTATION' "$selection_error"
if FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
   FLYOLOGY_JSON_BENCH_IMPLEMENTATION=Flyology_JSON \
     "comparison_bin/$track/flyology_json-comparison_benchmark" \
     >"$selection_output" 2>"$selection_error"; then
  echo "case-folded comparison implementation selector was accepted" >&2
  exit 1
fi
grep -Fq 'unknown FLYOLOGY_JSON_BENCH_IMPLEMENTATION' "$selection_error"
if FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
   FLYOLOGY_JSON_BENCH_FIXTURE=' large_array' \
     "comparison_bin/$track/flyology_json-comparison_benchmark" \
     >"$selection_output" 2>"$selection_error"; then
  echo "whitespace-padded comparison fixture selector was accepted" >&2
  exit 1
fi
grep -Fq 'unknown FLYOLOGY_JSON_BENCH_FIXTURE' "$selection_error"
if FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
   FLYOLOGY_JSON_BENCH_IMPLEMENTATION=serde_json \
   FLYOLOGY_JSON_BENCH_FIXTURE=deep_nesting \
     "comparison_bin/$track/flyology_json-comparison_benchmark" \
     >"$selection_output" 2>"$selection_error"; then
  echo "unsupported comparison population selector was accepted" >&2
  exit 1
fi
grep -Fq 'selected comparison population is unsupported' "$selection_error"
FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=false \
FLYOLOGY_JSON_BENCH_OUTPUT=json \
FLYOLOGY_JSON_BENCH_IMPLEMENTATION=flyology_json \
FLYOLOGY_JSON_BENCH_FIXTURE=large_array \
  "comparison_bin/$track/flyology_json-comparison_benchmark" >"$selection_output"
test "$(wc -l <"$selection_output" | tr -d ' ')" -eq 1
grep -Fq '"name":"comparison/lane=parse_events/implementation=flyology_json/fixture=large_array/bytes=294913"' \
  "$selection_output"
