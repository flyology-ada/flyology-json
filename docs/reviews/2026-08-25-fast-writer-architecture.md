# Fast transactional writer architecture review

Date: 2026-08-25

Base commit: `d0aa5a343cc0a206844f5cbccecd6d8fbe3c8cfc`

## Decision

Ordinary writer grammar and fragment calls use one atomic in-call marker and
atomic primary-diagnostic publication rather than whole-call abort deferral.
Transaction boundaries and failure cleanup use narrow controlled transfer
guards. An abnormal escape from a hot call exposes `Interrupted`; the owner
must abort or unwind before reuse. The public wrapper is the sole controlled
cleanup owner. The private engine is noncontrolled and exposes only explicit
cleanup to that wrapper.

This is approved for provisional implementation. Public freeze additionally
requires the evidence and consumer reviews listed in
`docs/architecture/fast-transactional-writer.md`.

## Reviewed artifacts

| Artifact | SHA-256 |
|---|---|
| `docs/architecture.md` | `260b419fcfc18e9726d0625f45e906bf3cf12cfca380fe500050b07163e56514` |
| `docs/architecture/fast-transactional-writer.md` | `63238d73b4b0a3130740179c4065aaecd7abc86a6b7e76ae0916ee53f24265c9` |
| `docs/api-draft/contracts.md` | `f1ef7a7868e6f83b19ccd101ea8836dc6997e92259547d0fb1e5c237fe12d718` |
| `docs/api-draft/flyology_json-writing.ads` | `17a5a97bdec0a61f6b8afe25d1f87919d384bf94449245ae4a18a02af3c89b04` |
| `docs/api-draft/flyology_json-errors.ads` | `f327a6e08f42853b98e7647dedaefbdbcd24ec8029ec82f40f819439d995bc35` |
| `docs/api-draft/flyology_json-profiles.ads` | `e2507a3a17b0df1e27d6274a4e73f2cb2d6d401b2d92c9a906562a0217d6e57d` |
| `docs/api-draft/flyology_json-destinations.ads` | `45cdeca9a9c1a9c5374af3bb2f2b67284f984288a6df156e0f320bc2a5f0c7b8` |

## Findings and resolution

Rubric: P0 is an unsafe or irreversible blocker; P1 is a correctness,
ownership, deterministic-diagnostic, or consumer-contract blocker; P2 is an
important pre-freeze clarity, portability, evidence, or performance issue.

The first independent pass found four P1 and three P2 findings:

- interruption cleanup diagnostics conflicted;
- the `Interrupted` lifecycle was incomplete;
- document-boundary ordinal and marker membership was ambiguous;
- recovery after a raising boundary formal exceeded what its contract could
  support;
- controlled cleanup ownership was not singular;
- abnormal write prefixes were insufficiently bounded; and
- post-interruption query eligibility did not explicitly require a joined
  borrower.

The fix pass retained `Writer_Interrupted`, made abort failure after an unknown
prefix secondary with no coordinate, completed every lifecycle row, defined
begin/finish ordinal behavior, narrowed contract-violation handling to
immediate unwind without an ownership or publication claim, assigned control
to the public wrapper alone, bounded abnormal writes to an in-order input
prefix, and required join before queries.

A second pass found two remaining P1 ambiguities: missing ready/interrupted
document-boundary rows and a general abort-coordinate rule that failed to name
the interrupted-prefix exception. Both were fixed.

Final independent re-review: P0 none, P1 none, P2 none. No additional OCI,
Wire, Serde, or Type IR API-shape incompatibility was found.

## Verification

- `git diff --check`: pass.
- GNAT 16.1.0 `gprbuild -q -P docs/api-draft/api_draft.gpr`: pass.
- public values audit: no default profile, capacity, budget, or canonical
  policy was introduced.
- architecture audit: no C, Serde, Type IR, Wire, OCI model, DOM, accounting,
  or Flyology runtime dependency was introduced.

