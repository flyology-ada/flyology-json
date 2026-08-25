# Draft public contracts

These contracts govern the compile-checked declarations in this directory.
They are review artifacts until moved into `src`; they are not installed API.

## Operation ownership

One parser, writer, or token collector has one logical owner. Mutating calls on
an instance and its bound caller collaborators are serialized. No package owns
an Ada task, retains a parser input array, calls a consumer visitor, or permits
reentrant use from a destination or future accounting hook.

The trusted parser and token collector do not defer asynchronous task abort or
another abnormal transfer across their mutating hot paths. If such a transfer
interrupts `Step`, `Drain`, `Begin_Token`, `Append`, or `Complete_Token`, their
normal-return atomicity and state-transition guarantees do not apply. The
interrupted parser/collector operation must not continue, and its instance must
be discarded rather than reset or reused. Any caller storage that was bound to
an interrupted collector is unpublished and unspecified until the collector is
discarded, after which the caller may reinitialize that storage. This is
distinct from the writer's explicit abort-deferred guarantee below.

The trusted parser and writer contain no budget object, accounting hook,
accounting branch, or observational counter. Resource accounting is a separate
opt-in package and capability identity. A nullable budget is not used.

## Profiles

Every versioned family carries an explicit positive numeric version. Version
identifiers are values, not `_V1` name suffixes. The initial implementation
accepts version `1` for each declared versioned family and rejects every other
value before byte zero or destination begin. Adding behavior under an existing
family/version is incompatible. Unversioned policy literals are immutable
flags; changed semantics require a new literal rather than reinterpretation.

No profile factory, parameter default, public constant, capacity default, or
implicit policy is provided. Callers construct every field explicitly.

The initial syntax profile is strict RFC 8259 JSON over UTF-8 Unicode scalar
values. It rejects a BOM, malformed UTF-8, unpaired surrogate escapes, raw
control characters, comments, trailing commas, nonstandard number spellings,
and nonfinite values. Top-level scalars are accepted only with
`Accept_Any_Value`; `Require_Object` rejects another root kind at that root's
actual first non-whitespace source octet.

`Reject_Duplicates` compares decoded object names by exact Unicode-scalar
sequence without normalization. `Preserve_Unchecked` exposes every name in
source order and performs no duplicate storage or comparison. It never selects
a winner or sets a duplicate flag. Alias collisions remain a Serde concern.

The trusted package identity is the no-accounting capability. Accounting does
not appear in its profile records. A parser instance rejects a profile whose
duplicate policy differs from its static `Duplicate_Mode`.

`Ordinary_Compact` emits UTF-8 without a BOM or added whitespace, preserves
caller object-member order and exact validated number lexemes, leaves solidus
and valid non-ASCII unescaped, uses short standard escapes, and uses uppercase
hexadecimal for remaining escaped controls. It is not canonical JSON. No key
sorting, key-order verification, normalized number spelling, or final newline
is implied.

## Event grammar

The closed grammar is:

```text
Document_Begin value Document_End
value = object | array | string | number | Null_Value | Boolean_Value
object = Object_Begin *(Name_Begin name-pieces Name_End value) Object_End
array = Array_Begin *value Array_End
string = String_Begin string-pieces String_End
number = Number_Begin number-pieces Number_End
```

Container lengths are unknown. JSON null, Boolean, object, and array events do
not imply Ada optionals, variants, records, schemas, aliases, or fingerprints.
Events remain provisional until `Document_Complete`; the consumer owns its
candidate commit/abort transaction.

Every `Name_Fragment`, `String_Fragment`, and `Number_Fragment` has a raw slice
into the returning call's input. A text fragment with
`Decoded_Is_Raw_Range` covers complete decoded scalars whose UTF-8 equals that
raw source range. `Decoded_Inline_Scalar` covers one complete scalar produced by
an escape or assembled across chunks. `No_Decoded_Fragment` covers only a raw
split piece that does not yet complete a scalar, or a final provisional piece
returned before a retained resource failure. Decoded fragments always end at
scalar boundaries; no decoded payload is eligible for an incomplete piece.
`Number_Fragment` covers exact source octets without conversion or normalization
and has no complete-token length ceiling.

`Event` is a compact private value. Its size, packing, representation, and ABI
are not public. `Kind` and `Source` are always eligible. `Boolean_Data` is
eligible only for `Boolean_Value`. `Decoded_Source` is eligible only when
`Decoded_Kind` is not `No_Decoded_Fragment`; `Decoded_Scalar` is eligible only
for `Decoded_Inline_Scalar`. An inline scalar has `Length` in `1 .. 4`; exactly
`Octets (1 .. Length)` is eligible and the remaining components are
unspecified. `Scalar_Octets` is a constrained `Stream_Element_Array` subtype,
so the eligible prefix composes directly with other octet APIs.

`Document_Begin`, `Document_End`, `Number_Begin`, and `Number_End` have a
zero-length source at their exact stream position. Object/array delimiters and
name/string opening and closing quotes have their exact one-octet source.
Null/Boolean source covers its complete literal even when the literal crossed
input calls. Fragment source covers exactly that event's raw piece. Successive
raw-bearing events for one name, string, or number cover its lexical source in
order without gaps or overlap, without promising a particular coalescing
across chunk schedules.

`Has_Raw_Slice` is true for object/array delimiters, name/string begin,
fragment, and end events, and number fragments. It is true for null/Boolean
only when the complete literal lies in the exact input window returning that
event; it is false when the literal crossed calls. It is false for document
begin/end and zero-length number begin/end. `Decoded_Kind` is
`No_Decoded_Fragment` for every event except a name/string fragment.

For a scalar split across calls, a fragment's `Source` and raw slice cover only
the piece in the returning call, while `Decoded_Source` may begin in an earlier
call and covers the complete scalar or escape provenance. A
`No_Decoded_Fragment` piece is never appended to decoded output; the later
`Decoded_Inline_Scalar` appends the completed scalar exactly once. A final
raw-only provisional piece caused by name-resource denial is followed by a
zero-consumption terminal failure.

A raw range is borrowed only from the exact unchanged `Input` actual supplied
to the `Step` or `Drain` call that returned it. `Input_Origin` is the parser's
absolute byte position before that call. `Resolve_Raw_Range` validates only
that the absolute range is contained in the caller-described origin/length
window and returns counts relative to that input's `First`; it does not
authenticate an Ada object, parser, operation, call, or unchanged contents. On
`No_Raw_Slice` or `Range_Outside_Window`, the returned range contains zero
counts. Passing the producing result together with its exact unchanged input
is a caller precondition. The event retains no access value. A consumer must
observe or copy raw bytes before the input actual is released, modified, or
reused. In particular, a Serde adapter may not retain such a range in a
builder. No stale/foreign-window rejection is claimed.

## Parser lifecycle

`Initialize` is accepted only in `Uninitialized`. It validates and freezes the
complete profile, clears parser state, and enters `Ready` without consuming
input. Unsupported or incompatible profiles enter `Failed` with no applied
profile. The first accepted parsing call enters `Active`.

`Step` returns one event, `Need_Input`, `Document_Complete`, `Step_Failed`, or
`Call_Rejected`. `Consumed` is a count from `Input'First`. `Need_Input` consumes
the complete supplied input. A nonfinal empty input may return `Need_Input`;
final input deterministically completes or fails. `End_Of_Input` is latched
when an otherwise legal `Step`/non-null `Drain` call is admitted, even if that
call returns after one event or because output fills. Every resubmitted suffix
must keep it true. A false value after the latch returns `Call_Rejected` or
`Drain_Rejected` with `Final_Input_Retracted` at the current `Source_Byte`, zero
consumed/produced, and no parser-state change.

`Drain` uses the same semantic engine and event grammar as `Step`. Only the
`Produced`-component prefix beginning at `Events'First` is eligible. `Consumed` is a count from
`Input'First`; every raw range refers to that exact input. A null event array
returns `Output_Full`, zero consumed, zero produced, and leaves the parser
unchanged. Filling the output takes precedence over a later pending terminal
condition; the next call reports it. Produced events are provisional even if
the same call reports failure. Capacity-one `Drain` calls over each unconsumed
suffix, preserving latched finality, produce the same transcript and terminal
result as repeated `Step` calls; stop precedence need not match in one call.

`Document_Complete` follows `Document_End`, enters `Completed`, and is the only
parser acceptance gate. A terminal malformed/resource failure retains its
primary diagnostic until cleanup/reset. `Abort_Document` is nonraising and
idempotent in active/failure cleanup states. `Reset` creates a fresh `Ready`
operation only from `Failure_Pending`, `Completed`, `Failed`, or `Aborted`,
after validating the new explicit profile. Illegal lifecycle calls are
nonmutating and cannot
replace a retained primary diagnostic.

`Step_Result` and `Drain_Result` are definite records, so copy-out through a
caller object cannot raise because a discriminant was constrained to another
outcome. `Input_Origin` is always the parser's absolute next byte before the
call. Every rejected call returns zero consumed and zero produced. An
`Event_Ready` step may consume zero for a synthetic begin/end event.
`Output_Full` on a nonnull array publishes exactly `Events'Length` events.
Malformed syntax, UTF-8, escape, surrogate, literal, and number failures include
the octet that proves the failure when that octet is representable and was
inspected. Depth denial, strict-name index-capacity-zero denial, top-level-kind
rejection, and offset exhaustion stop before consuming the denied opener,
name-opening quote, root byte, or unrepresentable octet respectively. A decoded
name-scalar storage denial consumes and publishes its final raw-only source
piece before retaining the failure; it publishes no decoded event for that
scalar, and the next call reports the failure with zero consumption. Duplicate
and index denial detected at `Name_End` consume the closing quote but publish no
`Name_End`. Ineligible `Item` and `Diagnostic` fields are valid but unspecified.

The closed parser lifecycle is:

| Call and state | Resulting state and effects |
|---|---|
| `Initialize` in `Uninitialized` | Valid matching profile: `Ready`, applied profile present. Invalid or mismatched profile: `Failed`, no applied profile, no input consumed. |
| `Initialize` elsewhere | Nonmutating `Invalid_State`; a retained terminal primary takes precedence. |
| `Step`/nonnull `Drain` in `Ready` | Admitted, freezes finality if requested, enters `Active`, and first publishes `Document_Begin`. |
| `Step`/nonnull `Drain` in `Active` | Admitted unless finality is retracted; returns the grammar result described above. A final raw-only event before name-storage denial enters `Failure_Pending`. |
| `Step`/nonnull `Drain` in `Failure_Pending` | Return `Step_Failed`/`Drain_Failed` with the retained primary and zero consumption/publication, then enter `Failed`. |
| `Step`/`Drain` in `Uninitialized`, `Completed`, `Failed`, or `Aborted` | Rejected with zero consumption/publication. `Failed` returns its retained primary as a rejection diagnostic; other states return `Invalid_State`. |
| Null `Drain` in any state | `Output_Full`, zero consumed/produced, and no state, profile, or finality change. This capacity stop precedes lifecycle admission. |
| `Abort_Document` in `Ready` or `Active` | `Aborted`; clean abort retains a cleared terminal diagnostic and keeps the applied profile queryable. |
| `Abort_Document` in `Failure_Pending` | Enter `Failed`; retain the primary diagnostic and applied-profile eligibility. |
| `Abort_Document` in `Failed` | Idempotent `Failed`; retain the primary diagnostic and applied-profile eligibility. |
| `Abort_Document` in `Uninitialized`, `Completed`, or `Aborted` | Nonmutating no-op. |
| `Reset` in `Failure_Pending`, `Completed`, `Failed`, or `Aborted` | Valid matching profile: fresh `Ready` with that applied profile and finality unlatched. Invalid profile: `Failed`, no applied profile. |
| `Reset` elsewhere | Nonmutating `Invalid_State`; a retained terminal primary takes precedence. |

`Has_Applied_Profile` becomes true only after successful `Initialize` or
`Reset` and remains true through that operation's `Active`, `Completed`,
`Failure_Pending`, `Failed`, or `Aborted` state. `Terminal_Diagnostic` is
eligible in `Failure_Pending`, `Failed`, and `Aborted`. A clean `Aborted` parser
has a cleared terminal diagnostic. A retained failure never becomes `Aborted`,
and its primary cannot be replaced by cleanup or an illegal call.

The parser is bounded by caller-selected `Maximum_Depth`, decoded-name octet
capacity, and name/index capacity. There are no defaults. `Maximum_Depth`
counts simultaneously open object and array containers: a root container is
depth one, nested containers add one, and a scalar root needs zero. An opener
that would make depth exceed the bound fails before consuming or publishing
that opener with `Depth_Exhausted` at its source byte. The writer uses the same
depth unit and fails before staging the denied opener.

In preserve mode both name capacities are ignored and may be zero; no
duplicate resource failure is possible. In strict mode,
`Name_Octet_Capacity` bounds the total decoded UTF-8 octets of unique names
retained by all simultaneously open objects plus the active candidate. Closing
an object releases exactly the storage acquired since its opener. A duplicate
candidate is reclaimed at detection. An append that would exceed the exact
octet capacity is atomic with respect to decoded-name storage: the completed
scalar is not stored and no decoded event is published for it. Its complete raw
source is consumed and published as one or more provisional raw-only pieces,
then `Name_Storage_Exhausted` is reported with zero further consumption and is
blamed on the name's opening quote. This rule is unchanged when the scalar's
UTF-8 or escape source crosses input calls.

`Name_Capacity` independently bounds both the total retained name leaves and
the total crit-bit internal nodes across simultaneously open objects. A unique
name consumes one leaf and, unless it is the first name in that object, one
node. The active candidate consumes neither until `Name_End`. Capacity zero
therefore rejects a strict name before consuming or publishing its opening
quote. An exact-fit unique name succeeds; the next unique name that needs a
leaf or node consumes the closing quote, fails at `Name_End`, publishes no
`Name_End`, and reports `Duplicate_Index_Exhausted` at its opening quote. Exact
duplicate comparison occurs before unique-name index reservation, so
`Duplicate_Name` wins when both could otherwise apply. Duplicate detection
likewise consumes the later closing quote, occurs at the later `Name_End`,
publishes no later `Name_End`, and blames the later opening quote.

For a candidate of decoded length `L`, with `K` retained nodes and an existing
leaf length `E`, strict completion performs at most two descents of `K` node
bit probes, one comparison of the eight-octet length prefix plus at most
`max (L, E)` content octets, and at most eight bit tests in the first differing
octet; append performs exactly `L` octet stores. `K <= Name_Capacity` and
`L, E <= Name_Octet_Capacity`. There is no scan over every prior name and no
collision-only or quadratic fallback.

## Source diagnostics

Parser source coordinates are zero-based absolute input-octet offsets. Invalid
UTF-8 blames the octet that proves invalidity, except an overlong, surrogate,
or out-of-range sequence whose completed prefix blames its stored lead. An
unknown single-character escape blames its offending character; an invalid
`\u` hex digit blames the first nonhex octet. A high surrogate followed by a
raw character, quote, or valid non-low `\u` escape blames the high-surrogate
escape start. A malformed following escape such as `\q` blames its offending
character. A lone low surrogate blames its own reverse solidus.
Truncation reports the first missing octet position. Depth denial reports the
container opener. Storage denial during a name reports that name's opening
quote. Offset exhaustion reports the first unrepresentable position.

Parser error classification and same-position precedence are closed as follows:

- at a value start, `n`, `t`, and `f` select literal validation; a later
  mismatch is `Invalid_Literal`. Minus or a decimal digit selects number
  validation; a rejected DFA transition is `Invalid_Number`. Another byte that
  cannot begin a value is `Unexpected_Token`;
- after a reverse solidus, an unknown escape or malformed `\u` spelling is
  `Invalid_Escape`. A syntactically valid scalar escape that is a lone low
  surrogate or fails the required high/low pairing is `Invalid_Surrogate`;
- `Offset_Exhausted` wins before inspecting an octet whose position is not
  representable. UTF-8/escape/syntax validation wins before a resource effect
  that would consume the same decoded scalar. Name-octet denial precedes
  end-of-name index/duplicate work; at `Name_End`, exact duplicate detection
  precedes unique-name index reservation as specified above;
- depth is tested only after recognizing a valid container opener. An invalid
  value-start byte is therefore `Unexpected_Token`; a recognized opener beyond
  the bound is `Depth_Exhausted`.

## Token collector

The collector binds one caller-provided unconstrained array and performs no
allocation. `Begin_Token` starts unpublished staging. `Append` accepts arbitrary
array bounds and is atomic per call: all supplied octets are copied or none are.
It retains no input reference. `Complete_Token` publishes the length only after
all staged bytes are present. Until then the storage is candidate state and the
caller must not interpret it as a completed token. Capacity failure publishes
no length and enters `Failed`. `Abort_Token` and `Reset` are nonraising and do
not replenish any future external budget.

The collector is syntax-neutral about its byte source: a parser consumer sends
decoded name/string fragments or exact number fragments according to the
selected `Token_Kind`. It does not recharge parser work or perform numeric
conversion.

The collector transition table is:

| Call and state | Resulting state and publication |
|---|---|
| `Begin_Token` in `Empty` | `Collecting`, zero staged/public length. |
| `Append` in `Collecting` | Complete copy: remains `Collecting`; capacity denial: `Failed`, public length zero. Empty input is accepted without effect. |
| `Complete_Token` in `Collecting` | `Complete`, publishes the exact staged length, including zero. |
| `Abort_Token` in any state | Idempotent `Empty`, public/staged lengths zero; retained bytes are unspecified. |
| `Reset` in any state | Fresh `Empty`, public/staged lengths zero; retained bytes are unspecified. |
| Any other call/state combination | `Invalid_Order`, no state or publication change. |

Successful `Begin_Token` and successful or empty `Append` return
`Operation_Accepted`; successful `Complete_Token` returns `Token_Completed`;
capacity denial returns `Storage_Exhausted`. `Kind` in `Collecting` or
`Complete` is the argument accepted by `Begin_Token`. The readable completed
prefix begins at `Storage'First`.

The bound storage outlives the collector. The caller does not independently
read or write it during a mutating call or while state is `Collecting` or
`Failed`. `Append.Value` must not overlap the bound storage; the collector does
not promise snapshot or memmove semantics for an aliased source. In `Complete`,
the caller may read exactly the first `Collected_Length` components
and does not mutate them until `Reset` or `Abort_Token`. The collector never
clears or promises values outside the published prefix.

## Writer destination and lifecycle

The destination is a whole-document transaction. `Begin` starts unpublished
staging; `Commit` is the only publication point; `Abort` ends staging without
publication even when it reports cleanup failure. A failed begin owns no
transaction. The destination outlives writer finalization and is not accessed
independently while the writer is active. The writer is scoped to and finalized
with its one logical owner. A task may borrow it only for a synchronized,
non-escaping call whose completion is joined before the owner or any other task
accesses or finalizes the writer. An unsynchronized or escaping borrow, or one
that can outlive the writer or destination, violates that ownership contract.

Every destination formal is synchronous, nonraising, returns in finite time,
does not call the writer recursively, mutate writer aliases, or retain `Data`
beyond `Write`. Every admitted mutating writer call executes as one
abort-deferred operation, including its finite validation/scan work,
destination calls, and adjacent JSON/ownership-state transitions. The caller
is not required to arrange task-abort deferral. This is a deliberate
correctness-over-cancellation-latency tradeoff: the hot per-octet loop contains
no abort check or dispatch, while a pending task abort waits for the call's own
finite scan and caller-supplied destination work to return.

`Destination_Begin` must either
complete with a coherent returned status or leave a transaction that a later
`Destination_Abort` can end. A failed `Begin` creates no transaction. A failed
`Commit` publishes nothing and leaves the transaction abortable. A successful
commit publishes exactly once before the writer records `Completed` in the
same abort-deferred region. `Abort` is itself abort-safe and ends the
transaction without publication even when its status is `Abort_Failed`.
All destination formals may block only according to the caller-supplied
implementation and must return. Task abort is deferred throughout them, so a
formal that violates the finite-return obligation can delay task abort
indefinitely. The writer adds no numeric timeout, helper task, preemption, or
scheduling policy.
Violating a generic formal obligation is outside the writer contract; raised
exceptions and dangling retained input are not recovered.

`Destination_Write` is bulk and prefix-reporting. On success it accepts the
complete array. On capacity exhaustion it accepts the longest prefix and
returns that count. On another error it returns zero and that call has no
staging effect. Counts are independent of the array's lower bound. This permits
bulk throughput while making capacity failure occur at the exact staged byte
regardless of caller fragment boundaries. Timing of an injected external
destination error is not chunk-invariant.

The result invariants are total: `Write_Succeeded` means
`Written = Data'Length`; `Write_Exhausted` means
`Written < Data'Length` and that count is the exact longest accepted prefix;
`Write_Failed` means `Written = 0` and no effect for the call. In every case
`Written <= Data'Length`. Empty data can return only `Write_Succeeded` with
zero written or `Write_Failed`; it cannot return `Write_Exhausted`.

The writer validates and freezes an explicit trusted ordinary profile in
`Initialize`, then enters `Ready` without touching the destination.
`Begin_Document` begins the transaction and enters `Active`. Calls follow the
JSON grammar; no container length is supplied. Name/string fragments may split
inside UTF-8 sequences. The writer retains at most one scalar's derived carry,
validates UTF-8 incrementally, and emits maximal safe spans in bulk. Number
fragments preserve exact octets and share the strict parser number DFA.

Grammar, UTF-8, number, offset, destination, and commit failures abort an owned
transaction exactly once and retain the JSON failure as primary. Abort failure
is secondary. A commit failure does not claim publication and is followed by
abort. Explicit abort without an earlier failure promotes abort failure to
primary. Finalization is a nonraising safety net that aborts one still-owned
transaction and cannot replace an already observable primary diagnostic.

If task abort or another abnormal transfer is pending during an admitted
mutating call, it is delivered when the abort-deferred call finishes. Before
unwinding can escape the writer, an abort-deferred cleanup finalizer ends an
owned unpublished transaction exactly once and seals the writer `Aborted`, so
no later grammar call or commit is possible. Successful cleanup retains a
cleared diagnostic when no primary failure existed; failed cleanup retains
`Abort_Failed` at the next staged-output coordinate. An already established
primary remains primary and abort failure is secondary. A successful commit
that has already published and recorded `Completed` remains `Completed`; the
cleanup finalizer never claims to retract publication.

`Finish_Document` requires one complete balanced root, commits, and enters
`Completed` only on success. `Reset` is accepted only from terminal states and
never implicitly aborts an active document. Calls rejected only for lifecycle
state do not touch the destination or replace terminal diagnostics.

Writer token coordinates are zero-based aggregate caller token-input octets.
Staged-output coordinates are zero-based candidate octets. Grammar/depth errors
use the zero-based public JSON call ordinal. Destination exhaustion reports the
first unaccepted staged byte. Invalid UTF-8 and number input report the exact
token byte that proves invalidity; truncation reports the first missing token
byte.

The closed writer lifecycle is:

| Call and state | Resulting state and effects |
|---|---|
| `Initialize` in `Uninitialized` | Valid profile: `Ready` with applied profile; invalid: `Failed`, no applied profile, no destination call. |
| `Initialize` elsewhere | Nonmutating `Invalid_State`; retained terminal diagnostic wins. |
| `Begin_Document` in `Ready` | Successful destination begin: `Active` and transaction owned; failed begin: `Failed`, no ownership and no abort. |
| Grammar call in `Ready` other than `Begin_Document` | Reserves its call ordinal, returns `Invalid_Writer_Grammar`, enters `Failed`, and makes no destination call. |
| Grammar call in `Active` (including another `Begin_Document`) | Success remains `Active`; grammar/further failure aborts once and enters `Failed`. |
| `Finish_Document` in `Active` | Balanced root and successful commit: `Completed`; validation/commit failure aborts once and enters `Failed`. |
| `Abort_Document` in `Ready` | `Aborted`, no destination call. |
| `Abort_Document` in `Active` | Destination abort exactly once, then `Aborted`; abort failure is primary if none existed. |
| `Abort_Document` in `Failed` or `Aborted` | Idempotent no-op; retain diagnostics. |
| `Abort_Document` in `Uninitialized` or `Completed` | Nonmutating no-op. |
| `Reset` in `Completed`, `Failed`, or `Aborted` | Valid profile: fresh `Ready`; invalid: `Failed` with no applied profile. Never aborts implicitly. |
| `Reset` elsewhere | Nonmutating `Invalid_State`; no destination call. |
| Other mutating call in uninitialized/terminal state | Nonmutating `Invalid_State`; retained terminal diagnostic wins. |

Initialization, reset, explicit abort, queries, and finalization have no JSON
call ordinal. After initialize/reset the next admitted ready/active grammar call
reserves ordinal zero before effects; each later admitted grammar call reserves
the next value. Calls rejected solely because the writer is uninitialized or
terminal do not reserve an ordinal. When the next ordinal equals
`Byte_Offset'Last`, the call is denied before effects with `Offset_Exhausted` at
that last representable coordinate; an active transaction aborts once. Thus
successful admitted calls use ordinals zero through `Byte_Offset'Last - 1`.
Token and staged offsets follow the same boundary convention. A bulk span may
advance through the representable prefix to make the next offset equal
`Byte_Offset'Last`; the next octet is denied before staging and reports that
last representable coordinate. An earlier destination exhaustion/error retains
precedence over a later offset boundary.

Destination diagnostics map as follows:

- failed `Begin`: `Destination_Failed`, `Staged_Output_Byte` zero, no ownership;
- exhausted `Write`: `Destination_Exhausted` at old staged offset plus `Written`;
- failed `Write`: `Destination_Failed` at the old staged offset;
- failed `Commit`: `Commit_Failed` at the next staged offset, followed by abort;
- failed `Abort`: `Abort_Failed` at the next staged offset, secondary when a
  primary failure already exists;
- depth or writer grammar denial: `JSON_Call_Ordinal` of the admitted call;
- malformed name/string/number input: aggregate `Writer_Token_Byte`;
- token or staged offset exhaustion: the first denied effect, reported as
  `Offset_Exhausted` at `Byte_Offset'Last`.

`Clear` sets `Code` and `Secondary` to `No_Error`, both coordinates to
`No_Coordinate`, and both offsets to zero. A primary offset is eligible only
when its coordinate is not `No_Coordinate`. Secondary coordinate/offset are
eligible only when `Secondary /= No_Error`; otherwise they remain cleared.

Every successful writer call returns a cleared diagnostic. Empty name, string,
and number fragments are legal no-ops, still reserve their grammar-call
ordinal, and return a cleared diagnostic. Abort no-ops in `Uninitialized` and
`Completed` return a cleared diagnostic; abort no-ops in `Failed` or `Aborted`
return the retained terminal diagnostic. Other rejected lifecycle calls return
their deterministic rejection diagnostic without changing retained state.

Fragment processing is defined as if validation and resulting output occur in
input order. An earlier destination exhaustion/error on an emitted prefix wins
over malformed UTF-8/number or offset failure proved by a later input byte.
Implementations may scan ahead and write bulk spans only when they return the
same primary status, coordinate, staged prefix, and cleanup behavior. This rule
is invariant under equivalent fragment schedules except for explicitly
injected external destination-error timing.

## Numbers

The parser and writer preserve exact number lexemes. Numeric conversion is a
separate checked operation over a complete byte array and never rereads parser
input. Integer conversion accepts only strict JSON integer spellings; decimal
fractions/exponents are invalid syntax for integer conversion. It detects range
before arithmetic overflow. Signed conversion maps `-0` to zero. Unsigned
conversion rejects every negative spelling, including `-0`. Every definite
numeric result contains a valid scalar value on every status; that value is
unspecified and ineligible unless the status declares conversion success.

Integer rendering is exact base ten with no leading zero, exponent, or added
plus sign. It is transactional: insufficient output capacity returns zero and
leaves the caller array unchanged.

Binary64 uses an always-valid `Interfaces.Unsigned_64` IEEE 754 interchange
encoding at its public boundary. Bit zero is the numeric least-significant bit;
bit 63 is the sign, bits 62 through 52 are the biased exponent, and bits 51
through 0 are the fraction. This mapping is independent of host byte order and
does not rely on unchecked conversion. Conversion uses strict JSON syntax and
round-to-nearest ties-to-even. It never needs to load a NaN or infinity into a
validity-checked floating object merely to classify it. Results distinguish exact, rounded,
invalid, underflow-to-signed-zero, and finite overflow. Exact lexical `-0` is
exact and publishes the negative-zero encoding; nonzero underflow publishes
status only and no rounded value. Overflow never publishes infinity. Rendering
rejects every NaN/infinity encoding and emits the shortest strict JSON decimal
that round-trips to the same finite binary64 encoding,
preferring fixed notation when fixed and exponent forms have equal byte length.
Otherwise scientific notation has one nonzero digit before the decimal point.
Among equally short coefficients that round-trip, rendering selects the decimal
closest to the exact binary value; an exact distance tie selects the coefficient
whose final retained decimal digit is even.
It uses lowercase `e`, no plus on a positive exponent, and `-0` for negative
zero. Every render failure sets produced length to zero and leaves output
unchanged.

Decimal/application conversions remain separate future packages. Binary64
behavior and representation claims require maintained GNAT/platform evidence;
mere compilation is insufficient.

## Optional accounting

The trusted baseline is the functional and performance authority. A future
accounted package must statically reuse the same semantic engine while binding
one nonreplaceable caller ledger for an operation. Its cost-model identity,
positive prefix-composable grants, dimensions, charge order, debit/denial
behavior, offsets, reset/rebind rules, and fragmentation invariance require a
separate public declaration and consumer review. Trusted generated assembly
must contain no accounting state, calls, or branches.
