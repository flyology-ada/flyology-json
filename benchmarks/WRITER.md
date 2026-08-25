# Public writer benchmark

This bounded standalone lane measures the public `Flyology_JSON.Writing`
generic through a caller-owned transactional destination. It compiles only
public source units from `src/`; it does not call the private writer core.
The destination owns a fixed benchmark buffer and performs no per-operation
heap allocation. Fixture construction occurs before measurement.

The maintained fixtures cover root null, Boolean, number, and string scalars;
a 1 MiB direct-UTF-8 string; an escape-heavy string; a number-heavy array; and
a structure-heavy nested array of objects. Fragment-bearing fixtures run both
as one bulk fragment and as one-octet fragments. Each result identity records
logical scalar/name octets, exact output octets, public writer calls, destination
calls, output checksum, maximum depth, and the compiler-reported writer size.
The one-octet lanes expose API-call and destination batching costs; they are
not expected to approach bulk throughput.

The timer includes writer initialization, destination begin, all writer calls,
destination copying/staging, commit, result observation, and controlled writer
finalization. Preflight validates exact ordinary-compact output byte-for-byte
before measurement. The checksum in each result identity is computed during
preflight, not charged to every measured operation. The timed result observes
the committed length, destination-call count, and boundary output octets so the
transaction remains observable.

Build using the existing benchmark Alire environment:

```sh
cd benchmarks
alr exec -- gprbuild -P flyology_json_writer_benchmarks.gpr -p
FLYOLOGY_JSON_BENCH_OUTPUT=terminal \
  writer_bin/portable/flyology_json-writer_benchmark
```

Use `FLYOLOGY_JSON_BENCH_FIXTURE` for one exact fixture identifier and
`FLYOLOGY_JSON_BENCH_FRAGMENT` for `bulk` or `1`. Machine-readable output uses
the same `terminal`, `csv`, `metrics_csv`, and `json` values as the parser lane.
The fixed flyology_bench policy is 100 ms warmup, a 500 ms measurement target,
50 retained samples, and at least 100 us per timed sample. There is no separate
manual repetition loop, so even the one-octet 1 MiB lane performs only the
iterations selected by the bounded measurement policy.

The weekly directional workflow runs the complete eligible writer matrix in
portable and native tracks on macOS and Linux. It validates the exact fixture
and fragment population set, retains raw JSONL and build logs, and includes the
writer sources, GPR project, validator, executable, environment, and artifact
digest manifest in the evidence bundle. GitHub-hosted measurements remain
directional rather than a formal regression scorecard.

The maintained yyjson adapter also exposes a separately labelled `write_dom`
lane. Ada imports `yyjson_write_opts` and ISO C `free` directly; the only C
shim retained by that adapter wraps yyjson's header-inline immutable-document
cleanup. Fixture parsing and reusable DOM construction occur outside timing.
Each timed operation includes yyjson serialization, one complete output
allocation, an FNV-1a observation of every output octet, and `free`.

The weekly job records exactly two yyjson populations that share Flyology
writer fixture bytes: the 1 MiB raw string and nested structures. Exact-output
preflight, capability disclosures, a strict population validator, build logs,
the executable, adapter sources, and the pinned yyjson provenance are retained.
This is a useful preconstructed-DOM serialization bound, never a ranking
against Flyology's event-driven `write_stream` lane. Flyology's full output
checksum is outside timing, while yyjson's is inside timing.

RapidJSON is template-based C++, and Rust serializers have Rust ABIs, so their
future coarse fixed-signature boundaries require benchmark-only shims. Those
shims must consume the same logical fixture, verify the selected output policy,
and disclose allocation and setup work before results are compared.
