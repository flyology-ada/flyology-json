# Benchmark CI review

Date: 2026-08-24

## Decision

Pull requests and pushes build and execute both `portable` and `native`
competitor adapter tracks on `macos-15` and `ubuntu-24.04`. The maintained
entry point installs the exact npm graph, verifies every source and license
lock, and runs the yyjson, C++, Rust, C ABI, Ada ABI, symbol, ownership,
strictness, capability, linked-driver, and exact 63-population preflight checks.

The scheduled workflow runs at 05:37 UTC each Sunday and can also be started
manually. Each OS/track population is a separate job. The Flyology parser GPR
consumes the same explicit track as its competitors; the native lane adds
`-mcpu=native` on arm64/aarch64 and `-march=native` on x86_64/amd64. Other
native architectures fail closed. A native result is therefore never an
accidentally relabeled portable executable.

GitHub-hosted runners do not satisfy the controlled-host protocol. Every
scheduled artifact is unconditionally classified as `directional`. It retains
the 40 Flyology parser distribution summaries, the 63 admitted comparative
distribution summaries, a derived throughput TSV, the declared skip, complete
host and toolchain output, all six capability records, every contract input,
the exact fixtures, harness sources and GPR projects, source and license locks,
Cargo and generated Alire locks, both measured executables, the Rust static
library, verbose parser/comparison/competitor build logs, and an artifact-wide
SHA-256 manifest. A failed benchmark step preserves its combined log and
regenerates the manifest before returning the original failure status.

The comparative driver times the same immutable fixture bytes for every
implementation. It retains the contract's separate `parse_events`,
`parse_validate`, and `parse_dom` identities because the admitted operations do
different work. The summary is therefore evidence for performance direction
and optimization priorities, not a cross-lane leaderboard or a formal result
record. `flyology_bench` currently emits distribution statistics rather than
the contract schema's per-sample array.

## Toolchain and action identities

- Alire 2.1.1 and selected providers GNAT 16.1.0 and GPRbuild 26.0.1;
- Node 24.19.0 and npm 11.17.0;
- Rust 1.97.1;
- `actions/checkout` v6.0.2 at
  `de0fac2e4500dabe0009e67214ff5f5447ce83dd`;
- `alire-project/setup-alire` v6.0.0 at
  `fc4c8ce471aa30b3af0d39ce15add1ee9eaf28f2`;
- `actions/setup-node` v6.5.0 at
  `249970729cb0ef3589644e2896645e5dc5ba9c38`; and
- `actions/upload-artifact` v4.6.2 at
  `ea165f8d65b6e75b540449e92b4886f43607fa02`.

The workflow's four direct action references use immutable commit identities,
not mutable tags. This attests only those direct references: the pinned
`setup-alire` composite currently invokes nested actions by mutable tags, so
the workflow does not claim a transitively immutable action graph.

## Evidence

The earlier local result bundles are superseded: they predate RapidJSON Reader
reuse, the exact 40-population parser validator, and the complete provenance
manifest. Fresh portable and native evidence is collected only after the
reviewed harness is committed, so the recorded commit identifies the measured
code without relying on a path-only dirty-worktree inventory.

## Findings

The final P0/P1/P2 findings and fresh measurements are recorded after the
committed harness runs complete.
