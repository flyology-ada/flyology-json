#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
benchmarks=$(CDPATH= cd -- "$root/../.." && pwd)

if [ "$#" -gt 1 ]; then
    echo "usage: ./test.sh [portable|native]" >&2
    exit 2
fi

tuning=${1:-${FLYOLOGY_JSON_BENCH_TUNING:-portable}}
if [ "$#" -eq 1 ] && [ -n "${FLYOLOGY_JSON_BENCH_TUNING:-}" ] && \
   [ "$1" != "$FLYOLOGY_JSON_BENCH_TUNING" ]; then
    echo "track argument conflicts with FLYOLOGY_JSON_BENCH_TUNING" >&2
    exit 2
fi

case "$tuning" in
    portable)
        cpu_switch=
        ;;
    native)
        case "$(uname -m)" in
            arm64 | aarch64) cpu_switch=-mcpu=native ;;
            *) cpu_switch=-march=native ;;
        esac
        ;;
    *)
        echo "FLYOLOGY_JSON_BENCH_TUNING must be portable or native" >&2
        exit 2
        ;;
esac

"$root/simdjson/acquire.sh"
"$root/rapidjson/acquire.sh"
"$root/simdjson/verify.sh"
"$root/rapidjson/verify.sh"
"$root/validate-capabilities.sh"

(
    cd "$benchmarks"
    env FLYOLOGY_JSON_BENCH_TUNING="$tuning" \
        FLYOLOGY_JSON_BENCH_NATIVE_SWITCH="${cpu_switch:--march=native}" \
        alr exec -- gprbuild -f -p -P competitors/cpp/cpp_adapter_tests.gpr
)

"$root/bin/$tuning/flyology_json-benchmark_cpp_tests"
"$root/check-symbols.sh" "$tuning"

build="$root/build/$tuning"
mkdir -p "$build"
cxx_flags="-std=c++17 -O3"
if [ -n "$cpu_switch" ]; then
    cxx_flags="$cxx_flags $cpu_switch"
fi

# shellcheck disable=SC2086
c++ $cxx_flags -Wall -Wextra -Werror \
    -I"$root/include" -I"$root/simdjson/upstream" \
    -c "$root/simdjson/src/simdjson_adapter.cpp" -o "$build/simdjson_adapter.o"
# shellcheck disable=SC2086
c++ $cxx_flags -DNDEBUG -I"$root/simdjson/upstream" \
    -c "$root/simdjson/upstream/simdjson.cpp" -o "$build/simdjson.o"
# shellcheck disable=SC2086
c++ $cxx_flags -Wall -Wextra -Werror \
    -I"$root/include" -I"$root/rapidjson/upstream/include" \
    -c "$root/rapidjson/src/rapidjson_adapter.cpp" -o "$build/rapidjson_adapter.o"
cc -std=c11 -O2 -Wall -Wextra -Werror -I"$root/include" \
    -c "$root/tests/abi_smoke.c" -o "$build/abi_smoke.o"
c++ "$build/abi_smoke.o" "$build/simdjson_adapter.o" "$build/simdjson.o" \
    "$build/rapidjson_adapter.o" -o "$build/abi-smoke"
"$build/abi-smoke"

echo "C++ competitor adapter tests passed ($tuning)"
