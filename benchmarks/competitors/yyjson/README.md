# yyjson benchmark adapter

This benchmark-only adapter pins yyjson 0.12.0 at commit
`8b4a38dc994a110abaec8a400615567bd996105f`. It is not linked into the
`flyology_json` library and contributes no C dependency to the production
parser.

The adapter calls the exported, fixed-signature `yyjson_read_opts` symbol
directly from Ada. yyjson exposes document destruction only as a header-inline
operation, so `src/flyology_json_bench_yyjson_free.c` is the one necessary
runtime shim. JSON policy, error classification, ownership, and checksum
construction remain in Ada.

The lane performs a complete allocating DOM parse with yyjson's zero read
flags. This includes yyjson's number conversion and is therefore not presented
as equivalent work to Flyology_JSON's allocation-free event parser. It does
not offer genuine incremental input: callers must materialize a complete
contiguous document. The returned checksum includes yyjson's bytes-read and
value-count fields so the parsed result remains observable.

## Materialize and test

```sh
./test.sh
```

`test.sh` is the maintained setup/build/smoke entrypoint for local and CI
runs. [`capability.json`](capability.json) conforms to the shared comparison
contract. `capabilities.sh` emits that exact checked-in document rather than
maintaining a second capability description.

The GPR scenario variable `FLYOLOGY_JSON_BENCH_TRACK` selects `portable` or
`native` and places objects and executables in distinct track directories.
Portable release compilation uses `-O3 -gnatn -gnatp` for Ada and
`-O3 -DNDEBUG` for C. Native compilation adds `-mcpu=native` on arm64/aarch64
or `-march=native` on other maintained CI hosts. `test.sh` builds and runs both
tracks, but its success is build and ABI evidence, not timing evidence. Formal
timing still follows the shared isolated-host protocol.

`acquire.sh` first runs the shared `scripts/verify-benchmark-sources.sh`
source-and-license verifier against `benchmarks/comparison/sources.lock.tsv`.
Only after the exact yyjson archive passes its locked byte-count, SHA-256, and
license checks does the adapter extract `LICENSE`, `src/yyjson.c`, and
`src/yyjson.h`. It rejects selected-file digest mismatches as a second check.
The materialized `upstream/` directory is ignored build input. Formal builds
must preserve this verifier-before-materializer ordering and use the same
`FLYOLOGY_JSON_BENCH_SOURCE_CACHE` for both steps. The attested files are:

| Path | SHA-256 |
|---|---|
| `LICENSE` | `45e384d3d52c73cba3a64d6e6c25d47cd738cd8a55c30629e3201046eda62947` |
| `src/yyjson.c` | `ac2e9bbb2e2d9149d90878d40506a1d624fa0b33c979a11b61075c54782c6d6a` |
| `src/yyjson.h` | `175867c5493a5df648cec566717fa1c29aa2f6096f5f0cf1efad0b65e1f6d7b3` |

The upstream `LICENSE` is the MIT license. The adapter and tests are
MIT OR Apache-2.0 like the rest of this repository; yyjson retains its own
license and copyright notice in the materialized source.
