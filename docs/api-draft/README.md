# Superseded public API drafts

These Ada specifications preserve historical architecture-review snapshots.
They are not an installed API, are not maintained as mirrors, and may differ
from the current public declarations. Consumers must use the specifications in
`src/` as the sole API authority. A declaration present only in this directory
is an architecture artifact, not an available or promised interface.

The drafts intentionally contain no implementation bodies and no public
capacity, budget, profile, or policy defaults.  The trusted parser and writer
contain no accounting hooks; a separately reviewed opt-in accounted surface
will be added without changing the trusted hot path.

[`contracts.md`](contracts.md) records the contracts evaluated during those
reviews. Applicable contract text moved into an installed specification before
that package became public API; this historical copy is not normative for the
installed crate.
