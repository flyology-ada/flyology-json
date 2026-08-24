# RapidJSON benchmark adapter

The benchmark source is pinned to commit
`24b5e7a8b27f42fa16b96fc70aade9106cf7102f`. The authoritative archive entry
in `benchmarks/comparison/sources.lock.tsv` records 1,116,703 bytes and SHA-256
`2d2601a82d2d3b7e143a3c8d43ef616671391034bc46891a9816b79cf2d3e7a8`.

The upstream archive has mixed licensing because its historic
`bin/jsonchecker/` directory uses the non-free JSON license. `acquire.sh`
downloads the full archive only into a temporary external cache so its exact
digest can be checked, then extracts only `include/` and `license.txt`.
`bin/`, including `bin/jsonchecker/`, is never materialized, compiled, copied,
or used as test data. `verify.sh` rejects any materialized `bin/` directory,
any extra file, and every digest mismatch.

The admitted headers are MIT except `include/rapidjson/msinttypes/`, whose
notice is BSD-3-Clause. The exact combined notice digest is recorded in
`benchmarks/comparison/licenses.lock.tsv`; `files.sha256` attests all 38
headers and the notice.

The adapter invokes `rapidjson::Document::Parse` with
`kParseValidateEncodingFlag`, then recursively visits the owned DOM. Input is
read-only and retained only for the duration of the call. DOM allocation,
string copying, number conversion, recursive observation, and cleanup are part
of the `parse_dom` timed operation.

The `parse_events` lane invokes `rapidjson::Reader::Parse` with
`kParseValidateEncodingFlag | kParseNumbersAsStringsFlag`. Its SAX handler
observes every structural token, member name, and scalar without constructing a
DOM. Number callbacks receive the exact lexical span; decoded names and strings
are callback-scoped. One Reader is reused per calling thread, so the maintained
preflight grows its internal decoded-token stack before measurement. This lane
still requires one complete contiguous input and preserves duplicate names
rather than rejecting them.

The exact behavior used for comparisons—including the DOM lane's accepted BOM,
the event lane's rejected BOM, UTF-8 validation, duplicate preservation, number
handling, and unsupported lanes—is in `capability.json`.
