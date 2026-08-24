# Draft public contracts

This document is normative for the adjacent draft Ada declarations. It will be
converted into GNATdoc comments when the declarations move into `src/`.

## Generic formal contracts

Each parser and writer instance has one logical owner. Public mutating calls on
that instance, its budget, and (for a writer) its destination are serialized;
concurrent calls or independent target access while active violate the
contract. Sequential ownership transfer is permitted only when the prior owner
is no longer executing a call.

The core does not introduce an Ada tasking dependency or an abort-deferred
region. A caller must defer asynchronous task abort, asynchronous transfer of
control, and cancellation while a public mutating call, budget hook, destination
formal, or finalization cleanup is executing. Such interruption is outside the
contract because it can occur between a destination side effect and its writer
ownership-state update. The finalization guarantee covers normal scope exit and
synchronous exception unwinding initiated outside a mutating call; it does not
claim recovery from asynchronous task abort. JSON operations and conforming
generic formals are themselves nonraising.

`Charge` executes synchronously on the caller's stack. It must not allocate,
raise an exception, retain an engine or array reference, call the same parser or
writer recursively, or mutate JSON state through another alias. `Deny_Charge`
means the named effect did not occur. An exception violates the generic
contract; JSON does not convert arbitrary application exceptions into an input
or resource status.

Every destination operation executes synchronously on the writer caller's
stack. A destination must not retain `Data` after `Destination_Write` returns.
The caller must not access `Target` independently while the writer is `Active`.

The destination transaction contract is:

- failed `Destination_Begin` creates no transaction and stages nothing;
- successful `Destination_Begin` creates one unpublished transaction;
- `Destination_Write` is all-or-nothing for the supplied array;
- failed `Destination_Write` leaves the transaction abortable and publishes
  nothing;
- successful `Destination_Commit` is the only publication point;
- failed `Destination_Commit` publishes nothing and leaves the transaction
  abortable;
- `Destination_Abort` is nonraising and idempotent, publishes nothing, and ends
  the transaction even when it reports `Stage_Error` for secondary cleanup;
- the destination operations must not call the writer recursively.

The writer catches no exception from a destination formal. Raising violates the
generic contract because Ada cannot guarantee transaction cleanup after an
arbitrary foreign exception. Explicitly allocating destinations catch their own
`Storage_Error`, clean up, and return `Stage_Error`.

`Writer` is limited controlled. Its nonraising finalization safety net checks
`Owns_Transaction`; when true, it advances the nondeniable cleanup/destination
observations and invokes `Destination_Abort` exactly once. It cannot return a
diagnostic because the object is leaving scope. A conforming destination ends
the transaction without publication even if it reports a cleanup error. The
safety net is a last resort for normal caller exception unwinding or
abandonment outside a mutating call; callers use explicit `Abort_Document` when
they need the cleanup result. After finish, explicit abort, or failure cleanup
clears ownership, finalization is a no-op. The access discriminant requires the
target to outlive writer finalization.

## Profiles

One successful `Initialize` or `Reset` copies and freezes a complete profile.
No profile field changes during an operation. `Applied_Profile` returns that
copy. `Has_Applied_Profile` is false before the first successful initialization
and after any rejected initialize/reset profile; `Applied_Profile` is then
ineligible. Unsupported or incompatible profiles fail before input consumption
or destination begin.

Successful initialization/reset clears the retained diagnostic. A successful
abort with no earlier failure retains that cleared diagnostic; it does not
invent an error. Consequently `Terminal_Diagnostic` in such an `Aborted` state
returns `No_Error`, while abort after `Failed` retains the primary failure.

`Interoperable_RFC8259_V1` returns:

```text
Syntax         = RFC8259_Syntax_V1
Unicode        = Unicode_Scalars_V1
Compatibility  = No_Extensions_V1
BOM            = Reject_BOM_V1
Duplicates     = Reject_Duplicate_V1
Top_Level      = Accept_Any_Value_V1
```

`Compact_UTF8_V1` selects `RFC8259_Syntax_V1`, `Unicode_Scalars_V1`, and
`Ordinary_Compact_V1`. It does not check, sort, remove, or select duplicate
names. It preserves every caller name and member in call order.

`Require_Object_V1` changes only the accepted root kind. It rejects another root
at that root's first source octet. It does not imply Type IR schema authority.

`No_Extensions_V1` rejects comments, trailing commas, nonstandard and nonfinite
number spellings, and raw control characters. No extension-accepting profile or
flag is present in this initial public draft. Each future compatibility profile
or flag requires separate user authority and P0/P1/P2 review before becoming an
accepted language. `Reject_BOM_V1` rejects the three-octet UTF-8 signature only
at document offset zero. The same octets inside a string decode normally to
U+FEFF; outside a string later in the document they follow ordinary JSON token
rules and are not classified as a BOM. No BOM-ignoring choice is public.
`Unicode_Scalars_V1` never replaces malformed UTF-8 or an unpaired surrogate.

`Detect_And_Report_V1` accepts every member. Only the later member's `Name_End`
event has `Is_Duplicate = True`. `Reject_Duplicate_V1` fails at the later name's
opening quote before returning its `Name_End`; earlier name events remain
provisional. `Preserve_Unchecked_V1` retains no name history and sets
`Is_Duplicate = False` because duplication is unknown.

## Event field validity and coverage

Events are ordinary copyable values and contain no access component. Inline
decoded scalar bytes remain valid in every copy. A `Raw_Slice` is meaningful
only together with the exact `Input` array supplied to the `Step` that returned
it. It maps to:

```text
Input (Input'First + Stream_Element_Offset (First_Count)
       .. Input'First + Stream_Element_Offset (First_Count + Octet_Length) - 1)
```

The zero-length case denotes a null range and performs no subtraction. The
caller may retain the range only if it also retains and identifies that exact
input array. JSON retains neither.

`Source` is an absolute range and remains meaningful without the chunk.
`Source_Start` equals `Source.First` except for a source-free document event,
where it is the next absolute input offset and `Source.Octet_Length = 0`.

Field validity is:

- structural begin/end, null, and Boolean events use `Source`; a chunk slice is
  present only when the entire spelling belongs to the current chunk;
- `Boolean_Data` is meaningful only for `Boolean_Value`;
- name, string, and number fragment events always have a nonempty raw slice;
- all raw token octets between the matching begin and end events occur exactly
  once, in order, without a gap or overlap across fragment `Source` ranges;
- `Decoded_Is_Raw_Range` means the raw slice is complete valid UTF-8 ending at a
  scalar boundary and is also the decoded output;
- `No_Decoded_Fragment` reports an incomplete split escape or UTF-8 sequence,
  or a number fragment;
- `Decoded_Inline_Scalar` contains exactly one complete UTF-8 scalar derived
  from an escape or from raw UTF-8 carried across chunks; `Decoded_Source`
  covers every source octet that produced that scalar, including earlier raw
  fragments;
- `Is_Duplicate` is meaningful only for `Name_End` under
  `Detect_And_Report_V1`.

Begin and end quote events own the quote octets. Fragment events cover only
contents between quotes. Number begin and end events have zero-length source
ranges at the token boundaries; number fragments cover the complete lexeme.
`Document_End` follows the root end event and precedes trailing-whitespace
validation. `Document_Complete` is an outcome, not another event.

Fragment boundaries may change with chunking. Concatenated raw fragment ranges,
decoded output, and the non-fragment grammar-event sequence do not.

## Parser lifecycle and step rules

A newly declared parser is `Uninitialized`.

| Operation and state | Result and next state |
| --- | --- |
| `Initialize` in `Uninitialized` | Valid profile: `Ready`; invalid profile: `Failed`. |
| `Initialize` otherwise | `Invalid_State`; state and retained diagnostic unchanged. |
| `Step` in `Uninitialized` | `Call_Rejected`, consumes zero, reports `Invalid_State`, remains `Uninitialized`. |
| First `Step` in `Ready` | Charges and returns `Document_Begin`, consumes zero, enters `Active`. |
| `Step` in `Active` | One event, `Need_Input`, `Document_Complete`, or terminal `Step_Failed`. |
| `Step` in a terminal state | `Call_Rejected` with `Invalid_State`; state and retained diagnostic unchanged. |
| `Abort_Document` in `Uninitialized` | No-op; remains `Uninitialized`. |
| `Abort_Document` in `Ready`, `Active`, or `Completed` | Enters `Aborted`; no diagnostic is fabricated. |
| `Abort_Document` in `Failed` | Enters `Aborted` and retains the primary diagnostic. |
| `Abort_Document` in `Aborted` | No-op. |
| `Reset` in `Completed`, `Failed`, or `Aborted` | Valid profile: fresh `Ready`; invalid profile: `Failed`. |
| `Reset` otherwise | `Invalid_State`; state and counters unchanged. |

`Need_Input` consumes the complete supplied array and returns no event. An
event may consume only a prefix. The caller resubmits the unconsumed suffix;
`Consumed` is a count, never an index. `End_Of_Input = True` certifies that no
octet follows the supplied array. When an event consumes only a prefix of a
final array, the caller passes `True` again with the suffix. When an event
consumes the final octet, the caller passes an empty final array on the next
step so the parser can apply EOF. An empty nonfinal array returns `Need_Input`.

After the root finishes, the parser returns `Document_End`, consumes trailing
RFC whitespace on later steps, rejects other trailing input, and returns
`Document_Complete` only after final input. Supplying bytes after a completed
document is a rejected call because `Completed` is terminal.

A malformed-input or resource failure returns `Step_Failed`, enters `Failed`,
publishes no event from that step, and retains its primary diagnostic. A
protocol misuse returns `Call_Rejected` and does not overwrite a terminal
diagnostic. `Reset` does not call or reset `Budget`.

`Consumed` is meaningful for every outcome. `Item` is meaningful only for
`Event_Ready`. `Diagnostic` is cleared for `Event_Ready`, `Need_Input`, and
`Document_Complete`; it describes the call for `Step_Failed` and
`Call_Rejected`. An invalid profile clears the applied-profile presence flag;
it never exposes a rejected profile as applied.

## Parser capacities

Root scalar depth is zero. The root container depth is one. A container open is
rejected before mutation when its resulting live depth exceeds
`Maximum_Depth`.

`Name_Octet_Capacity` is the total number of decoded name octets that can be
live across all open objects plus the current candidate name. Nested objects
share one LIFO arena; closing an object restores its entry mark.

`Name_Capacity` independently bounds the live leaf slots and internal crit-bit
node slots shared across all open objects. Each retained unique name uses one
leaf. Each nonempty object with `N` unique names uses `N - 1` internal nodes.
The current candidate consumes name octets but no leaf or node until successful
insertion. A permitted duplicate consumes no new leaf or node and its candidate
octets are reclaimed after `Name_End`. With `Preserve_Unchecked_V1`, both name
capacities are ignored and may be zero.

An empty name uses one leaf and zero name octets. When duplicate detection is
enabled and `Name_Capacity = 0`, its opening quote fails with
`Duplicate_Index_Exhausted`. Other capacity failures report the first source
octet whose scalar or insertion cannot be retained.

## Writer lifecycle and grammar

`Initialize` validates and freezes a profile and enters `Ready` without touching
the destination. `Begin_Document` is the only operation legal in `Ready`. It
advances its observational call counter, validates the state, calls
`Destination_Begin`, and enters `Active` only after success. It has no deniable
budget charge. Failed begin enters `Failed` with no destination abort
obligation.

While `Active`, exactly one root follows this grammar:

```text
Value := Put_Null | Put_Boolean
       | Begin_Number Put_Number_Fragment* End_Number
       | Begin_String Put_String_Fragment* End_String
       | Begin_Array Value* End_Array
       | Begin_Object
           (Begin_Name Put_Name_Fragment* End_Name Value)*
         End_Object
```

All array bounds are accepted. Empty fragments are legal no-ops that still form
public writer calls; they consume no input or output budget. Name and string
fragments may split UTF-8 at any byte. Number fragments may split at any byte.
The writer retains only bounded lexical carry.

`Finish_Document` is legal only after exactly one balanced root and no active
lexical token. It advances its observational call counter, invokes
`Destination_Commit`, and enters `Completed` only on `Stage_Accepted`. Any
grammar, UTF-8, number, budget,
destination, or commit failure while active latches a primary diagnostic,
invokes `Destination_Abort` exactly once, records an abort cleanup failure only
as secondary, and enters `Failed`.

`Abort_Document` in `Ready` enters `Aborted` without a destination call. In
`Active`, it invokes destination abort exactly once and enters `Aborted`; an
abort cleanup error is primary because no earlier failure exists. In `Failed`
or `Aborted` it is an idempotent no-op preserving diagnostics. In `Completed`
it is a no-op and cannot revoke publication. In `Uninitialized` it is a no-op.

`Reset` is legal only in `Completed`, `Failed`, or `Aborted`. It validates a new
profile and enters `Ready` without beginning a destination transaction. It does
not reset `Budget`.

A document call that violates the call grammar in `Ready` or `Active` returns
`Invalid_Writer_Grammar` at its `JSON_Call_Ordinal` and enters `Failed`. An
active writer aborts its destination exactly once; a ready writer has no
transaction to abort. In contrast, a call rejected solely because the writer is
`Uninitialized` or terminal returns `Invalid_State` without changing state,
staging output, invoking the destination, advancing the semantic call ordinal,
or replacing a terminal diagnostic. The documented idempotent/no-op
`Abort_Document` cases are successful lifecycle operations, not rejected calls.
`Initialize` outside `Uninitialized` and `Reset` outside its eligible terminal
states follow the same nonmutating `Invalid_State` rule.

Successful `Initialize` and successful `Reset` zero JSON's per-operation work
counters. A newly declared uninitialized parser or writer also reports zero
counters. A rejected initialize/reset profile and an illegal reset do not change
the retained counters. JSON retains no duplicate budget total; caller-owned
`Budget` is the authority for accepted charges and is never reset or replenished
by JSON.

## Diagnostics and ordinals

`Clear` sets `Code = No_Error`, every `Has_*` field to `False`, and both
coordinate kinds to `No_Coordinate`. Fields guarded by a false presence flag
are unspecified and must not be read. A non-error operation returns a cleared
diagnostic.

The first operation failure is primary. Later destination-abort or cleanup
failure sets `Has_Secondary` and `Secondary` without replacing the primary. An
explicit abort cleanup failure with no primary uses `Abort_Failed` as primary.
When abort failure is secondary, its coordinate is retained separately in
`Secondary_Coordinate` and `Secondary_Offset`; it never replaces the primary
coordinate.

Profile failures and invalid-state calls have no coordinate. Parser input errors
use `Source_Byte`. Parser event-budget denial without a source byte uses
`JSON_Event_Ordinal`. Destination begin failure uses `Staged_Output_Byte` zero.
Destination write, commit, and abort failures use the next staged-output byte.
Invalid writer token input uses `Writer_Token_Byte`. `Invalid_Writer_Grammar`
uses `JSON_Call_Ordinal`.

Destination outcomes map exactly as follows:

- `Destination_Begin`: `Stage_Capacity_Denied` becomes
  `Destination_Exhausted`; `Stage_Error` becomes `Destination_Failed`. Both use
  staged-output byte zero, enter `Failed`, and create no abort obligation.
- `Destination_Write`: `Stage_Capacity_Denied` becomes
  `Destination_Exhausted`; `Stage_Error` becomes `Destination_Failed`. Both use
  the current staged length (the first octet of the all-or-nothing requested
  span), latch primary, abort once, and enter `Failed`.
- `Destination_Commit`: `Stage_Capacity_Denied` becomes
  `Destination_Exhausted`; `Stage_Error` becomes `Commit_Failed`. Both use the
  current staged length, latch primary, abort once, and enter `Failed`.
- `Destination_Abort`: either nonaccepted outcome becomes `Abort_Failed` at the
  current staged length. It is secondary when a primary already exists and is
  primary for an explicit abort. In all cases the destination contract requires
  the transaction to have ended without publication.

`Writer_Calls` advances on entry to every document call and saturates
independently of the semantic call ordinal. `Destination_Calls` advances
immediately before each actual destination invocation. `Cleanup_Calls` advances
immediately before each parser cleanup or destination-abort invocation.
Saturation uses the nondeniable rule below and never prevents the invocation.

Parser event ordinals count only chunk-invariant non-fragment grammar events and
advance after the relevant event charge succeeds. Before returning an event at
unsigned 64-bit maximum, the parser instead returns `Counter_Exhausted` at that
`JSON_Event_Ordinal`, enters `Failed`, and performs no event charge.

Writer call ordinals start at zero after successful initialize/reset. A document
call in `Ready` or `Active` reserves and advances its ordinal before grammar
validation. If the current ordinal is unsigned 64-bit maximum, the call instead
returns `Counter_Exhausted` at that `JSON_Call_Ordinal`; an active writer aborts
once and enters `Failed`, while a ready writer enters `Failed` without abort.
Calls rejected because the writer is uninitialized or terminal, plus
initialize, reset, queries, and cleanup destination calls, do not advance the
JSON call ordinal.

`Denied_Dimension` is meaningful only when `Has_Denied_Dimension = True`.
Budget denial records the exact dimension. The offset and coordinate follow
the architecture's charge checkpoint and blame rules.

Writer token offsets aggregate every nonempty fragment from zero and do not
depend on fragment bounds or splitting. Name/string UTF-8 failures use these
exact rules:

- an illegal lead octet or unexpected continuation reports that octet;
- a required continuation replaced by another octet reports the replacement;
- an overlong, surrogate, or out-of-range encoding reports its lead octet;
- `End_Name` or `End_String` with an incomplete sequence reports the aggregate
  token length (the position of the missing continuation) as `Invalid_UTF8`.

Number grammar reports the first octet that makes the DFA invalid. This includes
the second integer digit after a strict leading zero and the first non-ASCII or
otherwise disallowed spelling octet. `End_Number` in a nonaccepting state reports
the aggregate token length as `Invalid_Number`; an empty number therefore fails
at zero. Token-offset exhaustion fails before inspecting the next supplied octet
and reports that next offset. The failing call stages no bytes of the rejected
effect and follows the active-writer abort contract.

## Charges and counters

The exact charge order in `docs/architecture.md` is part of this draft contract.
Charge amounts use the count subtype already defined by `Ada.Streams`; JSON does
not invent a separate width or ceiling. The caller-owned hook decides how to
accumulate accepted charges and denies before its own total would overflow.

`Duplicate_Index_Slots` is a single aggregate charge after comparison proves a
name unique and before index mutation: amount one for the first leaf in an
object, and amount two for each later unique name (one leaf plus one internal
node). A duplicate charges zero slots. Physical leaf/internal-node capacity is
checked before this charge. A denied aggregate charge retains neither slot.

`Step_Calls` counts every `Step` attempt, including rejected and empty calls.
`Need_Input_Count` counts returned `Need_Input` outcomes.
`Fragment_Deliveries` counts fragment events. `Writer_Calls` follows the call
entry rule and counts every attempted document call, including calls rejected
in uninitialized or terminal states. `Destination_Calls` counts every actual
destination invocation.
`Cleanup_Calls` counts parser cleanup and destination-abort invocations.

The six transport observations (`Step_Calls`, `Need_Input_Count`,
`Fragment_Deliveries`, `Writer_Calls`, `Destination_Calls`, and
`Cleanup_Calls`) saturate at `Counter_Value'Last` and set
`Transport_Counter_Overflowed`. `Maximum_Live_Depth` uses the same saturation
rule. Saturation never changes a call outcome, parser/writer state, primary or
secondary diagnostic, or mandatory cleanup. `Counters` returns the saturated
values and flag in every state. Parser chunk schedules can vary only these
documented transport counters, their overflow flag, and fragment segmentation;
semantic charges remain equal.
