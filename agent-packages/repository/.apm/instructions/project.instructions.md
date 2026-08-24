---
description: Preserve Flyology JSON's streaming, resource, profile, and review contracts.
---

# Flyology JSON agent guide

`flyology_json` is an experimental, Ada-first JSON parser and writer. Its core
is incremental, bounded, allocation-free, and independent of Flyology tasking,
Serde, Type IR, Wire, operating-system APIs, and C.

## Before changing anything

- Run `git status --short --branch` and preserve unrelated work.
- Read `docs/architecture.md`, the relevant public specification, its body,
  tests, and maintained runners. Executable code overrides stale prose.
- Use `rg` and `rg --files` for discovery and `apply_patch` for hand edits.
- Keep handwritten Ada to 110 columns and UTF-8. Run GNATformat through the
  owning GPR project after changing Ada.
- Run `gh` outside the sandbox. Repository: `flyology-ada/flyology-json`.
- Keep every commit focused and use the Flyology Problem/Solution format.

## Architecture invariants

- The parser and writer operate on JSON octets and never depend on Serde or
  Type IR. Flyology Wire runtime must not depend on this crate.
- Ada is the implementation language. Do not add C merely for speed. A new or
  materially expanded C boundary requires the inherited Flyology native-C
  admission review, proof that direct Ada is unsuitable, focused ABI tests,
  and confirmation that C owns mechanism rather than JSON policy.
- The bounded core performs no heap allocation. Storage capacities and budgets
  are caller-supplied, explicit, and have no public defaults.
- One operation freezes an explicit, versioned profile before byte zero. Reject
  unsupported versions, unknown flags, and incompatible combinations before
  consuming input or staging output.
- Parser input uses `Ada.Streams.Stream_Element_Array` and consumed counts. Do
  not assume a lower bound of one or retain an input-chunk reference after a
  step returns.
- Parser control remains caller-driven. A step returns one event, `Need_Input`,
  completion, or a terminal status on the caller's stack. A raw fragment is a
  count-based range into the current chunk, never a retained access value.
- Preserve number lexeme octets exactly. Numeric conversion is a separate,
  checked operation and must never silently normalize, round, truncate, or
  accept nonfinite input.
- Decoded text contains only valid UTF-8 scalar sequences under the approved
  initial policy. Preserve raw lexical provenance and exact byte ranges without
  normalizing Unicode or rereading input.
- Duplicate member names compare decoded Unicode scalar sequences without
  normalization. Rejection uses a bounded caller-backed crit-bit index over
  length-prefixed decoded UTF-8 and no quadratic or collision-unsafe fallback.
  Serde alias collisions remain outside this crate.
- Parser events are provisional observations until complete-document
  acceptance. The consumer owns any candidate transaction. JSON owns parser,
  token, duplicate-index, and diagnostic state.
- Writer destinations stage a whole document through
  `Begin`/`Write`/`Commit`/`Abort`. A failed commit does not publish output.
  Do not offer an irreversible prefix sink under the transactional API.
- Malformed input, resource denial, destination exhaustion, and allocation
  failure return statuses with exact offsets. Preserve the primary status
  through nonraising, idempotent cleanup.
- Ordinary output preserves caller member order and exact numeric spelling. It
  never implies canonical JSON. Canonical profiles require separate review.
- Keep allocating conveniences, DOM support, Serde adapters, Type IR adapters,
  corpus tooling, fuzz harnesses, and benchmark harnesses in distinct layers.
- Before freezing public event, profile, reset, transaction, offset, or writer
  declarations, send the concrete specifications to the existing Serde and
  Type IR tasks and resolve their P0/P1/P2 findings.

## Approved initial profile

The approved resolved profile combines `RFC8259_Syntax_V1` with
`Unicode_Scalars_V1`: top-level scalars are accepted; duplicate names, a BOM,
malformed UTF-8, unpaired surrogates, comments, trailing commas, nonstandard
numbers, nonfinite values, and raw control characters are rejected. A consumer
may additionally require an object root. No profile or policy is a default.

The approved ordinary compact writer emits UTF-8 without a BOM or added
whitespace, preserves member order and number lexemes, leaves solidus and valid
non-ASCII unescaped, uses short standard escapes, and uses uppercase hexadecimal
for other escaped controls. It is not canonical.

## Verification and review

- Add exact malformed, truncation, boundary, reset, cleanup, reuse, arbitrary
  array-bound, and transactional-publication cases for every parser or writer
  change.
- Every fixture runs monolithically, at every single split, in one-byte chunks,
  and through deterministic randomized schedules. Small transition fixtures
  additionally run every possible partition.
- Treat corpus labels and differential agreement as evidence, never as the
  specification. Pin and attest every imported corpus revision and license.
- Run the smallest relevant check while iterating, then the maintained complete
  suite required by the changed boundary. Performance changes also require a
  recorded before/after benchmark and hot-loop review.
- Review every architecture decision and every change with P0/P1/P2 findings.
  Fix every P0 and P1. Fix P2 by default; defer it only with explicit authority.
- Before committing, run `git diff --check`, inspect every staged path, rerun
  relevant checks after review fixes, and perform a final independent diff
  review.
- Alire compiler-provider locks stay host-local. Do not commit a non-propagating
  Alire dependency pin anywhere in this repository. The APM lock remains
  committed agent-package provenance. A release must resolve from the Flyology
  Alire index without downstream Git pins.
- Claim GNAT 13, 14, 15, or 16 and macOS or Linux compatibility only from the
  maintained matrix's build, behavior, corpus, and relevant tool evidence.
- Original source, tests, documentation, scripts, proof, and benchmarks are
  dual MIT/Apache-2.0. Do not vendor historic JSON.org JSON_checker fixtures;
  their restrictive license is incompatible with this repository policy.
- The initial version is `0.1.0-dev`. Before tagging or index submission,
  record the reviewed origin, dependencies, compiler/OS evidence, corpus pins,
  tests, benchmarks, and limitations. Use an immutable annotated
  `flyology_json/v<version>` tag and verify index resolution from a clean
  downstream workspace without any Git or path pin.
