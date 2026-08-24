# Parser baselines

This isolated Alire subcrate measures the private, allocation-free Ada parser
core. It is not a production dependency and does not add a native boundary to
`flyology_json`. The only benchmark dependency is the indexed
`flyology_bench = 0.1.1-dev` release; there is no Git or path pin. The isolated
GPR project compiles the repository's `src/` units directly with its release
switches so it cannot accidentally reuse the root workspace's development
profile. The GPR consumes Alire's generated benchmark configuration directly;
`alr build --release` therefore supplies `-O3`, inlining, and suppressed runtime
checks to both the driver and the parser units.

## Workload

One logical operation initializes a parser, validates one complete document,
and drains all provisional events through `Next`. Fixture construction and
preflight validation happen before measurement. The result-producing batch
interface keeps the event checksum observable after the ending timestamp.

The maintained synthetic fixtures exercise:

- a small mixed object;
- a large array of mixed nested objects;
- a string-heavy object containing direct ASCII, direct UTF-8, and escapes;
- a number-heavy array preserving long exact lexemes;
- 256 levels of nesting;
- a large scalar array; and
- a large object with unique member names.

Every fixture is measured monolithically and in 1, 16, 256, and 4096-octet
chunks. Duplicate-name storage is derived from each fixture's maximum live
object-name set rather than from a benchmark-wide default. A benchmark identity
includes the exact input size, emitted-event count, `Next` call count, decoded
name-octet capacity, name capacity, maximum depth, and compiler-reported parser
state bytes. These values distinguish parser work and caller storage from
transport scheduling without charging a counter hook inside the core.

This is a strict validation/event-draining lane, not a DOM construction,
decoded-text materialization, numeric-conversion, or I/O benchmark. It includes
decoded-name duplicate rejection but every maintained object name is unique.

## Reproduce

Use a release build and run from this directory:

```sh
alr build --release
FLYOLOGY_JSON_BENCH_OUTPUT=json bin/flyology_json-parser_benchmark
```

`FLYOLOGY_JSON_BENCH_OUTPUT` accepts `terminal`, `csv`, `metrics_csv`, or
`json`; the default is `terminal`. JSON output is newline-delimited and retains
raw samples and the host/toolchain metadata reported by `flyology_bench`.
`csv` reports latency summaries; `metrics_csv` reports the selected resource
axes. All three machine-readable modes omit interactive progress.

The initial harness validation resolved the indexed `flyology_bench 0.1.1-dev`
release to subdirectory `flyology_bench` of `flyology-ada/flyology` at commit
`243833e635b2fc4f990d86d32624c4f1b7e9951d`. This is an attested release origin,
not a Git pin; Alire's generated resolution and compiler-provider selection
remain under ignored `alire/` state.

The fixed measurement policy is 100 ms untimed warmup, a 500 ms measurement
target, no early sampling-time cap, 50 retained samples, at least 100 us per
timed sample, timer-cost subtraction disabled, and process resource metrics
enabled. The benchmark records process RSS and RSS change; it does not claim
that those process-wide values are parser-owned. The parser core contains no
allocation, while fixture generation and the benchmark framework allocate
outside timed parsing. Heap allocations per core operation are contractually
zero rather than inferred from process RSS; this lane does not install an
allocator hook. Future allocating comparison implementations must report their
allocations through separate instrumentation.

For a result with `bytes=B` and median latency `N` nanoseconds, derive binary
throughput as:

```text
MiB/s = B * 1_000_000_000 / N / 1_048_576
```

For comparable baselines, record the exact flyology-json commit, operating
system version, machine and CPU, power mode, compiler and binder versions,
`flyology_bench` release, command line, environment, and the complete JSONL
output. Retain an official baseline only from a clean checkout; a run over
uncommitted parser changes is a harness smoke test. Do not compare runs
collected under different chunk schedules or fixture byte counts as though they
measured the same operation.

## External comparisons

The maintained cross-implementation contract is under
[`comparison/`](comparison/README.md). It fixes independent parser and writer
lanes, portable and native build tracks, capability and result disclosures,
and exact benchmark-only source attestations. External libraries never become
dependencies of the production `flyology_json` crate.

Acquire and verify the approved source archives outside the checkout with:

```sh
scripts/verify-benchmark-sources.sh
```

The verifier checks byte length, SHA-256, and the exact license files recorded
in the lock manifests. It downloads archives but does not extract or vendor
them. In particular, RapidJSON's restrictively licensed `bin/jsonchecker/`
content must never enter a build tree or this repository.
