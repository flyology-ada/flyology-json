# Public writer benchmark smoke evidence

Date: 2026-08-25

Classification: directional local worktree smoke test, not a retained baseline

Repository HEAD: `056bf69e82b9910b735694e9adc6b92c01a17bb2`

Host: Apple arm64, macOS 26.5.2 build 25F84

Ada toolchain: GNAT 16.1.0, GPRbuild 26.0.0

Benchmark framework: indexed `flyology_bench = 0.1.1-dev`, resolved origin
`243833e635b2fc4f990d86d32624c4f1b7e9951d`

The worktree contained the not-yet-committed public writer implementation, so
these measurements cannot be promoted to a clean-checkout baseline. The exact
measured production source SHA-256 values were:

```text
cf0ac606b1dc7108e29bbe96402eca5a3cadb326e5a586d2ee2c56afcbb2560a  flyology_json-writing.ads
5e87a85415f9ae1de208506f44cec8a94634b84f19170d7e2449bcb753f4af77  flyology_json-writing.adb
1bc3ff44b220c6853beb4d8212517e942e95a6c6e527b2bbf9c81eb0b26766ef  flyology_json-writer_core.ads
9c7e71cd6a2b9a53ab5dcadb9fcf42254abe49e67cf5092e9243356287faee97  flyology_json-writer_core.adb
```

## Method

The new standalone lane uses the public `Flyology_JSON.Writing` generic and a
fixed caller-owned transactional destination. Every timed operation includes
profile initialization, begin, writer calls, destination copying/staging,
commit, observation, and controlled finalization. Fixture setup and exact
byte-for-byte output validation are outside timing. There is no per-operation
heap allocation in either the bounded writer or fixed destination; process RSS
change was also zero in every reported median.

The configuration retains 50 samples after a 100 ms warmup, targets 500 ms of
measurement, requires at least 100 us per sample, and caps calibrated batch
size at 65,536 operations. Only the selected lanes below were run. The 1 MiB
one-octet lane and complete matrix were deliberately not run.

## Directional results

| Fixture | Fragment | Output | Median | Output throughput | Writer calls | Destination calls |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| root `null` | bulk | 4 B | 1.94 us | 1.96 MiB/s | 4 | 1 |
| large raw string | bulk | 1,048,578 B | 672.40 us | 1,487.2 MiB/s | 6 | 3 |
| escape-heavy string | bulk | 655,364 B | 857.22 us | 729.1 MiB/s | 6 | 2,573 |
| numeric-heavy array | bulk | 143,361 B | 557.15 us | 245.4 MiB/s | 73,733 | 49,153 |
| nested structures | bulk | 155,649 B | 613.50 us | 242.0 MiB/s | 61,445 | 65,537 |
| eight-octet string | one octet | 10 B | 2.46 us | 3.88 MiB/s | 13 | 10 |

The raw-string result measures UTF-8 validation plus one large destination
copy and transactional overhead. Escape throughput includes expansion from
262,144 logical string octets to 655,364 JSON output octets and 2,573 bounded
destination writes. Numeric and structure rates are dominated by many public
semantic calls and small destination writes; they are not comparable to the
bulk-copy lane.

### Escape scratch-size experiment

The escape-heavy lane was rebuilt and measured in the same quiet window with
private stack scratch sizes of 128, 256, and 512 octets. The 128-octet variant
produced 5,143 destination calls and 705.8 MiB/s. The 256-octet variant produced
2,573 calls and 729.1 MiB/s. The 512-octet variant produced 1,288 calls and
728.4 MiB/s. The implementation retains 256: it matched the best observed
throughput while using half the per-call stack storage of 512. This private
implementation value is not a public capacity, default, or compatibility
promise.

### Mandatory P1 fix check

Review found that exactly 128 two-octet short escapes could fill the private
scratch before a following raw octet. The corrected engine flushes immediately
when an escape makes the scratch exactly full, so every later raw-copy step has
positive space. Core and public regressions cover 255, 256, and 257 emitted
octets, quote/reverse-solidus/short-control escapes followed by raw text, name
and string paths, arbitrary array bounds, and exact destination exhaustion.

After rebuilding from the corrected source in a quiet window, large raw string
measured 670.57 us or 1,491.3 MiB/s with 2.28% CV. Escape-heavy string measured
837.88 us or 745.9 MiB/s with 1.11% CV. The latter is 2.3% above the earlier
729.1 MiB/s smoke result; destination-call counts remain 3 and 2,573. No
performance regression is evidenced by this bounded rerun.

Exact commands, run individually in a confirmed quiet window, were:

```sh
cd benchmarks
alr exec -- gprbuild -P flyology_json_writer_benchmarks.gpr -p
env FLYOLOGY_JSON_BENCH_FIXTURE=small_null FLYOLOGY_JSON_BENCH_FRAGMENT=bulk \
  FLYOLOGY_JSON_BENCH_OUTPUT=terminal ./writer_bin/portable/flyology_json-writer_benchmark
env FLYOLOGY_JSON_BENCH_FIXTURE=large_raw_string FLYOLOGY_JSON_BENCH_FRAGMENT=bulk \
  FLYOLOGY_JSON_BENCH_OUTPUT=terminal ./writer_bin/portable/flyology_json-writer_benchmark
env FLYOLOGY_JSON_BENCH_FIXTURE=escape_heavy_string FLYOLOGY_JSON_BENCH_FRAGMENT=bulk \
  FLYOLOGY_JSON_BENCH_OUTPUT=terminal ./writer_bin/portable/flyology_json-writer_benchmark
env FLYOLOGY_JSON_BENCH_FIXTURE=number_heavy_array FLYOLOGY_JSON_BENCH_FRAGMENT=bulk \
  FLYOLOGY_JSON_BENCH_OUTPUT=terminal ./writer_bin/portable/flyology_json-writer_benchmark
env FLYOLOGY_JSON_BENCH_FIXTURE=nested_structures FLYOLOGY_JSON_BENCH_FRAGMENT=bulk \
  FLYOLOGY_JSON_BENCH_OUTPUT=terminal ./writer_bin/portable/flyology_json-writer_benchmark
env FLYOLOGY_JSON_BENCH_FIXTURE=small_string FLYOLOGY_JSON_BENCH_FRAGMENT=1 \
  FLYOLOGY_JSON_BENCH_OUTPUT=terminal ./writer_bin/portable/flyology_json-writer_benchmark
```

## yyjson comparative boundary

The benchmark-only yyjson adapter imports `yyjson_write_opts` and ISO C `free`
directly. Its existing C shim remains only for yyjson's header-inline immutable
document cleanup. C/Ada size and field-offset checks cover the write error
record, and exact-output preflight runs before timing.

| Fixture | Output | Median | Output throughput | CV |
| --- | ---: | ---: | ---: | ---: |
| 1 MiB raw string | 1,048,578 B | 1.22 ms | 817.245 MiB/s | 0.45% |
| 4,096 nested objects | 155,649 B | 240.55 us | 617.088 MiB/s | 1.03% |

Each yyjson operation includes allocation of the complete output,
serialization, FNV-1a over every output octet, and `free`; reusable DOM
preparation is outside timing. These are not same-lane rankings against
Flyology's streaming writer, whose full checksum is outside timing. Weekly
macOS/Linux portable/native jobs retain a separately labelled two-population
yyjson JSONL artifact and validate its exact identities.

## P0/P1/P2 findings sweep

Rubric: P0 is an unsafe or irreversible blocker; P1 is a correctness,
measurement-integrity, boundedness, or interoperability defect; P2 is an
important pre-milestone quality or coverage issue.

- P0: none.
- P1: none. Preflight validates exact output for every fixture; timed operations
  use only the public writer; output capacity is fixed and checked; arbitrary
  input lower bounds are used; fixture creation and checksum validation remain
  outside timing; all manual loops have fixed finite bounds.
- P2: RapidJSON and Rust writer adapters remain future work. yyjson now provides
  a useful but deliberately non-ranking `write_dom` bound.
- P2: the full fixture/fragment matrix and native build were intentionally not
  run in this shared-host smoke pass. The lane is now integrated into the
  scheduled macOS/Linux portable/native runner, but its first clean-commit
  weekly artifact remains required before promoting a retained baseline.
- P2: the host has Node 25.2.1, while the repository deliberately admits only
  Node 24.19.0 for benchmark validation. The yyjson validator's syntax and
  focused fixtures were checked, but its exact-toolchain execution awaits CI.
