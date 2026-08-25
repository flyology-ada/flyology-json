#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
benchmarks=$(CDPATH= cd -- "$root/../.." && pwd)

if [ "$#" -gt 1 ]; then
    echo "usage: ./test.sh [portable|native]" >&2
    exit 2
fi

tracks=${1:-"portable native"}
case "$tracks" in
    portable | native | "portable native") ;;
    *)
        echo "track must be portable or native" >&2
        exit 2
        ;;
esac

"$root/acquire.sh"
"$root/verify.sh"

case "$(uname -m)" in
    arm64 | aarch64)
        native_cpu_flag=mcpu_native
        native_switch=-mcpu=native
        ;;
    x86_64 | amd64)
        native_cpu_flag=march_native
        native_switch=-march=native
        ;;
    *)
        if [ "$tracks" != portable ]; then
            echo "unsupported native benchmark architecture: $(uname -m)" >&2
            exit 2
        fi
        native_cpu_flag=march_native
        native_switch=-march=native
        ;;
esac

for track in $tracks
do
    (
        cd "$benchmarks"
        FLYOLOGY_JSON_BENCH_TRACK=$track \
        FLYOLOGY_JSON_BENCH_NATIVE_CPU_FLAG=$native_cpu_flag \
          alr exec -- gprbuild -f -p -P competitors/yyjson/yyjson_adapter_tests.gpr
        FLYOLOGY_JSON_BENCH_TUNING=$track \
        FLYOLOGY_JSON_BENCH_NATIVE_SWITCH=$native_switch \
          alr exec -- gprbuild -f -p \
            -P competitors/yyjson/yyjson_writer_benchmarks.gpr
    )

    "$root/bin/$track/flyology_json-benchmark_yyjson_tests"
    FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY=true \
      "$root/writer_bin/$track/flyology_json-benchmark_yyjson_writer_benchmark"
    FLYOLOGY_JSON_BENCH_TRACK=$track "$root/check-symbols.sh"
done

"$root/validate-capability.sh"
"$root/capabilities.sh"
