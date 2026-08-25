# Architecture

## Scope and direction

Flyology_JSON owns JSON octets, grammar, UTF-8 and escape validation, exact
number lexemes, duplicate-name policy, parser events, and ordinary JSON output.
It does not own Serde traversal, Type IR schema/validation/projection/fingerprint
authority, Flyology wire encoding, or consumer candidate transactions.

```text
input octets -> bounded JSON parser -> provisional JSON events -> consumer
application JSON calls -> transactional writer -> staged octets -> commit
```

The core is Ada-first, allocation-free, caller-driven, nonconcurrent, and has
no tasking, operating-system, Serde, Type IR, Wire, DOM, or C dependency. C and
C++/Rust bridges belong only to separately reviewed benchmark adapters unless
direct Ada cannot express a required mechanism.

Parser and token-collector hot paths do not defer asynchronous task abort or
abnormal transfer. An interrupted instance is discarded, not reset or reused;
ordinary atomic/result guarantees apply only to normal return. The transactional
writer makes a different, explicit abort-safety tradeoff below.

## Static package shapes

The ordinary parser and writer are trusted packages: no budget field, hook,
counter, nullable access, or runtime accounting branch exists. Duplicate
handling is a generic formal with no default, so `Reject_Duplicates` and
`Preserve_Unchecked` compile as distinct parser shapes. Preserve mode performs
no decoded-name retention or duplicate-index work.

Optional accounting is a separate future package family built over the same
semantic engine. It must statically erase from trusted instantiations and bind
one caller ledger for a complete operation. Its versioned cost model requires a
separate review before publication.

Every physical capacity is an explicit caller parameter. There are no public
depth, storage, token, staging, buffer, chunk, budget, or retry defaults.

## Profiles

Syntax, Unicode, compatibility, duplicate handling, top-level policy, and
output policy remain independently identifiable. Public
names do not contain `_V1`; each versioned family carries an explicit positive
numeric version. The initial implementation accepts version 1 and rejects
unknown/incompatible profiles before byte zero or destination begin.

The initial strict parser is RFC 8259 JSON over UTF-8 Unicode scalar values. It
rejects BOMs, malformed UTF-8, unpaired surrogate escapes, raw controls,
comments, trailing commas, nonstandard/nonfinite numbers, and (when selected)
decoded-name duplicates. Top-level scalars and object-only roots are distinct
explicit policies. Object-only parsing rejects a recognized non-object root
leader before consuming it or validating the remainder of that token; a byte
that cannot lead any JSON value remains a syntax error.

The ordinary compact writer emits UTF-8, no BOM or added whitespace, caller
member order, exact validated number lexemes, direct solidus/non-ASCII, short
standard escapes, and uppercase hex for remaining control escapes. It is not
canonical. Any future canonical profile requires an independent review; Type IR
retains projection, ordering, framing, and fingerprint authority.

## Parser transport

The parser accepts arbitrary-bound `Ada.Streams.Stream_Element_Array` chunks.
Every consumed value is a count from `Input'First`, never an Ada index. State
retains only bounded lexical carry, structural frames, diagnostics, and (in
strict mode) the caller-backed decoded-name crit-bit index.

`Step` returns one compact event, `Need_Input`, completion, or terminal status.
`Drain` fills a caller event array using the same static engine until output is
full, input is needed, the document completes, or parsing fails. A null output
array is a nonmutating capacity stop. No callback or virtual dispatch occurs per
byte or event.

An event is a compact private value with accessor semantics but no public size,
layout, packing, or ABI. Absolute source ranges and inline decoded scalars
survive event copies. A raw range is only a count-based borrow from the exact
unchanged input actual supplied to the returning call; no access value is
retained. Range resolution validates coordinate containment, not Ada object or
content identity; using the producing result with that exact unchanged actual
is a caller obligation. Consumers copy before releasing or reusing it.

The event grammar contains document/object/array boundaries, member-name and
string begin/fragment/end, number begin/exact-fragment/end, null, and Boolean.
Container lengths are unknown. Events are provisional until complete-document
acceptance; JSON never retroactively withdraws observations or commits a Serde
candidate.

Decoded text fragments end at Unicode scalar boundaries. Escapes and surrogate
pairs yield validated decoded UTF-8 while retaining exact source provenance.
Numbers are never normalized or converted by parsing and may span unlimited
fragments. A bounded collector copies selected decoded/exact fragments into
explicit caller storage and publishes a length only at token completion.

## Duplicate names

Strict duplicate equality is exact decoded UTF-8 scalar-sequence equality with
no normalization. Each object owns a LIFO mark into caller-backed name octets,
leaves, and crit-bit nodes. Lookup/insertion is bounded and has no quadratic or
hash-collision fallback. Detection occurs when the later name is complete,
before its `Name_End`; the primary coordinate is its opening quote.

Preserve mode emits every member in source order and performs no duplicate
classification. It does not select first/last values. Serde alias collisions
between distinct names remain outside JSON.

## Parser lifecycle and failures

Successful initialization freezes a complete profile in `Ready`. Parsing enters
`Active`; `Document_Complete` enters `Completed`; malformed/resource failure
retains a primary nonraising diagnostic; abort/reset are explicit and cleanup
does not replenish any caller-owned external limit. Reset is accepted only from
terminal states and revalidates the complete next-operation profile.

Source offsets are zero-based absolute octets. UTF-8 blames the octet proving
invalidity, except completed overlong/surrogate/out-of-range sequences blame the
stored lead. Unknown escapes and nonhex `\u` digits blame the offending octet.
A valid but non-low continuation blames the preceding high escape; a malformed
following escape blames its own offending octet; a lone low surrogate blames
its own reverse solidus. Truncation blames the first missing position;
depth blames the opener; name storage blames that name's opening quote.

## Writer transaction

The writer binds a caller destination and explicit depth capacity. Destination
`Begin` starts unpublished staging; `Commit` is the only publication point;
`Abort` always ends the unpublished transaction. Failed commit never claims
publication. Explicit abort and limited-controlled finalization ensure one
cleanup attempt; cleanup failure is secondary to an existing JSON failure.

Every admitted mutating writer call is one abort-deferred operation covering
its finite validation and scan, destination calls, and adjacent writer and
ownership transitions. If abnormal transfer is pending, an abort-deferred
cleanup finalizer ends an owned unpublished transaction exactly once and seals
the writer terminal before unwinding. This deliberately favors transaction
integrity over cancellation latency: the hot per-octet loop has no task-abort
check or dispatch, but cancellation waits for the finite call and its
caller-supplied destination work to return. Every destination formal is
synchronous, nonraising, and must return; a destination that blocks
indefinitely can therefore delay task abort indefinitely. The writer invents
no timeout, helper task, preemption, or scheduling policy.

Destination writes are bulk and prefix-reporting. Capacity exhaustion accepts
the longest prefix, locating failure at the first unaccepted staged byte while
avoiding octet-at-a-time calls. Other destination errors roll back that call.
The writer batches maximal safe ASCII/UTF-8 spans, retains at most one scalar's
carry across fragments, escapes only as required by ordinary compact policy,
and validates exact number fragments with the parser DFA.

Writer grammar mirrors parser events but uses JSON-level calls only. It knows no
Ada field, optional, variant, alias, schema, or Type IR projection. Writer input
offsets count aggregate token octets; staged offsets count candidate output;
grammar/depth failures use public call ordinals. Every failure aborts an owned
transaction once and preserves the primary diagnostic.

## Numbers

Checked signed, unsigned, and binary64 conversions are separate from parsing.
Decimal and application conversions are future packages, not part of the
initial installed surface or its release evidence. Integer conversion validates
strict integer syntax and checks range before arithmetic overflow. Integer
rendering is exact and transactional in caller output.

Binary64 uses an always-valid `Interfaces.Unsigned_64` IEEE 754 interchange
encoding with numeric bit zero least significant, sign bit 63, biased exponent
bits 62 through 52, and fraction bits 51 through 0. The mapping is independent
of host byte order. Conversion is nearest-even with explicit
exact/rounded/underflow/overflow outcomes, negative-zero preservation, and
shortest round-trip deterministic rendering. NaN and infinity encodings are
rejected without first materializing an invalid floating object. The
implementation and claims require independent oracle, endpoint, compiler, and
OS evidence.

## Verification

Focused tests cover every parser/writer transition, malformed/truncated input,
all Unicode scalars and escape/surrogate combinations, arbitrary array bounds,
exact resource boundaries, reset/abort/reuse, destination failures, numeric
endpoints, token staging, and transactional publication. Every fixture runs
monolithically, one byte at a time, at every retained split, and under seeded
random schedules; deliberately quadratic full-corpus campaigns require an
explicit caller work ceiling and are not routine CI loops.

Pinned corpora retain exact revisions, licenses, byte manifests, and
profile-specific expectations. Corpus labels and differential agreement are
evidence, never specification. Differential runners compare several mature
independent parsers/writers and record expected profile disagreements. Fuzzing,
mutation, sanitizers, validity checks, and selected proof retain minimized
regressions.

Benchmarks use flyology_bench, reproducible workloads/chunk schedules, raw
samples, throughput/latency/allocation/memory/work counters, and honest lanes
for streaming, DOM, SAX, validation, or materialization. Performance changes
require before/after evidence, profiling/assembly inspection, the full relevant
correctness suite, and P0/P1/P2 review. Trusted accounting erasure and compact
event transport are assembly-reviewed release properties.

## Release boundary

Publication requires installed public parser/writer/token/numeric units,
consumer spikes using only those units, maintained macOS/Linux GNAT evidence,
APM 0.28 frozen reproduction/audit, source-archive tests, pinned corpus/oracle
evidence, current-commit benchmarks, and a final P0/P1/P2 sweep. The immutable
annotated tag is `flyology_json/v0.1.0-dev`. The Flyology Alire index entry must
resolve the reviewed origin without Git/path pins; compiler-provider locks stay
host-local and non-propagating pins are never committed.
