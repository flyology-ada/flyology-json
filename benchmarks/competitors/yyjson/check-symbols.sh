#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
track=${FLYOLOGY_JSON_BENCH_TRACK:-portable}

case "$track" in
    portable | native) ;;
    *)
        printf 'FLYOLOGY_JSON_BENCH_TRACK must be portable or native\n' >&2
        exit 2
        ;;
esac

executable="$root/bin/$track/flyology_json-benchmark_yyjson_tests"

if [ ! -x "$executable" ]; then
    printf 'missing %s; build yyjson_adapter_tests.gpr first\n' "$executable" >&2
    exit 1
fi

symbols=$(nm "$executable")

printf '%s\n' "$symbols" | grep '[[:space:]]_\{0,1\}yyjson_read_opts$' >/dev/null
printf '%s\n' "$symbols" | grep '[[:space:]]_\{0,1\}yyjson_write_opts$' >/dev/null
printf '%s\n' "$symbols" | grep '[[:space:]]_\{0,1\}flyology_bench_yyjson_doc_free$' >/dev/null
# ELF linkers may retain a symbol-version suffix such as @GLIBC_2.2.5 on the
# undefined ISO C free import.  Mach-O instead prefixes the symbol with `_`.
printf '%s\n' "$symbols" \
    | grep -E '[[:space:]]_?free(@[^[:space:]]+)?$' >/dev/null

if printf '%s\n' "$symbols" | grep '[[:space:]]_\{0,1\}flyology_bench_yyjson_read' >/dev/null; then
    printf 'yyjson read is hidden behind a shim instead of imported directly\n' >&2
    exit 1
fi

if printf '%s\n' "$symbols" | grep '[[:space:]]_\{0,1\}flyology_bench_yyjson_write' >/dev/null; then
    printf 'yyjson write is hidden behind a shim instead of imported directly\n' >&2
    exit 1
fi

printf 'yyjson %s direct-import symbol check passed\n' "$track"
