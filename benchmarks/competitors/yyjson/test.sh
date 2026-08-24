#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
benchmarks=$(CDPATH= cd -- "$root/../.." && pwd)

"$root/acquire.sh"
"$root/verify.sh"

case "$(uname -m)" in
    arm64 | aarch64) native_cpu_flag=mcpu_native ;;
    *) native_cpu_flag=march_native ;;
esac

for track in portable native
do
    (
        cd "$benchmarks"
        FLYOLOGY_JSON_BENCH_TRACK=$track \
        FLYOLOGY_JSON_BENCH_NATIVE_CPU_FLAG=$native_cpu_flag \
          alr exec -- gprbuild -f -p -P competitors/yyjson/yyjson_adapter_tests.gpr
    )

    "$root/bin/$track/flyology_json-benchmark_yyjson_tests"
    FLYOLOGY_JSON_BENCH_TRACK=$track "$root/check-symbols.sh"
done

"$root/validate-capability.sh"
"$root/capabilities.sh"
