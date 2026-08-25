# Public streaming writer implementation review

Date: 2026-08-25

Status: reviewed implementation milestone; consumer exact-commit review and CI
remain post-push gates, not release evidence

Base architecture commit: `056bf69e82b9910b735694e9adc6b92c01a17bb2`

## Scope

This milestone implements the public trusted `Flyology_JSON.Writing` generic,
keeps the bounded allocation-free writer engine private, adds public-surface
tests and assembly checks, adds project-owned writer corpus/oracle schedules,
and adds standalone and yyjson writer benchmark lanes. It does not add an
accounting surface, canonical JSON, a DOM, Serde/Type IR/Wire/OCI integration,
or a production C dependency.

The yyjson code is benchmark-only. It uses direct Ada imports for the stable
`yyjson_write_opts` and ISO C `free` symbols. The one retained C helper wraps
yyjson's header-inline immutable-document cleanup; no JSON policy lives in C.

## Review rubric and result

P0 is unsafe or irreversible publication. P1 is correctness, ownership,
boundedness, interoperability, or measurement-integrity failure. P2 is an
important pre-milestone evidence, portability, documentation, or hygiene gap.

The first independent implementation review found no P0 and one P1: 128
two-octet escapes could exactly fill the private 256-octet scratch before a raw
run, creating zero available space and no progress. The engine now flushes
immediately when an appended escape exactly fills the scratch. Core and public
tests cover exact 255/256/257 output, quotes, reverse soliduses, short control
escapes, names, string values, negative and positive arbitrary bounds, complete
expected bytes, destination exhaustion at staged byte 257, no publication,
`Failed`, retained primary diagnostic, and exactly-once abort.

The mandatory fix re-review reports P0 none and P1 none. Its two local P2s were
also fixed: yyjson's unsupported lane now says specifically that no *streaming*
writer boundary exists, and exact-fill tests compare all output bytes and
terminal failure behavior.

RapidJSON and Rust writer comparators remain a disclosed P2 for the next focused
benchmark milestone. The user explicitly authorized pushed incremental
milestones while continuing comparative performance work; this milestone does
not claim that the original comparative-writer or release plan is complete.

## Correctness and corpus evidence

`./scripts/test-all.sh` passed with GNAT 16.2.0-patchset.1.1.0. It covered:

- parser core, UTF-8, number DFA, duplicate index, offsets, and Unicode escapes;
- public parser/foundation and separate external consumer-project compilation;
- public and private writer behavior, lifecycle, transaction cleanup, task
  abort, contract-violating destination exceptions, arbitrary array bounds,
  exact resource boundaries, and output exhaustion;
- public-surface parser and writer assembly gates;
- four project-owned writer event tapes through whole-token, one-octet, every
  single split including empty ends, and four deterministic randomized writer
  schedules;
- exact Ordinary_Compact golden bytes, public parser replay through exhaustive,
  one-byte, and randomized parser chunks, and independent Node `JSON.parse`;
- 394 maintained parser fixtures in monolithic, one-byte, and randomized
  schedules with zero unexpected outcomes: JSONTestSuite 314, JSON Schema Test
  Suite 80, and three WPT provenance-evidence fixtures; and
- the adversarial parser work guard.

Corpora remain pinned and attested by their existing lock/provenance files.
Corpus labels and independent-oracle agreement remain evidence, not the JSON
specification.

## Benchmark and native-boundary evidence

The public writer benchmark uses only public source units. It validates exact
output outside timing and includes profile setup, transaction begin, semantic
calls, destination staging/copying, commit, result observation, and controlled
finalization in timing. Current rebuilt portable directional results include
1,491.3 MiB/s for the 1 MiB raw string and 745.9 MiB/s for escape-heavy output,
with zero RSS change per operation.

The yyjson 0.12.0 source remains pinned to commit
`8b4a38dc994a110abaec8a400615567bd996105f`, archive SHA-256
`94e9c90f8f12d8329f2c0756782d21e5c278729023cd2c5fe47e323a35947ed6`,
MIT. C/Ada write-error sizes and field offsets, direct symbols, exact output,
repeated write, malformed preparation, idempotent release, and arbitrary Ada
bounds passed. Portable `write_dom` medians were 817.245 MiB/s for the 1 MiB raw
string and 617.088 MiB/s for nested structures. Allocation, serialization,
full-output FNV-1a, and free are timed; reusable DOM preparation is not. These
are deliberately not ranked against Flyology's `write_stream` lane.

The weekly macOS/Linux portable/native job now records and validates the full
public writer matrix and the exact two-population yyjson writer JSONL, retaining
sources, capabilities, binaries, build logs, environment, and digests. The
public validator's five focused matrix/mutation tests pass locally. The yyjson
validator awaits execution under the required Node 24.19.0 in CI because the
host Node 25.2.1 is deliberately rejected.

## Consumer boundary

No OCI-specific P0/P1 incompatibility was found: strict RFC/Unicode profiles,
exact number lexemes and checked integer conversion, explicit duplicate policy,
caller-selected physical bounds, arbitrary chunking, unknown-member exposure,
exact offsets, provisional parser events, and deterministic noncanonical
transactional output fit the stated OCI consumer requirements. Unknown-field
retention or skipping remains the typed consumer's policy.

Wire, Serde, Type IR, and OCI must review the exact pushed commit before this
surface freezes. No integration, dependency pin, canonical-authority claim, or
release readiness follows from this implementation milestone. Installed and
no-pin downstream resolution remain later release gates.
