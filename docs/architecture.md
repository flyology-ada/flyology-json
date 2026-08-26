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

The strict parser is RFC 8259 JSON over UTF-8 Unicode scalar values. With
`No_Extensions`, it rejects BOMs, malformed UTF-8, unpaired surrogate escapes,
raw controls, comments, trailing commas, nonstandard/nonfinite numbers, and
(when selected) decoded-name duplicates. The explicit `Comments`,
`Trailing_Commas`, and `Comments_And_Trailing_Commas` compatibility families
select only their named extensions. Comments use non-nested `//` and `/* */`
syntax where JSON whitespace is legal. The parser validates comment text as
UTF-8 and skips it without emitting events. A trailing comma is accepted only
after at least one array item or object member. Top-level scalars and
object-only roots are distinct explicit policies. Object-only parsing rejects
a recognized non-object root leader before consuming it or validating the
remainder of that token; a byte that cannot lead any JSON value remains a
syntax error.

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

The normative ownership, interruption, lifecycle, destination, and diagnostic
contract is [the fast transactional writer architecture](architecture/fast-transactional-writer.md).
The writer binds a caller destination and explicit depth capacity. Destination `Begin` starts
unpublished staging; `Commit` is the only publication point; `Abort` ends an unpublished
transaction. Failed commit never claims publication.

Hot grammar and fragment calls use an atomic in-call marker rather than whole-call abort
deferral. An abnormal transfer can leave the writer `Interrupted`; the owner must then abort the
document or unwind before any other use. Narrow controlled transfer guards protect begin, commit,
explicit abort, reset, and finalization ownership transitions. A boundary formal that violates its
nonraising generic contract is saved and re-raised after the guard completes; it is never converted
to an ordinary writer result.

Destination writes are bulk and prefix-reporting. Capacity exhaustion accepts
the longest prefix, locating failure at the first unaccepted staged byte while
avoiding octet-at-a-time calls. Other destination errors roll back that call.
The writer batches maximal safe ASCII/UTF-8 spans, retains at most one scalar's
carry across fragments, escapes only as required by ordinary compact policy,
and validates exact number fragments with the parser DFA.

Writer grammar mirrors parser events but uses JSON-level calls only. It knows no Ada field,
optional, variant, alias, schema, OCI model, or Type IR projection. Writer input offsets count
aggregate token octets; staged offsets count candidate output; grammar/depth failures use public
call ordinals. Every ordinary failure aborts an owned transaction once and preserves the primary
diagnostic.

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
endpoints, token staging, and transactional publication. Every corpus fixture
runs monolithically, one byte at a time, and under seeded random schedules.
Every split is retained for bounded transition fixtures; large adversarial
fixtures retain focused boundary schedules rather than a quadratic replay.
Any exhaustive corpus action must compute and require an explicit caller work
ceiling before it starts, and a release record must disclose both a refused
campaign's work requirement and the bounded evidence used in its place.

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

The publication gate required installed public parser/writer/token/numeric units,
consumer spikes using only those units, maintained macOS/Linux GNAT evidence,
APM 0.28 frozen reproduction/audit, source-archive tests, pinned corpus/oracle
evidence, current-commit benchmarks, and a final P0/P1/P2 sweep. The
published `0.1.0-dev` development manifest pins the exact reviewed source
commit and does not use a Git tag. The Flyology Alire index entry resolves that
origin without Git/path pins; compiler-provider locks stay host-local and
non-propagating pins are never committed.
