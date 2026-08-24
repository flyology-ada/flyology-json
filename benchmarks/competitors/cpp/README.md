# C++ benchmark adapters

This directory contains benchmark-only coarse C++ boundaries for pinned
simdjson and RapidJSON. Nothing here is linked into the production
`flyology_json` crate. Both adapters expose only one complete-document DOM
parse-and-traverse call, use the same fixed-width observation record, retain no
input, perform no I/O, and publish counters only after successful parsing and
traversal.

JSON behavior comes from each pinned library API. The shims do not add
duplicate rejection, BOM rejection, number normalization, retries, fixture
selection, timing, or result classification. The checked-in capability records
disclose the resulting behavior and support only the `parse_dom` lane.

## Maintained entry point

Run the portable track with the benchmark contract's reviewed Node 24.19.0 on
`PATH`:

```sh
./test.sh
```

When that executable is not the default `node`, set
`FLYOLOGY_JSON_BENCH_NODE` to its path.

Run the host-specific build separately:

```sh
FLYOLOGY_JSON_BENCH_TUNING=native ./test.sh
```

On arm64/aarch64, the native track adds `-mcpu=native`; other hosts add
`-march=native`. The portable track adds neither. simdjson's unmodified runtime
ISA dispatch remains enabled in both tracks.

`test.sh` verifies source and license attestations, validates both capability
records against `comparison/capability.schema.json`, builds the Ada/C++
wrappers, runs arbitrary-bound and behavior tests, checks exported symbols, and
runs a C ABI/ownership smoke test. Materialized upstream files and build output
are ignored inputs and never vendored.

The C ABI is intentionally coarse because both admitted operations are C++
APIs. The header documents pointer lifetime, nullability, padding, aliasing, and
publication. All fields and scalar arguments crossing the boundary are fixed
width. JSON policy and benchmark orchestration remain outside the shims.

See the per-library README files for exact archive, file, and licensing
attestations.
