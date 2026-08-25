# Public API draft

These Ada specifications are architecture artifacts. The library project does
not compile or install them. They become public source only after independent
Serde and Type IR P0/P1/P2 review and resolution.

The drafts intentionally contain no implementation bodies and no public
capacity, budget, profile, or policy defaults.  The trusted parser and writer
contain no accounting hooks; a separately reviewed opt-in accounted surface
will be added without changing the trusted hot path.

[`contracts.md`](contracts.md) is normative for these declarations during the
review. Its contract text will become installed GNATdoc comments when the
specifications move into `src/`.
