# Architecture

## Scope and dependency direction

Flyology JSON is a standalone Ada JSON crate. Its core has no dependency on
Flyology tasking, Serde, Type IR, Wire, an operating system, or C.

```text
input octets -> JSON parser -> provisional JSON events -> consumer candidate
application events -> JSON writer -> staged octets -> destination commit
```

The parser and writer own JSON syntax only. They do not know Serde optionals,
variants, records, aliases, schemas, Type IR facts, fingerprints, or wire
encoding.

Parser and writer instances are single-owner and nonconcurrent. Calls on an
instance and its caller-owned budget/destination are serialized. The core has
no Ada tasking dependency and does not promise abort deferral: callers must
defer asynchronous task abort, asynchronous transfer of control, and
cancellation while a mutating JSON call, generic formal, or finalization
cleanup executes. Normal scope exit and synchronous exception unwinding outside
a mutating call remain covered by writer finalization.

## Transaction boundaries

Parser events observed before complete-document acceptance are provisional.
The parser cannot retract an event from an arbitrary consumer. A consumer that
constructs a value must therefore keep an unpublished candidate and commit it
only after the parser reports complete-document acceptance.

JSON owns parser, lexical, structural, duplicate-index, counter, and diagnostic
state. On failure, the parser enters a terminal failed state and retains the
primary status and offset. Parser `Abort_Document` is nonraising and idempotent
in every state. Its first effective call cleans internal JSON state and enters
`Aborted`; later calls are no-ops. Returned events contain no parser-owned view,
so abort cannot invalidate a copied event or a caller-retained input chunk.
Aborting a completed parser revokes completion. Aborting a failed parser
preserves its primary diagnostic.

The parser never calls a consumer's abort operation. An orchestration layer that
owns both transactions calls parser `Abort_Document` once and consumer abort once on
failure, with guards against repeated cleanup during exception unwinding. A
consumer cleanup failure cannot replace the JSON primary diagnostic and remains
secondary. When no primary failure exists, the cleanup failure becomes the
operation failure. `Reset` is the only reuse route from `Completed`, `Failed`,
or `Aborted`. It begins new JSON state but does not replenish or reset a
caller-owned budget.

Writer destinations implement a whole-document transaction:

```text
Begin -> Stage bulk octets -> Commit
                      \-> Abort
```

Destination bytes remain unpublished until `Commit` succeeds. A successful
destination `Begin` transfers sole transaction ownership to the writer. A
failed `Begin` must leave no transaction to abort. While it owns the transaction,
the writer is the only component that calls destination `Write`, `Commit`, or
`Abort`.

Writer `Initialize` and successful `Reset` validate and freeze a profile, enter
`Ready`, and do not begin a destination transaction. `Begin_Document` advances
its observational call counter, validates its call state, and then calls
destination `Begin`; it has no deniable budget charge. A failed destination
`Begin` must leave no transaction to abort and puts the writer in `Failed`;
success puts it in `Active` with sole transaction ownership.

Writer `Abort_Document` is nonraising and idempotent. Its first call in `Ready`
enters `Aborted` without calling the destination. Its first call in `Active`
invokes destination `Abort` exactly once and enters `Aborted`. A writer
validation, budget, staging, or destination-write failure while `Active` first
latches that primary diagnostic, invokes destination `Abort` exactly once, and
enters `Failed`. A failed destination `Commit` is likewise primary and is
followed by one destination `Abort`. Destination `Abort` must preserve
nonpublication even when it reports a cleanup failure; that failure is retained
as the secondary diagnostic. An explicit active-writer abort with no earlier
failure promotes an abort cleanup failure to primary.

Writer `Abort_Document` after `Completed` is a no-op and cannot revoke committed output.
`Reset` is legal only from `Completed`, `Failed`, or `Aborted`; it never aborts
an active transaction implicitly and never resets a caller budget. Reset starts
a fresh writer operation in `Ready` only after the new profile validates; a
later `Begin_Document` starts its destination transaction. A bounded buffer
retains its published length as zero until commit. Direct irreversible sockets
and files do not meet this contract without external staging and are not
exposed as transactional destinations.

The writer is limited controlled. If normal caller exception unwinding or
abandonment outside a mutating call finalizes it while it still owns an active
transaction, a nonraising safety net invokes destination `Abort` exactly once.
Explicit `Abort_Document` remains the observable cleanup path; finalization
cannot return a cleanup diagnostic. The destination generic contract therefore
requires abort to end the unpublished transaction even when it reports an
error, and the writer target must outlive writer finalization.

## Parser state machine

The parser is caller-driven. One `Step` accepts an arbitrary-bound
`Ada.Streams.Stream_Element_Array`, an explicit final-input flag, and a frozen
operation configuration. It returns a consumed count and exactly one outcome:

- one JSON event;
- `Need_Input`;
- complete-document acceptance;
- a terminal malformed-input or resource status, or a nonterminal rejected-call
  status for protocol misuse.

The parser never retains a reference to the chunk after `Step` returns. A raw
fragment event contains a count-based range into the chunk passed to that call
and an absolute range. The caller can inspect or copy that slice before it
reuses the chunk. The event contains no access value. Decoded bytes that are not
a source slice occupy the event's fixed four-octet scalar field; four is derived
from the maximum UTF-8 encoding length and is not a configurable capacity.
After the source-free `Document_Begin` event, a zero-length nonfinal chunk
returns `Need_Input` without lexical or structural state change. Final input
converts every incomplete token, escape, UTF-8 sequence, surrogate pair,
literal, number, or container into a truncation status.

The closed event grammar is:

```text
Document_Begin
Value := Null | Boolean
       | Number_Begin Number_Fragment* Number_End
       | String_Begin Text_Fragment* String_End
       | Array_Begin Value* Array_End
       | Object_Begin (Name_Begin Text_Fragment* Name_End Value)* Object_End
Document_End
```

JSON container lengths are unknown without buffering. No event implies a known
length. Null, arrays, objects, strings, names, and numbers remain JSON concepts;
they do not imply Serde logical kinds.

Number fragments identify exact input ASCII octets in the current chunk. For
names and strings, a fragment event identifies the exact raw source range and
one of three decoded forms: no decoded output, that same raw range as decoded
UTF-8, or one decoded scalar in its inline field. Raw-only fragments report
incomplete pieces of a split escape or split UTF-8 sequence. The completing
fragment carries the decoded scalar inline. Decoded source ranges end at Unicode
scalar boundaries. A high surrogate remains lexical state until an immediately
following low-surrogate escape completes one scalar. No Unicode normalization
occurs. JSON performs no hidden reread of an earlier input chunk.

Raw chunk ranges are usable only with the exact chunk passed to the `Step` that
returned them. Absolute source ranges are coordinates and remain meaningful
without the chunk. Inline scalar bytes are ordinary value data and remain valid
in every copied event. A bounded collector above the fragment API copies a
complete token into caller storage and changes its caller output only after the
token validates and fits.

## Input offsets

Offsets are zero-based unsigned 64-bit octet positions from the first supplied
input octet, independent of every Ada array lower bound.

- Malformed input reports the first offending octet.
- An incomplete construct at final input reports the total input length.
- An invalid UTF-8 continuation reports the offending continuation octet.
- An overlong, surrogate, or out-of-range UTF-8 encoding reports its lead octet.
- An invalid hexadecimal escape reports its first non-hexadecimal octet.
- An isolated low surrogate reports the escape's reverse-solidus octet.
- A high surrogate followed by a closing quote, a raw Unicode scalar, or a
  complete valid escape other than a low-surrogate escape reports the high
  surrogate escape's reverse solidus.
- A malformed would-be following escape reports its first malformed octet.
- An unfinished high surrogate or following escape at final input reports the
  total input length as truncation.
- A duplicate name reports the opening quote of the later name.
- Parser input-budget denial reports the next unconsumed octet. A semantic,
  storage, index-work, event, value, item, scalar, or depth denial reports the
  first source octet of the denied construct. A denial before a source-free
  document event reports that event's zero-based ordinal.
- Missing input needed after offset `N - 1` reports `N`.
- Offset counter exhaustion reports a distinct resource status before wrap.

The consumed count is a count relative to the supplied array, never an array
index. Failure publishes no event from the failing step.

Writer diagnostics carry a coordinate kind. Invalid text or number fragments
use the zero-based aggregate input-octet position within the active writer
token. Destination exhaustion uses the zero-based staged-output octet that
could not be accepted. Grammar and state errors use the zero-based JSON call
ordinal. A coordinate is absent only when no input, output, or call was
examined.

Within writer text, an illegal lead or unexpected continuation reports that
octet, a bad required continuation reports the bad replacement octet, and an
overlong, surrogate, or out-of-range encoding reports its lead. Ending text
with incomplete UTF-8 reports the aggregate token length. Within a number, the
first octet that invalidates the DFA is offending; ending in a nonaccepting DFA
state reports the aggregate token length. These rules are invariant under
fragment splitting and arbitrary Ada array bounds.

## Profiles and configuration

Syntax, Unicode compatibility, extension acceptance, duplicate handling,
top-level restrictions, and writer output policy have independent identities
and versions. One operation resolves and freezes every selected identity and
flag before consuming input or staging output. Unsupported versions, unknown
flags, and incompatible combinations fail before byte zero. The applied
identity remains queryable for deterministic capability reporting.

No profile, flag, capacity, budget, layout, or allocator has a public default.
Resource capacities describe caller storage and are not compatibility policy.

The approved initial resolved parser profile combines:

- `RFC8259_Syntax_V1`;
- `Unicode_Scalars_V1`;
- top-level scalar acceptance;
- duplicate-name rejection;
- BOM rejection;
- rejection of comments, trailing commas, nonstandard number spellings,
  nonfinite values, and raw control characters.

RFC 8259's string grammar can admit escaped unpaired surrogates even though the
document identifies their interoperability problems. The initial resolved
profile is therefore a Unicode-scalar interoperability policy layered on the
RFC grammar, not a claim that every sequence admitted by the ABNF becomes a
Unicode scalar string.

A consumer can additionally require an object root. Compatibility behavior is
independently versioned rather than hidden behind an omnibus permissive mode.
The initial public profile exposes `No_Extensions_V1` only. Comments, trailing
commas, nonstandard number spellings, nonfinite values, raw controls,
invalid-Unicode replacement, and alternate BOM behavior have been assessed as
separate future policies; none is silently admitted. Any future granular flag
requires separate authority and P0/P1/P2 review. Parser acceptance and writer
emission permissions remain separate.

## Duplicate names

When detection is enabled, a member name is compared after escape decoding as
an exact Unicode scalar sequence represented by canonical UTF-8. No NFC, NFD,
case, locale, or application normalization occurs. Thus `"a"` and `"\u0061"`
are equal, while canonically equivalent composed and decomposed spellings are
distinct.

Each active object owns a root in a bounded caller-backed crit-bit index. Its
virtual key is the decoded-octet length as eight big-endian octets followed by
the decoded UTF-8 octets. Bits are numbered from zero at the most-significant
bit of the first length octet. The length prefix distinguishes embedded NUL and
proper-prefix names without a sentinel byte. An internal node stores one
increasing critical-bit position and two child indices. A leaf stores the name
arena offset and length. Decoded name bytes, leaves, and internal nodes use LIFO
caller arenas whose marks are stored in structural frames. Object close
restores the marks.

Lookup follows strictly increasing critical-bit positions. Insert performs one
leaf comparison to find the first differing bit and one bounded insertion walk.
Both are linear in the decoded name length and independent of the number of
names except for capacity. `Duplicate_Work` charges once for each tree edge and
once for each pair of virtual-key octets inspected, including length-prefix and
candidate octets. Reading a branch bit is covered by its edge charge.
There is no linear all-name scan, hash collision chain, or quadratic fallback.
Exhausted name bytes, leaves, or internal nodes produce a resource status. When
detection is disabled, the parser retains no name history and exposes every
member in source order.

JSON duplicate names are distinct from two different JSON names or aliases that
map to one application field. Serde owns the latter policy.

## Writer

The writer accepts JSON-level calls only. Its call grammar mirrors the parser
grammar and supports fragmented names, strings, and exact number lexemes. It
validates UTF-8 and number syntax incrementally before the document transaction
can commit. Static or generic bulk destination calls avoid per-byte virtual
dispatch.

A call-grammar violation in `Ready` or `Active` terminates the JSON operation;
an active writer aborts its destination once. Lifecycle-state rejection in an
uninitialized or terminal writer is nonmutating and cannot replace a retained
diagnostic. The explicitly documented abort no-op cases remain successful and
idempotent.

The approved ordinary compact policy:

- emits UTF-8 with no BOM or added whitespace;
- preserves caller member order and exact validated numeric lexemes;
- emits valid non-ASCII directly;
- does not escape solidus;
- uses the short JSON escapes for backspace, tab, newline, form feed, and
  carriage return;
- uses the mandatory two-octet escapes for quotation mark and reverse solidus;
- uses uppercase hexadecimal for other required control escapes.

The ordinary writer is not canonical. A future canonical profile requires a
separate review of its standard, number rendering, key ordering, storage,
limits, and final framing. Type IR continues to own its projection, ordering,
fingerprint, and canonical document authority. A JSON canonical writer may
verify caller-supplied ordering but does not decide Type IR order.

## Numbers

The parser validates number grammar but never converts the lexeme. Number
fragments preserve every source octet, including exponent letter, plus sign,
leading exponent zeroes, fraction spelling, and negative zero.

Separate packages provide checked conversions for signed and unsigned integer
types, binary floating-point types, decimal or fixed-point targets, and
application accumulators. Conversion results distinguish invalid target,
overflow, underflow, inexactness, and unsupported nonfinite values. No public
contract depends on locale-sensitive `'Value` or implementation-specific
`'Image` output.

The writer validates caller-supplied exact number fragments against the frozen
output profile before commit. Typed numeric rendering is a separate policy and
operation.

## Resource accounting

Physical capacities are supplied by the caller. Logical budgets are separate
caller-owned state. JSON never replenishes them during reset. Before each
charged effect, JSON calls the caller-supplied budget hook with a dimension and
delta. Rejection denies that effect before it occurs. Earlier independent input
charges and cursor movements remain consumed when a later semantic charge is
denied. A hook must not call the parser or writer recursively.

Parser budget dimensions and charge points are:

- `Input_Octets`: one immediately before consuming an input octet;
- `Syntax_Events`: one before returning each document, container, token-begin,
  token-end, null, or Boolean event; transport fragment events are excluded;
- `Values`: one before accepting each scalar or opening each container value;
- `Container_Items`: one before accepting an array element or object member;
- `Decoded_Scalars`: one before observing a decoded Unicode scalar;
- `Duplicate_Name_Octets`: one before retaining each decoded name octet;
- `Duplicate_Index_Slots`: one per leaf or internal-node slot needed by a unique
  name, charged as one aggregate amount before retaining either slot;
- `Duplicate_Work`: one per index edge traversed and one per virtual-key octet
  pair inspected for exact comparison.

Input-octet charging always occurs first, immediately before each cursor move.
After enough octets have been consumed to recognize a semantic effect, all
charges for that effect occur before observation, retained storage, structural
mutation, or event return. Their total order is:

1. `Container_Items` when the value is an array child or at object-name begin
   when the construct is an object member;
2. `Values` when a scalar completes or a container opens;
3. `Duplicate_Name_Octets` then `Decoded_Scalars` for a decoded name fragment
   before its bytes are retained and exposed;
4. incremental `Duplicate_Work`, followed by one aggregate
   `Duplicate_Index_Slots` charge, before duplicate-index insertion at name end;
5. `Decoded_Scalars` before a decoded string fragment is exposed;
6. no semantic charge for a raw-only or number fragment beyond its already
   charged `Input_Octets`;
7. `Syntax_Events` before every non-fragment grammar event.

Physical capacity and profile checks that can be decided without consuming
input occur before budget charges. A later denial reports the source start of
its denied construct even though the bytes needed to recognize it remain
consumed. No event for the denied effect is returned.

Opening and closing containers changes live depth but does not spend a
cumulative depth budget. The configured maximum live depth is checked before
opening a container. `Maximum_Live_Depth`, `Step_Calls`, and `Need_Input_Count`
are observational counters, not budget dimensions.

Every optional collector owns a separate collector-budget namespace and charges
`Collected_Octets` before copying. A bounded collector copies into caller
storage and fails transactionally on capacity or budget denial. An allocating
collector additionally owns allocation cleanup and maps caught `Storage_Error`
to its allocation-failure status. Neither collector recharges parser input,
scalar, event, value, or item work. A future Serde backend charges logical
values, schema work, and candidate construction independently.

The writer first checks state, call grammar, profile compatibility, and
immediately decidable physical capacity without charging. It then charges:

1. `Container_Items` before accepting an array child or object name;
2. `Values` before accepting a scalar-begin or container-begin call;
3. `Writer_Input_Octets` before inspecting each supplied name, string, or
   number octet;
4. `Staged_Output_Octets` for the complete bulk span before asking the
   destination to stage it;
5. no deniable charge for a public-call or destination-call boundary.

Step, fragment-delivery, writer-call, destination-call, cleanup-call, and
maximum-depth observations are transport counters. They cannot deny a semantic
effect or change an outcome. Each saturates at the counter subtype's derived
last value and sets `Transport_Counter_Overflowed`; it never wraps or creates a
diagnostic.
Destination `Abort` is mandatory cleanup and cannot be denied by a budget hook
or observational counter. The writer does not recharge escaped expansion
separately because every emitted octet is already charged as
`Staged_Output_Octets`. A failure after earlier staging aborts the document
transaction; those earlier charges remain. The collector, destination, and
future Serde adapter do not recharge writer input, JSON values, JSON items, or
staged octets.

Chunk schedules produce identical non-fragment grammar events, concatenated raw
and decoded fragment streams, semantic budget charges, terminal status, and
diagnostics. Fragment segmentation, `Step_Calls`, `Need_Input_Count`, writer
calls, and destination calls may differ and are transport observations rather
than semantic budgets; their values and overflow flag are exempt from chunk
invariance. Tests compare a normalized event tape. Every denial reports stable
coordinates. Caller-owned semantic-total overflow is a budget-hook denial.
Fixed unsigned 64-bit event and call ordinals return an explicit
counter-exhaustion status before wrap. The fast configuration must establish
through benchmarks and generated-code review that observation adds no per-byte
virtual dispatch or hidden allocation.

Before a parser would return a non-fragment grammar event whose event ordinal
is unsigned 64-bit maximum, it fails with `Counter_Exhausted` at that
`JSON_Event_Ordinal`, enters `Failed`, and returns no event or event charge.
Before a writer call admitted in `Ready` or `Active` would use call ordinal
unsigned 64-bit maximum, it fails at that `JSON_Call_Ordinal`; an active writer
aborts its destination once, while a ready writer has no abort obligation.
Calls rejected solely because the writer is uninitialized or terminal do not
advance the semantic call ordinal. The independently derived observational call
counter still saturates as specified above.

## Allocation

The core performs no heap allocation. Explicit allocating convenience packages
may snapshot input, collect output, or build a separate DOM. They catch storage
exhaustion, clean up owned state, and return `Allocation_Failed`. They never
recast malformed input as allocation failure or publish a partial value.

## Verification architecture

Repository-owned generators cover every `\uXXXX`, every combination of two
surrogate code units, all Unicode scalars, number grammar families, numeric
conversion endpoints, depth and exact resource boundaries, truncation,
mutation, and adversarial duplicate names.

Every fixture runs as one chunk, at every possible single cut, one byte at a
time, and with deterministic randomized schedules. Small transition fixtures
also run every possible chunk partition. Schedules include empty chunks and
arrays with negative, zero, one, and nontrivial lower bounds.

Imported corpora have a non-JSON attestation manifest containing the exact
revision, selected tree and file digests, license digest, transformation digest,
and profile-specific expectation digest. Tests run offline and reject missing,
extra, or changed files. Corpus labels and differential-oracle majorities never
define expected behavior.

The initial candidates, pending file-level provenance review, are JSONTestSuite,
WPT Encoding fatal UTF-8 cases, and the JSON Schema Test Suite's valid JSON
documents. Historic JSON.org JSON_checker fixtures are not vendored because
their license is incompatible with the repository's intended dual license;
clean-room RFC-grounded cases cover equivalent grammar boundaries.

Differential runners compare only capabilities each independent implementation
preserves. Fuzzers assert monolithic/chunked equivalence, deterministic status
and offsets, transactional checkpoints, reset/abort/reuse, resource monotonicity,
sentinel preservation, and writer/parser round trips. Every discovered failure
is minimized and retained in a portable regression manifest.

GNATfuzz and libFuzzer are assessed and used where their supported parameter
shapes and toolchains fit. Maintained configurations also exercise GNAT
assertions, overflow and validity checks, sanitizer builds where supported,
allocation failure at every allocating-layer allocation, and SPARK proof for
the lexical DFAs, Unicode ranges, indices, offsets, and charge-before-mutation
invariants where practical.

Benchmarks are established before optimization and record toolchain, host,
profile, message family, chunk schedule, throughput, latency, allocations, peak
retained memory, and work counters. A performance change requires before/after
evidence, the complete correctness suite, profile evidence, hot-loop generated
code inspection, and a fresh P0/P1/P2 review.

Competitive comparisons use standalone or binding-based harnesses for credible
Ada and non-Ada implementations. Reports disclose semantic/profile differences,
toolchain and binding overhead, input ownership, validation mode, and allocation
behavior rather than presenting unlike configurations as equivalent.

## Release boundary

The initial crate version is `0.1.0-dev`. The crate supports freely available
GNAT releases 13 through 16 where verified on macOS and Linux. Alire
compiler-provider locks remain host-local. No non-propagating Alire dependency
pin may be committed anywhere in this repository. The committed APM lock is
independent agent-package provenance and remains versioned.

A release is complete only when the reviewed origin resolves through the
Flyology Alire index without a downstream Git pin. Release records name exact
dependency identities, compiler and operating-system evidence, test and corpus
revisions, benchmark environment and results, and limitations. Compilation
alone is not compatibility evidence.

Before any public event, profile, reset, transaction, offset, or writer
declaration freezes, its concrete Ada specification receives P0/P1/P2 review
from the existing Serde and Type IR tasks. Implementation begins only after
their P0/P1 findings are resolved and every P2 is fixed or explicitly accepted.
