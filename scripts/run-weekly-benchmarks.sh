#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$#" -ne 2 ]; then
  echo "usage: ./scripts/run-weekly-benchmarks.sh portable|native OUTPUT_DIRECTORY" >&2
  exit 2
fi

track=$1
output_directory=$2
parser_executable="$project_root/benchmarks/bin/flyology_json-parser_benchmark"
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
comparison_executable="$project_root/benchmarks/comparison_bin/$track/flyology_json-comparison_benchmark"

mkdir -p "$output_directory/provenance/adapters"
mkdir -p "$output_directory/provenance/build"
mkdir -p "$output_directory/provenance/capabilities"
mkdir -p "$output_directory/fixtures"

if ! "$project_root/scripts/test-benchmark-competitors.sh" "$track" \
     >"$output_directory/competitor-build.log" 2>&1
then
  cat "$output_directory/competitor-build.log" >&2
  exit 1
fi
cat "$output_directory/competitor-build.log"

case "$(uname -s)" in
  Darwin) system_libraries= ;;
  Linux) system_libraries='-ldl -lpthread -lm' ;;
  *)
    echo "unsupported comparison benchmark host: $(uname -s)" >&2
    exit 2
    ;;
esac

(
  cd "$project_root/benchmarks"
  if ! FLYOLOGY_JSON_BENCH_TUNING="$track" \
       FLYOLOGY_JSON_BENCH_NATIVE_SWITCH="$native_switch" \
       alr build --release -- -f -p -v \
         >"$output_directory/parser-build.log" 2>&1
  then
    cat "$output_directory/parser-build.log" >&2
    exit 1
  fi
  cat "$output_directory/parser-build.log"
  FLYOLOGY_JSON_BENCH_TUNING="$track" \
    FLYOLOGY_JSON_BENCH_NATIVE_SWITCH="$native_switch" \
    FLYOLOGY_JSON_BENCH_OUTPUT=json \
    "$parser_executable" >"$output_directory/flyology-parser.jsonl"

  if ! FLYOLOGY_JSON_BENCH_TUNING="$track" \
       FLYOLOGY_JSON_BENCH_NATIVE_SWITCH="$native_switch" \
       FLYOLOGY_JSON_BENCH_SYSTEM_LIBRARIES="$system_libraries" \
       RUST_ADAPTER_DIR="$PWD/competitors/rust/target/$track/release" \
       alr exec -- gprbuild -f -p -v \
         -P flyology_json_comparison_benchmarks.gpr \
         >"$output_directory/comparison-build.log" 2>&1
  then
    cat "$output_directory/comparison-build.log" >&2
    exit 1
  fi
  cat "$output_directory/comparison-build.log"
  FLYOLOGY_JSON_BENCH_OUTPUT=json \
    FLYOLOGY_JSON_BENCH_FIXTURE_DIRECTORY="$output_directory/fixtures" \
    "$comparison_executable" \
    >"$output_directory/comparison-summary.jsonl" \
    2>"$output_directory/comparison-skips.txt"
)

node "$project_root/scripts/validate-parser-benchmarks.mjs" \
  "$output_directory/flyology-parser.jsonl"

node "$project_root/scripts/summarize-comparison-benchmarks.mjs" \
  "$track" "$output_directory/comparison-summary.jsonl" \
  >"$output_directory/comparison-summary.tsv"

expected_skip='skip lane=parse_dom implementation=serde_json fixture=deep_nesting reason=declared_depth_limit'
if [ "$(wc -l <"$output_directory/comparison-skips.txt" | tr -d ' ')" -ne 1 ] ||
   ! grep -Fqx "$expected_skip" "$output_directory/comparison-skips.txt"; then
  echo "comparison benchmark emitted an unexpected skip set" >&2
  exit 1
fi

node "$project_root/scripts/write-comparison-skip.mjs" \
  "$project_root" "$track" "$output_directory/comparison-skip.json"
(
  cd "$project_root/benchmarks/comparison"
  node validate-records.mjs skip.schema.json \
    "$output_directory/comparison-skip.json"
)

{
  printf 'classification=directional\n'
  printf 'track=%s\n' "$track"
  printf 'native_cpu_switch=%s\n' "$native_switch"
  printf 'commit=%s\n' "$(git -C "$project_root" rev-parse HEAD)"
  printf 'working_tree_status_begin\n'
  git -C "$project_root" status --short
  printf 'working_tree_status_end\n'
  uname -a
  if command -v sw_vers >/dev/null 2>&1; then
    sw_vers
  fi
  alr --version
  alr toolchain
  alr exec -- gprbuild --version
  alr exec -- gnat --version
  alr exec -- gcc --version
  alr exec -- g++ --version
  node --version
  npm --version
  rustc --version --verbose
  cargo --version
  cc --version
  c++ --version
  printf 'github_actions=%s\n' "${GITHUB_ACTIONS:-}"
  printf 'github_event_name=%s\n' "${GITHUB_EVENT_NAME:-}"
  printf 'github_workflow=%s\n' "${GITHUB_WORKFLOW:-}"
  printf 'github_job=%s\n' "${GITHUB_JOB:-}"
  printf 'github_run_id=%s\n' "${GITHUB_RUN_ID:-}"
  printf 'github_run_attempt=%s\n' "${GITHUB_RUN_ATTEMPT:-}"
  printf 'github_repository=%s\n' "${GITHUB_REPOSITORY:-}"
  printf 'runner_name=%s\n' "${RUNNER_NAME:-}"
  printf 'runner_os=%s\n' "${RUNNER_OS:-}"
  printf 'runner_arch=%s\n' "${RUNNER_ARCH:-}"
  printf 'runner_image_os=%s\n' "${ImageOS:-}"
  printf 'runner_image_version=%s\n' "${ImageVersion:-}"
  if command -v lscpu >/dev/null 2>&1; then
    lscpu
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null || true
    sysctl -n hw.model 2>/dev/null || true
    sysctl -n hw.logicalcpu 2>/dev/null || true
  fi
} >"$output_directory/environment.txt"

cp "$project_root/benchmarks/comparison/capability.schema.json" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/result.schema.json" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/skip.schema.json" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/sources.lock.tsv" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/licenses.lock.tsv" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/tooling-licenses.lock.tsv" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/README.md" \
  "$output_directory/provenance/comparison-README.md"
cp "$project_root/benchmarks/README.md" \
  "$output_directory/provenance/benchmark-README.md"
cp "$project_root/benchmarks/comparison/ci-protocol.md" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/validate-records.mjs" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/strict-json.mjs" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/node-toolchain.mjs" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/package.json" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/package-lock.json" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/competitors/rust/Cargo.lock" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/competitors/rust/Cargo.toml" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/alire/alire.lock" \
  "$output_directory/provenance/benchmark-alire.lock"
cp "$project_root/benchmarks/flyology_json_comparison_benchmarks.gpr" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/flyology_json_parser_benchmarks.gpr" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/src/flyology_json-comparison_benchmark.ads" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/src/flyology_json-comparison_benchmark.adb" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/src/flyology_json-parser_benchmark.ads" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/src/flyology_json-parser_benchmark.adb" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/parser-matrix.mjs" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/comparison/comparison-matrix.mjs" \
  "$output_directory/provenance/"
cp "$project_root/scripts/summarize-comparison-benchmarks.mjs" \
  "$output_directory/provenance/"
cp "$project_root/scripts/validate-parser-benchmarks.mjs" \
  "$output_directory/provenance/"
cp "$project_root/scripts/validate-parser-preflight.mjs" \
  "$output_directory/provenance/"
cp "$project_root/scripts/validate-comparison-preflight.mjs" \
  "$output_directory/provenance/"
cp "$project_root/scripts/write-comparison-skip.mjs" \
  "$output_directory/provenance/"
cp "$project_root/scripts/test-benchmark-competitors.sh" \
  "$output_directory/provenance/"
cp "$project_root/scripts/write-benchmark-manifest.sh" \
  "$output_directory/provenance/"
cp "$project_root/benchmarks/competitors/rust/test.sh" \
  "$output_directory/provenance/rust-test.sh"
cp "$parser_executable" \
  "$output_directory/provenance/build/"
cp "$comparison_executable" \
  "$output_directory/provenance/build/"
cp "$project_root/benchmarks/competitors/rust/target/$track/release/libflyology_json_rust_bench_adapters.a" \
  "$output_directory/provenance/build/"
cp "$project_root/benchmarks/competitors/cpp/include/flyology_json_cpp_bench_adapters.h" \
  "$output_directory/provenance/adapters/"
cp "$project_root/benchmarks/competitors/cpp/rapidjson/src/rapidjson_adapter.cpp" \
  "$output_directory/provenance/adapters/"
cp "$project_root/benchmarks/competitors/cpp/simdjson/src/simdjson_adapter.cpp" \
  "$output_directory/provenance/adapters/"
cp "$project_root/benchmarks/competitors/rust/src/lib.rs" \
  "$output_directory/provenance/adapters/rust-lib.rs"
cp "$project_root/benchmarks/competitors/yyjson/src/flyology_json-benchmark_yyjson.ads" \
  "$output_directory/provenance/adapters/"
cp "$project_root/benchmarks/competitors/yyjson/src/flyology_json-benchmark_yyjson.adb" \
  "$output_directory/provenance/adapters/"
cp "$project_root/benchmarks/competitors/yyjson/src/flyology_json_bench_yyjson_free.c" \
  "$output_directory/provenance/adapters/"
cp "$project_root/benchmarks/competitors/yyjson/capability.json" \
  "$output_directory/provenance/capabilities/yyjson.json"
cp "$project_root/benchmarks/competitors/cpp/simdjson/capability.json" \
  "$output_directory/provenance/capabilities/simdjson.json"
cp "$project_root/benchmarks/competitors/cpp/rapidjson/capability.json" \
  "$output_directory/provenance/capabilities/rapidjson.json"
cp "$project_root/benchmarks/competitors/rust/capabilities/serde_json.json" \
  "$output_directory/provenance/capabilities/serde_json.json"
cp "$project_root/benchmarks/competitors/rust/capabilities/sonic_rs.json" \
  "$output_directory/provenance/capabilities/sonic_rs.json"
cp "$project_root/benchmarks/competitors/rust/capabilities/simd_json.json" \
  "$output_directory/provenance/capabilities/simd_json.json"

"$project_root/scripts/write-benchmark-manifest.sh" "$output_directory"
