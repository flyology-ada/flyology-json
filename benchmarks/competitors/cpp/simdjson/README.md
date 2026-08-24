# simdjson 4.6.8 benchmark adapter

The benchmark source is pinned to simdjson 4.6.8 at commit
`17fef66827864c33170996554b7aa0598da080cd`. The authoritative archive entry in
`benchmarks/comparison/sources.lock.tsv` records 6,691,503 bytes and SHA-256
`5b95ee177ab5780f16eb2338ed4c6daa4c3613a9e0b0c0a2500904d9b3b8e88c`.

`acquire.sh` downloads that exact archive into a temporary external cache,
checks its byte count and digest, and materializes only the two upstream license
files and the official `singleheader/simdjson.h` and `simdjson.cpp`
amalgamation. `files.sha256` attests every materialized file, and `verify.sh`
rejects missing, changed, or extra files.

The two upstream license choices are Apache-2.0 and MIT. Their exact evidence
digests are also recorded in `benchmarks/comparison/licenses.lock.tsv`.

The adapter calls `simdjson::dom::parser::parse` with
`realloc_if_needed=false`, so it does not hide an input copy. Callers provide
64 additional readable padding octets as required by this pinned version.
Parser allocation, number conversion, DOM construction, recursive observation,
and per-call cleanup are part of the `parse_dom` timed operation. The parser
and DOM are local to the coarse call and destroyed before it returns.

The exact behavior used for comparisons—including the accepted initial BOM,
the upstream 1,024-level configuration and tested 1,023-container acceptance
ceiling, number conversion, and unsupported lanes—is in `capability.json`.
