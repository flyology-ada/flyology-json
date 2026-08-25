# Public API draft

These Ada specifications are the reviewed target declarations. Public
foundation packages are now being moved into `src/`; parser, writer, unsigned,
and binary64 declarations remain architecture artifacts until their matching
implementations and consumer reviews are complete.

The drafts intentionally contain no implementation bodies and no public
capacity, budget, profile, or policy defaults.  The trusted parser and writer
contain no accounting hooks; a separately reviewed opt-in accounted surface
will be added without changing the trusted hot path.

[`contracts.md`](contracts.md) remains normative for draft declarations during
review. Each declaration's applicable contract text moves into its installed
specification before that package is treated as public API.
