# Duplicate-name parser performance gate

Date: 2026-08-24

This review gates the strict parser's caller-backed duplicate-name index. It is
before/after evidence for the implementation change, not the repository's
formal performance baseline. Sample distributions contained contention and
outliers. The cross-run statistic below is directional gate evidence, not a
stable population estimate or confidence interval. An isolated, power-locked
run remains required before retaining a formal baseline.

## Identities

- Baseline commit: `10728ab0064ff1bc2b377114b6a845c98c57be71`
- Current `parser_core.ads` SHA-256:
  `eeedc1a5d024f52fbd473ceff759818fe1ab85c42ce5be4d4e071b06f8ba7460`
- Current `parser_core.adb` SHA-256:
  `01ac35489fa60187dd099085e19475ffbca707272208a8901481da7c6469b88a`
- Current `parser_duplicates.ads` SHA-256:
  `baead2d59b69a5931dcb1493096bf8607e53aa6847a60e858f8c7ad952f5fd50`
- Current `parser_duplicates.adb` SHA-256:
  `b87927ab0de307904e0b18b4bc58813b5916a2c0871376d8800235f9b7ffd0d7`
- Benchmark body SHA-256:
  `902b2e2f9158bbb4316ae0b1f5b5535e0e2a924e0474efa61b3440f204c448f8`
- Benchmark dependency: indexed `flyology_bench = 0.1.1-dev`, release
  origin commit `243833e635b2fc4f990d86d32624c4f1b7e9951d`; no Git or path pin

Environment:

- MacBook Pro `Mac15,9`, Apple M3 Max, 16 cores (12 performance and
  4 efficiency), 48 GB, AC power and 100% battery
- macOS 26.5.2 build 25F84, arm64
- GNAT 16.1.0
- GPRbuild 26.0.0
- Alire 2.1.1
- release compilation with `-O3 -gnatn -gnatp`

## Method

Both versions were force-built with `alr build --release -- -f`. The reviewed
`flyology_bench` harness ran three interleaved rounds per version and retained
50 samples per lane per round. The table reports the median of the three
per-round median latencies. The complete local output has 48 lines and 24,063
bytes with SHA-256
`078b0430da9a802feaeb770beab105236bc2768a4421662792d72c99ec6d7d4a`.
It remains at the repo-relative ignored path
`benchmarks/obj/perf_gate_results/10728ab-vs-01ac354-3x50-interleaved-20260824.log`
because this is a dirty-tree performance gate, not a formal baseline artifact.

The baseline copy required one compatibility-only harness edit: its parser
constructor omits the duplicate-storage discriminants that did not exist at
`10728ab`. Both isolated copies received the same temporary lane filter for
string-heavy and large-object documents at monolithic, 16-octet, and
4,096-octet schedules. No fixture or benchmark-loop code was otherwise edited.

Each lane used the harness's fixed 100 ms warmup, 500 ms measurement target,
50 retained samples, at least 100 us per timed sample, no timer-cost
subtraction, process metrics, and the Mach monotonic clock. The host had no
affinity/power lock or interference watcher. The interleaved run was:

```sh
for perf_pair in 1 2 3
do
  echo "PAIR=${perf_pair} BASELINE"
  env FLYOLOGY_JSON_BENCH_OUTPUT=csv \
    benchmarks/obj/perf_gate_baseline/tree/benchmarks/bin/flyology_json-parser_benchmark
  echo "PAIR=${perf_pair} CURRENT"
  env FLYOLOGY_JSON_BENCH_OUTPUT=csv \
    benchmarks/obj/perf_gate_current/tree/benchmarks/bin/flyology_json-parser_benchmark
done | tee \
  benchmarks/obj/perf_gate_results/10728ab-vs-01ac354-3x50-interleaved-20260824.log
```

The compared lanes use identical documents and chunk schedules. The large
object comparison intentionally adds work: the baseline did not detect
duplicates, while the current parser indexes 16,384 unique decoded names and
136,346 name octets.

| Lane | Baseline | Current | Direction |
| --- | ---: | ---: | ---: |
| String-heavy, monolithic | 2.587 ms | 1.487 ms | -42.5% |
| String-heavy, 16-octet chunks | 3.171 ms | 2.491 ms | -21.4% |
| String-heavy, 4,096-octet chunks | 2.583 ms | 1.476 ms | -42.9% |
| Large object, monolithic | 0.847 ms | 1.823 ms | +115.2% |
| Large object, 16-octet chunks | 1.019 ms | 2.126 ms | +108.7% |
| Large object, 4,096-octet chunks | 0.834 ms | 1.779 ms | +113.3% |

The object delta is not a like-for-like parser regression: it is the measured
cost of exact decoded-name retention and crit-bit insertion relative to doing
none of that work. The string lanes demonstrate that enabling the strict engine
does not impose duplicate-index work on ordinary string values.

## Generated-code inspection

The release object contains distinct generated functions for name and string
text scanning. The string scanner has no duplicate-index or name-retention
relocation or call, and its ASCII loop has no name-mode branch. Unescaped names
call `Append_Octets` once per complete validated raw span rather than once per
scalar or octet. `Append_Octets` performs its arena used-count store once after
the copy loop rather than once per copied octet.

## Correctness and review

- The strict parser suite was force-built and executed separately with the
  local GNAT 13.2.2, 14.2.1, 15.3.1, and 16.2.0 toolchains. Each run used
  `gprbuild -f -p -j0 -P tests/flyology_json_parser_tests.gpr` followed by all
  six produced test executables; all passed.
- Monolithic, one-byte, and deterministic randomized corpus campaigns each
  passed 394 fixtures with zero unexpected outcomes.
- Exact name-capacity, malformed/resource precedence, provisional raw and
  decoded prefix invariance, duplicate, reset, abort, and zero-name-storage
  string tests passed. No Unicode normalization is performed or claimed.
- Independent final reviews found P0 0, P1 0, and P2 0.

Disposition: the performance-change gate is closed for this parser milestone.
Formal throughput/latency baselines remain open until an uncontended isolated
run can retain complete statistically valid output.
