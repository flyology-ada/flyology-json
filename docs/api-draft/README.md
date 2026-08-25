# Public API draft

These Ada specifications are reviewed target declarations. Public foundation,
parser, token-collector, and signed/unsigned integer packages with matching
implementations are installed in `src/`. A declaration that is absent from
`src/` remains an architecture artifact until its implementation and consumer
reviews are complete.

The drafts intentionally contain no implementation bodies and no public
capacity, budget, profile, or policy defaults.  The trusted parser and writer
contain no accounting hooks; a separately reviewed opt-in accounted surface
will be added without changing the trusted hot path.

[`contracts.md`](contracts.md) remains normative for draft declarations during
review. Each declaration's applicable contract text moves into its installed
specification before that package is treated as public API.
