# Provisional parser corpora

These pinned, data-only corpora drive parser implementation before the public
API is frozen. Run `scripts/verify-corpora.sh` without network access before
using them. The verifier checks every selected fixture, exact selection sets,
license bytes, counts, and aggregate manifest digests.

The expectation files describe the approved strict RFC JSON profile: UTF-8,
Unicode scalar strings, top-level scalars, no BOM or extensions, and rejection
of duplicate decoded object names. They are provisional test expectations, not
specification authority. A mismatch is triaged against the profile and RFC;
upstream labels and differential-oracle agreement never decide correctness.
The expectation tables are checked-in review inputs with pinned digests. The
network importer never derives or overwrites them from upstream filenames.

The corpus runner accepts an explicit schedule. `every-split` reparses every
fixture at every possible single split and is intentionally an expensive
exhaustive campaign. It requires a caller-supplied positive maximum work count:

```sh
scripts/test-corpus-parser.sh every-split MAX-WORK-UNITS
```

The runtime ledger charges one work unit for every `Next` call and every input
octet planned for a parse. Before parsing, the runner computes the minimum
complete-campaign charge: one `Next` call plus the full fixture length for the
monolithic parse and every split parse. It refuses to start when that minimum
exceeds the caller's ceiling. Additional `Next` calls debit the same ceiling,
so a repeated zero-consumption event cannot loop indefinitely. Corpus changes
between estimation and execution are also charged by the runtime ledger. There
is no default ceiling and no silent fixture skipping. `monolith`, `one-byte`,
and `randomized` provide faster development campaigns without weakening that
retained exhaustive action.
The runner compares terminal acceptance or the expected error class. For
malformed inputs, every scheduled result must also reproduce the monolithic
error code and byte offset. Duplicate expectations specifically require
`Duplicate_Name`; a generic parse failure is not accepted. It does not compare
event or fragment sequences.

Corpus files are read into arrays whose lower bound is one. The randomized
campaign varies nonempty chunk lengths but does not inject empty chunks. The
focused core suite separately covers arbitrary Ada array bounds and empty
chunks; `every-split` also feeds an explicit empty nonfinal chunk at split zero.

WPT JavaScript is not vendored or executed. Its three reviewed files are
recorded only as byte-digest evidence for later, separately reviewed extraction
of UTF-8 split and truncation cases.
