# Cross-implementation benchmark contract

This directory defines fair, reproducible comparisons between Flyology JSON
and independently maintained JSON implementations. It is benchmark-only: no
source, adapter, build tool, or native library here is a dependency of the
production Ada crate.

The exact contract is the combination of this document,
[`capability.schema.json`](capability.schema.json),
[`result.schema.json`](result.schema.json), [`sources.lock.tsv`](sources.lock.tsv),
[`licenses.lock.tsv`](licenses.lock.tsv), and
[`skip.schema.json`](skip.schema.json), and [`ci-protocol.md`](ci-protocol.md),
the strict validator sources, exact Node/npm declaration, npm lock, and tooling
license lock, together with the parent benchmark sampling policy. A retained
result records
the SHA-256 of every contract file and the harness commit. Changing a field,
lane, source, compiler mode, inclusion rule, or measurement rule changes the
contract identity; old and new results must not be pooled.

Capability, result, and skip records are validated with the exact Node
24.19.0 runtime and dependencies pinned in `package-lock.json`. Run
`npm ci --ignore-scripts`, `npm test`, `npm run verify:tooling`, and
`npm run validate:capabilities` from this directory. The validator rejects
malformed UTF-8, a BOM, duplicate decoded object names, unpaired surrogates,
unsupported numeric-schema constraints, dangling capability references, and
incomplete lane declarations before applying the Draft 2020-12 schema.
`verify-tooling.sh` and the test sources are verification evidence rather than
result-contract inputs; the accepted validator code, toolchain declaration,
package manifest/lock, and tooling-license lock are explicit record digests.

## Independent lanes

Every sample executes exactly one lane. An implementation is omitted from a
lane it cannot implement honestly; an adapter must not silently add the missing
operation.

| Lane | Timed operation | Required observable result |
| --- | --- | --- |
| `parse_validate` | Validate one complete input through the implementation's fastest complete-document API. | Acceptance plus a checksum that depends on the terminal outcome. |
| `parse_events` | Parse and visit every structural and scalar token without constructing a DOM. | Acceptance plus event, scalar, member-name, and exact input-byte counters. |
| `parse_incremental` | Perform the same complete visit while accepting the declared caller chunk schedule without concatenating chunks in the adapter. | The `parse_events` observables plus feed/step counters. |
| `parse_dom` | Parse one complete input and construct the implementation's ordinary owned tree/value representation. | Acceptance plus a recursive value checksum performed inside the timed operation. |
| `write_stream` | Emit the fixture's preconstructed logical event/value stream through a streaming writer, without first constructing a DOM. | Exact output bytes and their checksum. |
| `write_dom` | Serialize a preconstructed ordinary DOM/value representation. | Exact output bytes and their checksum. |
| `parse_write` | Parse the input and emit semantically equivalent compact JSON using the implementation's natural parse and write APIs. | Acceptance, output byte count, and output checksum. |

`parse_validate` is not interchangeable with `parse_events`: a library may
validate without materializing strings, numbers, or events. `parse_dom` and
`write_dom` expose allocation and conversion costs that the streaming lanes do
not. `parse_incremental` is available only for a genuine incremental API; a
one-shot parser fed an adapter-concatenated buffer is reported in a separate
copy experiment and never in this lane.

The timed region excludes fixture construction, file I/O, dynamic loading,
adapter initialization that is reusable across operations, and output checking
after the required checksum has made work observable. It includes all work
needed for the named operation: parsing, validation, traversal or DOM
construction, documented mandatory input mutation, writer escaping, output
growth, and any per-operation cleanup. A required copy, padding fill, UTF-8
precheck, or conversion is included unless the same prepared representation is
an ordinary reusable input accepted by every compared implementation in that
lane. Both the setup and timed byte counts remain explicit in every result.

## Semantic comparability

Every result names a complete explicit profile from its capability record, and
the lane capability lists the exact profile and output-policy identities it
supports. Implementation, profile, output-policy, and lane identifiers are
unique within one capability record.
The profile discloses UTF-8 and surrogate behavior, root scalars, BOM,
duplicates, comments, trailing commas, controls, nonstandard/nonfinite
numbers, number conversion, maximum depth, and other limits. No profile is a
default.

Primary Flyology comparisons use valid RFC JSON fixtures accepted by every
participant. A result may be compared only when the lane, fixture SHA-256,
chunk schedule, profile-relevant behavior, track, timed-work inclusions, and
output policy match. Profile disagreement fixtures are correctness evidence,
not throughput samples. Differential agreement is never the specification.

The Flyology `parse_events` adapter visits private compact event descriptors
in caller storage. Raw text remains in the current input and is identified by
an exact range; the adapter does not reconstruct the larger convenience
`Event` record in the timed region. RapidJSON SAX instead invokes one callback
for each complete decoded name, string, or number. Both satisfy the event-lane
observables, but this transport and granularity difference is part of result
interpretation rather than a claim of identical work.

For writers, fixtures supply one immutable logical value/event sequence.
Ordinary compact output preserves member order, contains no added whitespace
or BOM, and does not claim canonicality. Exact byte equality is required only
among implementations configured for the same escaping and number-spelling
policy. Otherwise the harness validates the output and records the difference
under a distinct output policy; unlike policies are not ranked together.

The maintained preconstructed-DOM writer comparison uses the same
`large_raw_string` and `nested_structures` output bytes for yyjson, RapidJSON,
serde_json, and sonic-rs. DOM construction is outside timing. Each timed call
includes the implementation's ordinary compact serialization, output-buffer
allocation and cleanup, and a full-output checksum. Exact byte equality is a
mandatory preflight, and these results remain separate from Flyology's
`write_stream` lane.

## Build tracks

Each admitted implementation is built separately in both tracks when the
toolchain supports them:

- `portable`: release optimization without `native`, host-specific ISA, or
  link-time CPU specialization flags. Runtime ISA dispatch supplied by the
  unmodified library is allowed and disclosed.
- `native`: the implementation's documented release configuration plus the
  toolchain's host-CPU optimization flag. The exact compiler, linker, target,
  enabled ISA features, link-time optimization, panic/exception mode, and all
  flags are recorded.

Portable and native results are separate populations. Absence of a supported
track is reported as a capability limitation, never replaced by the other
track. Cross-language builds use equivalent release/check settings as far as
their toolchains allow, with differences disclosed rather than normalized by
an undocumented adapter.

## Native boundaries

Fixed-signature stable C APIs use direct Ada `Import (C, ...)`. yyjson is the
initial direct-C comparison; its document-free operation is header-inline, so
that one operation uses a necessary fixed-signature C shim. Direct Ada APIs are
used for `json` (JSON-Ada) and GNATCOLL.JSON.

RapidJSON and simdjson expose essential benchmark operations through C++ APIs,
so each may use one coarse `extern "C"` translation unit. Rust crates may use
one coarse `staticlib` boundary. Such shims own only ABI translation and an
observable checksum; JSON policy, fixture selection, retries, measurement,
classification, and result reporting remain in Ada. Each exported function
must have fixed-width/nullability documentation and ABI tests. No shim retains
Ada storage after returning, calls back into Ada, performs hidden I/O, or
silently copies input. Shims and exact generated symbols are hashed in results.

## Copying, allocation, mutation, and padding

A capability record states whether the implementation reads or mutates input,
the exact required readable and writable padding, whether input preparation is
reusable, and where copies occur. A result records setup and timed input-copy
octets, padding octets written, output-copy octets, allocations, allocated
bytes, and peak retained memory. An unavailable counter is represented as
`null` with a reason; it is never reported as zero.

Reported zero allocations requires either a language/runtime allocator hook
covering the timed thread and all called libraries or an allocation-free
contract for the exact API. Process RSS is supplemental and cannot establish
per-operation allocation. A mutating parser receives a private buffer; the
copy is timed unless the named lane explicitly compares reusable prepared
input. simdjson padding is allocated and initialized outside or inside timing
exactly as the result declares. Each lane also records its checksum method and
the quantity of data incorporated while timed. Unlike observability work is a
comparison limitation rather than invisible overhead.

## Isolated-host protocol

Formal retained comparisons follow the existing `flyology_bench` sampling
policy documented in the parent README and additionally:

1. Use a clean checkout and verified source archives. Record the source-lock,
   license-lock, schema, adapter, fixture, executable, and Cargo lock digests.
2. Use a dedicated, quiescent host on external power. Record CPU topology,
   memory, OS/build, thermal and power mode, frequency policy, affinity support,
   and unavailable controls. Warm the host before collection.
3. Build every participant before measurement. Do not compile, download,
   extract, or regenerate fixtures during a timed campaign.
4. Interleave implementations in recorded seeded block order for each exact
   lane/fixture/chunk/track tuple. Retain all raw samples and process rounds;
   do not publish only the fastest run.
5. Run correctness preflight and output verification before timing. Re-run the
   complete Flyology parser/writer suite after a performance change.
6. Report the per-round distributions and the declared aggregate statistic.
   Preserve outliers; document environmental invalidation rather than deleting
   samples post hoc. Do not combine results across machines or contract hashes.

A laptop run without affinity, thermal, or interference controls is a
directional experiment and must say so. It cannot be promoted to an isolated
formal baseline solely because it has many samples.

## Approved benchmark-only sources

The initial set is yyjson 0.12.0, simdjson 4.6.8, RapidJSON at the exact
approved commit, serde_json 1.0.151, sonic-rs 0.5.8, simd-json 0.18.1,
JSON-Ada (`json`) 6.0.0, and GNATCOLL.JSON from GNATCOLL 26.0.0. Exact commits,
archive bytes, SHA-256 values, licenses, evidence-file hashes, URLs, and source
admission notes are in the lock manifests.

RapidJSON's source archive includes historic `bin/jsonchecker/` material under
the non-free JSON license. The archive may exist only in an external verified
download cache. Acquisition and adapter builds must select the implementation
headers and applicable license notices without extracting, compiling,
vendoring, copying, or using `bin/jsonchecker/` as test data. The repository's
own corpus policy remains unchanged.

Rust adapters must commit a `Cargo.lock` and pin these three direct crate
versions exactly. Every transitive package and license must pass review before
the first Rust result is admitted. A top-level crate checksum does not attest
its transitive graph.
