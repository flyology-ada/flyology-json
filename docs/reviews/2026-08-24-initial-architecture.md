# Initial architecture review

Date: 2026-08-24

## Rubric

- P0: the architecture cannot safely satisfy the stated contract, creates an
  irreversible publication or legal risk, or must block implementation.
- P1: a correctness, interoperability, boundedness, or public-contract defect.
- P2: an important performance, testing, maintenance, or release-quality issue.

## Review inputs

Three independent read-only reviews covered the core architecture, the Serde
and Type IR API boundary, and corpus, licensing, differential, and fuzz design.
The existing Serde and Type IR tasks then reviewed the proposed consumer
boundary. The repository was empty throughout the review.

## Resolved findings

### P0: irreversible streaming contradicts no partial publication

An ordinary socket or file cannot retract a prefix after a later failure.

Resolution: the writer requires a whole-document transactional destination.
The parser explicitly treats early events as provisional observations and
requires a consumer-owned candidate for atomic application publication.

### P0: visible profile behavior lacked authority

RFC 8259 does not settle duplicate-name policy, BOM policy, or the treatment of
escaped unpaired surrogates as Unicode values.

Resolution: the user approved the exact initial syntax, Unicode, duplicate,
BOM, extension, top-level, and writer policies recorded in the architecture.
There are no public defaults.

### P0: historic JSON_checker licensing is incompatible

The JSON.org test license includes a non-OSI use restriction.

Resolution: do not vendor those fixtures. Evaluate their coverage and create
clean-room RFC-grounded cases.

### P1: Serde requires caller-driven control

A parser-owned visitor would invert control and cannot suspend the existing
Serde pull traversal safely.

Resolution: the stable parser surface is caller-driven `Step`/`Next`. Any
callback is limited to immediate fragment observation.

### P1: JSON and consumer transactions were conflated

JSON cannot withdraw already observed events or own an application builder.

Resolution: JSON owns its parser and writer state. Consumers own unpublished
candidates and commit only after complete-document acceptance. Cleanup
ownership and primary-status precedence are explicit.

### P1: exact input and number provenance was incomplete

Decoded strings alone cannot support a consumer that attests its source bytes,
and eager number conversion loses spelling.

Resolution: events report count-based and absolute raw lexical ranges into the
current caller-retained chunk, carry escaped decoded scalars inline, and
preserve exact number fragments. JSON never normalizes or rereads an earlier
input chunk.

### P1: duplicate detection could become quadratic

A name vector or collision-unsafe hash table violates adversarial work bounds.

Resolution: use bounded caller-backed crit-bit indexing over length-prefixed
decoded UTF-8 with exact comparison and explicit storage failure.

### P1: offset and reset behavior was underspecified

Chunking, Unicode failures, duplicate rejection, EOF, cleanup, and caller-owned
budgets could otherwise produce unstable diagnostics or double charging.

Resolution: the architecture defines zero-based unsigned 64-bit byte offsets,
failure blame rules, retained primary diagnostics, view invalidation, and
non-replenishing reset.

### P1: Type IR canonical policy risked leaking into ordinary output

Type IR has distinct ordering, escaping, framing, projection, and fingerprint
rules.

Resolution: ordinary output is explicitly noncanonical. Canonical output is a
separate future profile that may verify caller ordering but never assumes Type
IR authority.

### P2: exhaustive split language was computationally ambiguous

Every partition of a large input is exponential.

Resolution: every fixture gets every single cut, one-byte chunks, and seeded
random schedules. Small transition fixtures additionally get every partition.

### P2: resource accounting could be double charged

Parser, collector, and Serde work represent different layers.

Resolution: the architecture assigns each charge to one layer and requires
charge-before-mutation behavior.

### P2: convenience allocation could obscure the core contract

Resolution: allocating packages remain separate, convert storage exhaustion to
a status after cleanup, and receive dedicated failure-injection tests.

## Disposition

The user approved the recommended architecture slate. Serde reported no P0 and
accepted the ownership split subject to reviewing concrete declarations. Type
IR reported no P0/P1 objection to the ownership split and requested the same
concrete-specification review. No P0 or P1 remains open at the architecture
level. The P2 findings above are resolved in the design rather than deferred.

No Ada implementation may freeze a public declaration until the concrete
event, profile, reset, offset, transaction, and writer contracts receive the
promised consumer review.
