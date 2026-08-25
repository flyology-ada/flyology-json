#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$#" -gt 1 ]; then
    echo "usage: ./check-symbols.sh [portable|native]" >&2
    exit 2
fi

tuning=${1:-${FLYOLOGY_JSON_BENCH_TUNING:-portable}}
case "$tuning" in
    portable | native) ;;
    *)
        echo "track must be portable or native" >&2
        exit 2
        ;;
esac
executable="$root/bin/$tuning/flyology_json-benchmark_cpp_tests"

if [ ! -x "$executable" ]; then
    echo "missing C++ adapter test executable for $tuning" >&2
    exit 1
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/flyology-json-cpp-symbols.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

nm -g "$executable" \
    | awk '{print $NF}' \
    | sed 's/^_//' \
    | grep '^flyology_json_bench_' \
    | LC_ALL=C sort -u >"$temporary/actual"

cat >"$temporary/expected" <<'SYMBOLS'
flyology_json_bench_rapidjson_check_write
flyology_json_bench_rapidjson_dom
flyology_json_bench_rapidjson_events
flyology_json_bench_rapidjson_prepare_write
flyology_json_bench_rapidjson_release_write
flyology_json_bench_rapidjson_write_dom
flyology_json_bench_simdjson_dom
flyology_json_bench_simdjson_padding
SYMBOLS

diff -u "$temporary/expected" "$temporary/actual"
echo "C++ adapter symbol check passed ($tuning)"
