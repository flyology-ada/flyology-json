# Fast transactional writer architecture

Status: approved for provisional implementation; consumer acceptance and
implementation evidence remain public-freeze gates.

This decision replaces whole-call abort deferral in ordinary writer grammar
calls. It retains whole-document staging, commit-only publication, exact JSON
validation, and nonraising ordinary status results. It adds no accounting,
capacity default, callback, C dependency, or canonical-output claim.

## Ownership

One logical owner creates, mutates, completes or aborts, and finalizes a
writer. Its destination outlives the writer and is not independently accessed
while the writer owns a transaction. A borrowed writer call is synchronized,
nonescaping, and joined before the owner resumes use or finalization. The
writer is not a concurrent object.

The destination stages one complete document. `Destination_Commit` is the only
publication point. A failed operation never publishes a partial document.
The owner may query `State` or `Terminal_Diagnostic` after an asynchronous or
borrowed call only after that call's task has joined or its transfer handler is
running in the owner task.

## Static shape

`Flyology_JSON.Writing` is a trusted generic package over one private generic
engine. The public wrapper is the only controlled cleanup owner and validates
and freezes the explicit writer profile. The private engine is noncontrolled;
it owns JSON grammar, offsets, UTF-8 and number state, depth, destination
ownership, diagnostics, and an explicit nonraising cleanup operation invoked
only by the public wrapper.

The initial writer accepts only the explicit `Ordinary_Compact` output policy.
It emits no BOM or added whitespace, preserves caller member order and exact
validated number lexemes, leaves solidus and valid non-ASCII unescaped, uses
short standard escapes, and uses uppercase hexadecimal for other escaped
controls. It is not canonical JSON.

## Streaming grammar calls

The hot streaming grammar calls are object/array begin and end,
name/string/number begin/fragment/end, null, and Boolean emission. They do not
defer task abort across scanning or destination writes. `Begin_Document` and
`Finish_Document` are transaction boundaries governed separately below.

After nonmutating lifecycle checks, each admitted call:

1. copies its candidate call ordinal into private storage;
2. atomically sets an elementary `In_Call` marker as its first effect;
3. reserves the call ordinal and performs grammar, validation, and output;
4. assembles any primary diagnostic completely before atomically setting an
   elementary `Primary_Valid` publication flag; and
5. clears `In_Call` only after all normal state, output, cleanup, and result
   effects are coherent.

An exception, ATC transfer, or task abort that escapes while the marker is set
makes the observed state `Interrupted`. No later grammar call, reset, or commit
is admitted. The caller must call `Abort_Document` or unwind the writer owner
scope.

An interrupted destination write may have staged an unknown in-order prefix of
the supplied `Data`, from zero through `Data'Length` octets. It must remain
unpublished, retain no reference to the supplied array, and leave one coherent
transaction that `Destination_Abort` can end. Because no normal `Written`
result exists, the writer claims no token or staged-output coordinate for the
interruption.

There is no controlled guard, protected operation, task-abort runtime call,
callback, dispatch, or per-octet destination call in a fragment scanner.

## Ownership and publication boundaries

Initialization, reset, destination begin, commit, explicit abort, failure
cleanup, and finalization use narrow language-defined abort-deferred regions.
A procedure-local `Ada.Finalization.Limited_Controlled` transfer guard is
configured completely before one final atomic `Armed` store. Its
language-invoked `Finalize` performs the destination operation and adjacent
ownership, state, diagnostic, and result transition. The finalizer is never
called explicitly.

The guarded transitions make these pairs indivisible with respect to task
abort:

- successful begin and acquisition of transaction ownership;
- successful commit publication, ownership release, and `Completed`;
- destination abort, ownership release, exactly-once bookkeeping, and terminal
  state; and
- complete profile validation/freeze or reset state transition.

Every lifecycle-admitted `Begin_Document` and `Finish_Document` reserves one
JSON call ordinal inside its guarded boundary before destination effects.
`Begin_Document` in `Ready` may begin the transaction; another
`Begin_Document` in `Active` fails grammar at that ordinal and aborts the owned
transaction. `Finish_Document` in `Active` diagnoses an incomplete grammar at
its ordinal or commits a balanced document. Neither boundary uses the hot
`In_Call` marker. Calls rejected solely for any other lifecycle state reserve
no ordinal.

The guard finalizer catches every exception so finalization itself never
replaces an exception, ATC transfer, or task abort already unwinding the owner.

## Contract-violating destination exceptions

Every destination formal is required to be synchronous, finite, nonraising,
nonreentrant, nonretaining, and free of writer-alias mutation. Normal statuses
are the only portable ownership and publication report.

If `Destination_Begin`, `Destination_Commit`, or `Destination_Abort` raises in
violation of that generic contract during an otherwise normal call, the
transfer guard saves the exception occurrence and seals ordinary continuation.
After the guard has left scope, the public operation re-raises that occurrence.
It does not return a false `Begin_Failed`, `Commit_Failed`, or `Abort_Failed`
status and makes no ownership or publication claim. The caller must immediately
unwind the writer owner scope without a query, abort, reset, or any other reuse.
Controlled finalization is nonraising and best effort, but cannot restore a
contract the destination violated.

During task-abort or exception unwinding, controlled writer finalization remains
nonraising and best effort. It never invents an ordinary status for a raising
destination formal.

## Mandatory abort-or-unwind rule

An atomic marker cannot make asynchronous transfer atomic with the caller's
observation of procedure return. A transfer can win before the marker is set or
after it is cleared but before the caller observes return.

Therefore a handler or ATC alternative that knows asynchronous transfer won
while evaluating actuals for, invoking, or returning from a mutating writer
call must do exactly one of these before further writer use:

1. call `Abort_Document`, then optionally reset after reaching a terminal
   state; or
2. leave the writer owner scope so controlled finalization performs cleanup.

It must not retry the uncertain call, issue another grammar call, reset, or
call `Finish_Document`. This rule applies even if the observed state is
`Ready`, `Active`, `Failed`, or `Completed`. A successful commit may publish
before a pending abort is delivered; publication is not retracted and
`Completed` remains authoritative.

## Lifecycle

| Call and state | Result |
| --- | --- |
| Initialize in Uninitialized | Valid explicit profile enters Ready; invalid profile enters Failed before destination begin. |
| Initialize elsewhere | Nonmutating Invalid_State; retained primary wins. |
| Begin_Document in Ready | Successful begin enters Active and owns one unpublished transaction; failed begin enters Failed without ownership. |
| Begin_Document in Active | Admitted grammar failure, abort once, then Failed. |
| Begin_Document in Interrupted | Zero-effect Invalid_State with no ordinal; retain the interruption primary. |
| Finish_Document in Ready | Reserve an ordinal, fail grammar, then Failed without a destination call. |
| Grammar in Ready | Admitted grammar failure, no destination transaction, then Failed. |
| Grammar in Active | Success remains Active; ordinary failure aborts once and enters Failed; abnormal escape exposes Interrupted. |
| Grammar in Interrupted | Invalid_State with no effects and retained primary. |
| Finish_Document in balanced Active | Successful commit enters Completed; validation or commit failure aborts once and enters Failed. |
| Finish_Document in Interrupted | Zero-effect Invalid_State with no ordinal; retain the interruption primary. |
| Abort_Document in Ready | Clean Aborted without a destination call. |
| Abort_Document in Active | Abort owned transaction exactly once, then Aborted. |
| Abort_Document in Interrupted | Abort owned transaction exactly once, clear marker, retain interruption primary, then Aborted. |
| Abort_Document in Failed or Aborted | Idempotent no-op retaining terminal diagnostic. |
| Abort_Document in Uninitialized or Completed | Nonmutating no-op; completed publication is not retracted. |
| Reset in Completed, Failed, or Aborted | Valid profile starts fresh Ready; invalid profile enters Failed before destination begin. |
| Reset in Interrupted | Invalid_State; explicit abort or unwind is required first. |
| Finalization with ownership | Best-effort abort at most once; never publish or propagate. |

Every lifecycle rejection stages no output, reserves no ordinal, and cannot
replace a retained primary. `Has_Applied_Profile` stays true through the
operation after successful initialization. `Terminal_Diagnostic` is eligible
in `Interrupted`, `Failed`, and `Aborted`.

## Diagnostics

- malformed text and number input use aggregate zero-based
  `Writer_Token_Byte`;
- grammar and depth failure use zero-based `JSON_Call_Ordinal`;
- destination exhaustion uses the first unaccepted `Staged_Output_Byte`;
- destination failure uses the staged offset before the failed write;
- commit and ordinary abort failure use the next staged offset;
- offset exhaustion uses the first denied representable coordinate; and
- interruption without an established primary uses `Writer_Interrupted` at
  the interrupted `JSON_Call_Ordinal`.

An established atomic primary always wins. Abort failure after an interrupted
write is secondary with `No_Coordinate`, because the staged prefix is unknown.
An interruption without an established primary synthesizes and retains
`Writer_Interrupted` at the interrupted call ordinal. Successful abort
preserves it. A clean explicit abort is cleared only when no interruption or
earlier primary exists.

## Required evidence before public freeze

- deterministic injection at every marker, write-prefix, diagnostic
  publication, boundary transfer, and return-edge window;
- caught exception, ATC, task abort, joined borrower, explicit abort,
  finalization, commit, abort-failure, and reset cases;
- exact destination-capacity and malformed-status tuples with no publication
  and exactly-once cleanup;
- GNAT 13 through 16 on macOS and Linux, including atomic code shape and
  pending-abort delivery after controlled finalization;
- installed-public assembly proving atomic marker accesses and no hot-path
  controlled finalization, abort runtime, dispatch, or per-byte writes;
- quiet paired writer benchmarks for one-byte through large fragments; and
- Wire, Serde, Type IR, and OCI review of `Interrupted`, abort-or-unwind, the
  interrupted-write destination obligation, and commit-before-abort delivery.
