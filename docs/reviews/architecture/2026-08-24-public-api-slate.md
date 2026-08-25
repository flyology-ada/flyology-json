# Public parser, writer, token, and number architecture slate

## Status

This is the internally reviewed implementation slate for `0.1.0-dev`. It is
not yet a frozen public API: the required Serde and Type IR task delivery and
acknowledged P0/P1/P2 re-review remain release gates. Attempts to send the
working-tree specs through the Codex task service stalled without an
acknowledgment, so no consumer review is claimed.

## User authority

The user approved the recommended initial architecture, then explicitly
required optional/near-zero-cost accounting for trusted inputs, rejected `_V1`
identifiers, authorized strict duplicate rejection and preserve-unchecked
names, required a public batched parser path, bounded token collection, checked
signed/unsigned/binary64 conversion and deterministic rendering, and directed
implementation and `0.1.0-dev` publication. The numeric version value `1`
retains the approved initial profile identity while removing the rejected name
suffix; it is a profile aggregate value, not a public constant or default.

## Decisions

- The trusted parser/writer have no budget field, hook, counter, nullable
  access, or accounting branch. Accounted packages are separate future static
  shapes with their own reviewed cost-model identity.
- Parser duplicate behavior is an explicit generic formal with no default:
  `Reject_Duplicates` or `Preserve_Unchecked`.
- Parser events are compact private values. `Step` and caller-storage `Drain`
  share the same grammar and fragment contract; no layout or size is public.
- Each parser generic instantiation owns its event type. This avoids exposing
  compact representation or coupling a trusted hot path to a common boxed
  event. Serde and Type IR each consume one selected mode; any shared adapter
  must itself be generic over that instance. Consumer acceptance is pending.
- Raw fragments are count-based borrows from the exact returning input window.
  Nonraising resolution validates origin and length and clears the slice on a
  wrong window.
- The writer destination is whole-document transactional and accepts bulk
  longest prefixes, preserving throughput and exact capacity coordinates.
- The token collector binds arbitrary-bound caller storage and publishes only
  on completion.
- Integer parsing/rendering is exact and checked. Unsigned parsing rejects all
  negative spellings, including `-0`.
- Binary64 is nearest-even, checked for underflow/overflow, preserves exact
  negative zero, and uses a fully ordered shortest-round-trip spelling rule.
- `Ordinary_Compact` remains explicitly noncanonical.

## Review history

Three independent read-only passes reviewed the architecture, parser/event
transport, and writer transaction. Initial findings included mandatory
accounting, `_V1` names, materialized events, missing Drain, contradictory
destination booleans, incomplete lifecycle/offset rules, raw-window safety,
fragment/source ambiguity, incomplete collector publication, imprecise Unicode
blame, finality retraction, and nondeterministic binary64 ties.

All declaration P0/P1/P2 findings were fixed in the retained slate. The only
remaining release-level implementation finding is evidence that
`Preserve_Unchecked` removes duplicate storage/index work, accepts zero name
capacities, and cannot produce duplicate/name-storage failures. That requires
behavior, parity, performance, and assembly evidence before installation.

## Exact reviewed artifacts

- `flyology_json-destinations.ads`:
  `45cdeca9a9c1a9c5374af3bb2f2b67284f984288a6df156e0f320bc2a5f0c7b8`
- `flyology_json-errors.ads`:
  `236ef55767035b3bf50940c34d59cc4efb80a8cc3185c79f196b64803efd02cf`
- `flyology_json-numbers-binary64.ads`:
  `619d84bb11bc9d7f70a936822afcc9df1cb83885b1f6883ab67f3d045bcfb29f`
- `flyology_json-numbers-signed_integers.ads`:
  `880a6dc6d17e9a09b6ee1265e622a805daaa1cf83ec46d0435597aeb5c9aaa7d`
- `flyology_json-numbers-unsigned_integers.ads`:
  `4a675977a297f34883507b3d951cd992a4c6540f12d0efe4be27de4a040ef78d`
- `flyology_json-numbers.ads`:
  `eff2743bf10ff14b46f54c69711e1e582e51b9fb9b446131849d77aac11826ef`
- `flyology_json-parsing.ads`:
  `aa356f625ac5345d2bed71bcd5db7ce1482c17912c30d05dc4e6e46f76077b0c`
- `flyology_json-profiles.ads`:
  `e2507a3a17b0df1e27d6274a4e73f2cb2d6d401b2d92c9a906562a0217d6e57d`
- `flyology_json-tokens.ads`:
  `c914af667f766580d8d4654f8cbc87d47d2410b174e765658d8dc387363d01a4`
- `flyology_json-writing.ads`:
  `c1e17f82adc0b441a68b3eb8329c506c52a8c876d63770e7c08e2fb8d08b76da`
- `contracts.md`:
  `677b2d0853a836b537f6b004910ae556d2c225e780d6d533ecf36bbec5069aef`
- `architecture.md`:
  `62357e0ada6265f59ca35ecdf75cbcbe8c429218ac936ff99b6762b778e9115e`

The declarations compile with GNAT FSF 16.1.0 through
`docs/api-draft/api_draft.gpr`; `git diff --check` and the handwritten Ada
110-column scan pass. GNATformat was unavailable in the selected toolchain, so
no formatting success is claimed.

## Findings

- P0: none.
- P1: consumer-task review delivery and static preserve implementation evidence
  remain release blockers; they do not invalidate this internal implementation
  slate.
- P2: none in the declaration/prose review. Generic-instantiation-specific
  event types are an explicit performance/encapsulation decision awaiting
  consumer confirmation rather than an undisclosed deferral.
