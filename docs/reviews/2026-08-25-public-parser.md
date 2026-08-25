# Public streaming parser milestone review

Date: 2026-08-25

Reviewed implementation commit:
`e1726835db292669fb6db8ce437fec17704f8831`.

This review closes the installed trusted parser milestone. It does not freeze
the writer, publish the Alire release, or claim installed no-pin evidence from
the Flyology index.

## Reviewed identities

| Artifact | SHA-256 |
| --- | --- |
| `src/flyology_json-parsing.ads` | `156f6bd0ff0316ed34a35fca3fad4901db5c80799d5420cd0186b425d21db000` |
| `src/flyology_json-parsing.adb` | `c2fb5253116810835bd38f4f0bf3b13c57d5936392005bc2b4d40c2f4805815c` |
| `src/flyology_json-parser_core.ads` | `95b5941e3098c7994d2f73f4091c6e8bee014e7af3045db430068197d5ce9695` |
| `src/flyology_json-parser_core.adb` | `e583197cdf40a86ad3e85fc55d2f2d0c24430acb8ac53cf7ae7f083af2be2dc5` |
| `tests/flyology_json-public_parsing_tests.adb` | `71f07e1cb07a51862d2fb8b773d19db734591b4ff7ef9245e4449f174e6f1ef9` |
| `tests/flyology_json_external_consumer_smoke.adb` | `78381b94d9f5b2fa7c8751a9e0044aec4322ef7207b5207b7d139f0df2ce44de` |
| `scripts/check-public-parser-assembly.sh` | `44680b7af1bd27c00bb8bf7573b4defb74938dd7467c6032e564e51f375c2988` |
| `benchmarks/src/flyology_json-parser_benchmark.adb` | `5037a8e2edb854cc7ccdb5182df5017a7e1158d2664259f25ad91ffffb8d7422` |
| `tools/corpus/flyology_json-corpus_runner.adb` | `3133655f00514b86fcb432581d505018a4904933ebb376938fab3f8789bb6db6` |

## Result

The installed `Flyology_JSON.Parsing` generic exposes definite `Step` and
batched `Drain` results, compact private events, arbitrary-bound stream-element
input and event arrays, exact number fragments, explicit root policy, exact
coordinates, caller-selected resource capacities, and static
`Reject_Duplicates` or `Preserve_Unchecked` behavior. The preserve instance
does not carry the strict duplicate arena or index.

The raw-range resolver validates coordinate containment honestly; it does not
claim to authenticate an Ada array identity or unchanged contents. Borrowed
ranges remain producing-call scoped. Parser events remain provisional until
`Document_Complete`.

The installed contract closes every parser state transition, final-input
latching, rejected-call effect, depth unit, name-storage boundary, duplicate
index boundary, duplicate detection timing, and retained-primary rule.

## Verification

The executable candidate passed `scripts/test-parser.sh` with GNAT 16.1.0 and
GPRbuild 26.0.0 on arm64 macOS 26.5.2 build 25F84. The maintained run included:

- parser-core, public parser, external public-consumer, number, UTF-8,
  duplicate-index, Unicode-escape, public-foundation, and writer-core tests;
- the public strict/preserve assembly gate;
- 394 pinned corpus fixtures (JSONTestSuite 314 and JSON Schema Test Suite 80)
  with zero unexpected results under monolithic, one-byte, and deterministic
  randomized schedules;
- pinned licensing and provenance evidence for three nonvendored, unexecuted
  WPT JavaScript files; and
- the bounded corpus work guard.

The external smoke exercises public parser events through the bounded token
collector into checked unsigned 32-bit, unsigned 64-bit, and signed 64-bit
conversions with arbitrary lower bounds. It is a local project consumer, not
the fresh indexed/no-pin release check.

The APM 0.28.0 frozen install, Codex compilation, and CI audit had already
passed on the executable candidate. The final repair after that run changed
only installed contract comments and the draft-status README. A clean-source
APM compilation reproduced the committed generated `AGENTS.md`; ignored local
benchmark caches are not instruction authority.

### Post-review clean-source runner repair

The first remote run of this milestone found a later P1 in the maintained test
runner, not in the parser implementation. A clean archive reached the external
consumer GPR before Alire had materialized the ignored, host-local
`config/flyology_json_config.gpr`; a dirty checkout concealed the dependency.

Repair commit `011a4438f6fc8cea8c20d1631734e04b23778d38` runs the canonical
`alr build` before compiling that external consumer and keeps generated
configuration and compiler-provider locks uncommitted. The repaired
`scripts/test-parser.sh` SHA-256 is
`8dad6a97a1fbb2f7037f6171734df592c514e979643b1f5320bc892c7d2f56f5`.
The same commit makes CI's retained-log diagnostic safe when an early Alire
failure creates no log; `.github/workflows/ci.yml` SHA-256 is
`e5cf214f34901ce54a4efbb316f812c4814fafb87135c6a6ea7da4d782c56264`.

A clean Git archive reproduced the missing-project failure before the repair.
The same archive with only the runner repair passed `alr test` under GNAT
16.1.0. This closes the clean-source local parser test gate.

GitHub Actions run
[`32829916060`](https://github.com/flyology-ada/flyology-json/actions/runs/32829916060)
then passed from evidence head `aecfee74762b183a5fa3619c3a675c8c51048500`.
All eight parser jobs passed with GNAT 13.2.2, 14.2.1, 15.3.1, and 16.1.0 on
macOS 15 and Ubuntu 24.04. All four portable/native benchmark-adapter jobs also
passed on those two operating systems.

## Performance evidence

On an Apple M3 Max quiet-window GNAT 16 release run, the 295 KiB
`large_array` public `Drain` lane measured a 296,784 ns median with 0.761%
sample CV: 0.994 decimal GB/s, or 947.7 MiB/s. The benchmark uses a
caller-owned 256-event (6,144-byte) buffer and records that capacity in its
result identity. The earlier public candidate measured 322,544.9 ns, so the
compact derived-event path reduced median latency by about 8.0% in those local
runs.

The maintained standalone public-parser benchmark contains 45 populations. The
cross-implementation comparison matrix contains 63 populations across
Flyology_JSON and prepared RapidJSON SAX/DOM, yyjson validation, simdjson DOM,
serde_json DOM, sonic-rs, and simd-json lanes. Their output contracts differ,
so comparative throughput is optimization evidence rather than semantic
equivalence. Installed-library assembly and fresh indexed benchmark evidence
remain release gates.

## Consumer boundary review

Independent Wire, Serde, and Type IR API reviews drove definite result types,
the coordinate-only range contract, literal split behavior, total lifecycle,
exact capacity units, no-copy stream-element token flow, strict/preserve
duplicate modes, exact numeric lexemes, and the public batched path. No
integration or dependency was added.

The OCI Runtime Spec consumer requirements introduce no parser-specific P0 or
P1 incompatibility. The strict reject instance provides RFC JSON and strict
UTF-8 behavior, duplicate rejection, arbitrary chunking, bounded depth/name
resources, exact offsets and lexemes, and checked uint32/uint64/int64
conversion without a Flyology runtime dependency. Unknown OCI fields and
annotations are exposed deterministically as JSON events; selecting or
retaining them remains consumer-owned. Deterministic ordinary serialization is
a writer milestone and remains explicitly noncanonical.

## Findings and remaining gates

Severity rubric: P0 is an unsafe or irreversible blocker; P1 is a correctness,
boundedness, lifetime, or public-contract blocker; P2 is an important
pre-freeze quality or evidence defect.

The final independent implementation and contract sweep found P0 0, P1 0, and
no actionable parser-milestone P2. All original parser findings were fixed and
narrowly re-reviewed. The later clean-source runner P1 and failure-logging P2
described above were also fixed and independently reviewed. One
corpus-evidence P2 remains explicitly authorized for deferral: the full bounded
exhaustive every-split campaign is too expensive for routine execution and
remains a release evidence gate.

The following are disclosed future gates, not closed by this milestone:

- fresh installed and no-pin downstream resolution plus installed-library
  assembly evidence after an indexed release exists;
- that intentionally infrequent exhaustive corpus campaign, with a finite
  maintained bound, as recorded in the provisional corpus review;
- public writer implementation, writer comparison lanes, final repository
  review, immutable release tag, and Flyology Alire index publication.
