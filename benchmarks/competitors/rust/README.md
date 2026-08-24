# Rust parser benchmark adapters

This benchmark-only static library exposes one coarse whole-document C ABI call
for each admitted Rust parser:

- serde_json 1.0.151 at commit de8500740cdcabffb9734f503e4889def823cf10;
- sonic-rs 0.5.8 at commit e339451e37a8f2d3f9b93f155985d31fcbcb115a;
- simd-json 0.18.1 at commit 61d649d13fae83ac6d9f587863696be2741f5b8b.

The exact dependency graph is committed in `Cargo.lock`, whose reviewed
SHA-256 is pinned by `Cargo.lock.sha256`. The 70-package graph includes
target-conditional WASI and wasm packages even though they are not built on
every host.

`license-policy.tsv` is the handwritten review input. For every package it
records the exact manifest expression, the selected permissive `OR` branch,
every license required by the selected `AND` expression, and the evidence used
for that conclusion. It also records license notices for bundled third-party
source where the crate supplies them. `licenses.tsv` is the generated
attestation: it adds each registry package's lock checksum and the SHA-256 of
each exact evidence file. The local adapter package has no registry checksum,
so its source and checksum fields are explicitly `LOCAL`.

Most manifest license fields are SPDX expressions. `halfbrown`, `value-trait`,
and `version_check` retain Cargo's deprecated slash-separated dual-license
spelling. Their exact raw fields and both supplied license files were reviewed;
the policy records the MIT branch without silently rewriting the upstream
metadata.

Run the offline audit with:

    ./audit-licenses.sh

The audit uses `cargo metadata --locked --offline`, requires exact policy
coverage of the complete resolved graph, checks every cached `.crate` archive
against its lock checksum, confirms extracted manifests and evidence match the
archive, validates the reviewed SPDX branch and all `AND` obligations, then
regenerates and compares the attestation. Crate archives and dependency license
texts remain in Cargo's cache; neither is vendored here.

The locked `r-efi 5.3.0` archive has no `LICENSE`-named file. Its normalized
manifest and `README.md` both declare
`MIT OR Apache-2.0 OR LGPL-2.1-or-later`; the README points to `AUTHORS`, which
contains the complete MIT permission grant and disclaimer followed by the
copyright holders and authors. The policy therefore selects MIT, records
`AUTHORS` as the selected-license evidence, and independently records the README
declaration. No dependency in this locked graph lacks evidence for its selected
license branch.

Each call parses a complete document and recursively traverses the resulting
DOM while computing a checksum and item count. The wrapper publishes outputs
only after success, retains no Ada storage, performs no I/O, and contains no
fixture selection or JSON policy. simd-json requires mutable input, so its
coarse function copies the caller's read-only bytes into a private vector. The
copy and its allocation are therefore inside the timed parse_dom operation.
Traversal is recursive. The admitted benchmark fixture matrix is preflighted
and bounded to depth 256; deeper accepted values and allocator exhaustion may
abort the process and are not represented as the ordinary panic status.

Run both tracks with:

    ./test.sh portable
    ./test.sh native

The build requires Rust 1.88 or newer, Cargo, a C compiler, Alire, and the Ada
compiler selected by the benchmark workspace. The shared validator requires
the reviewed Node 24 toolchain and an `npm ci --ignore-scripts` in
`benchmarks/comparison`. Capability declarations are under capabilities/.
