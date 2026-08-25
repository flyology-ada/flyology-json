# yyjson benchmark adapter

This benchmark-only adapter pins yyjson 0.12.0 at commit
`8b4a38dc994a110abaec8a400615567bd996105f`. It is not linked into the
`flyology_json` library and contributes no C dependency to the production
parser.

The adapter calls the exported, fixed-signature `yyjson_read_opts` and
`yyjson_write_opts` symbols directly from Ada. It imports ISO C `free` directly
for writer output. yyjson exposes immutable document destruction only as a
header-inline operation, so `src/flyology_json_bench_yyjson_free.c` is the one
necessary runtime shim. JSON policy, error classification, ownership, output
comparison, and checksum construction remain in Ada.

The lane performs a complete allocating DOM parse with yyjson's zero read
flags. This includes yyjson's number conversion and is therefore not presented
as equivalent work to Flyology_JSON's allocation-free event parser. It does
not offer genuine incremental input: callers must materialize a complete
contiguous document. The returned checksum includes yyjson's bytes-read and
value-count fields so the parsed result remains observable.

The writer lane prepares one immutable yyjson DOM outside timing and repeatedly
serializes it with zero write flags. Each timed operation includes yyjson's
complete output allocation, serialization, an Ada FNV-1a checksum over every
output octet, and `free`. Untimed preflight compares every emitted byte against
the expected compact JSON. This is `write_dom`, not `write_stream`: yyjson has
no public streaming writer, and the two lanes must not be ranked as equivalent
work. The admitted common-policy fixtures preserve member order, emit direct
UTF-8 and unescaped solidus, use the same short and uppercase control escapes,
and avoid numeric spellings that yyjson normalizes after conversion.

## Materialize and test

```sh
./test.sh
./test.sh portable
./test.sh native
```

`test.sh` is the maintained setup/build/smoke entrypoint for local and CI
runs. [`capability.json`](capability.json) conforms to the shared comparison
contract. `capabilities.sh` emits that exact checked-in document rather than
maintaining a second capability description. The test entrypoint builds the
writer comparison executable in both requested tracks and runs its exact-output
preflight without entering the timing loop.

Run the two bounded writer populations from the benchmark Alire workspace:

```sh
cd benchmarks
FLYOLOGY_JSON_BENCH_TUNING=portable \
  alr exec -- gprbuild -f -p \
    -P competitors/yyjson/yyjson_writer_benchmarks.gpr
FLYOLOGY_JSON_BENCH_FIXTURE=large_raw_string \
  competitors/yyjson/writer_bin/portable/\
flyology_json-benchmark_yyjson_writer_benchmark
```

The maintained populations reproduce the public writer benchmark's 1 MiB raw
string and 4,096-element nested-structure fixture. They do not add another
manual repetition loop: `flyology_bench` owns the fixed warmup, sampling, and
iteration bounds. A run is directional unless it follows the isolated-host
protocol, and its `write_dom` result remains cross-lane context for Flyology's
`write_stream` result rather than a same-lane ranking.

The GPR scenario variable `FLYOLOGY_JSON_BENCH_TRACK` selects `portable` or
`native` and places objects and executables in distinct track directories.
Portable release compilation uses `-O3 -gnatn -gnatp` for Ada and
`-O3 -DNDEBUG` for C. Native compilation adds `-mcpu=native` on arm64/aarch64
or `-march=native` on x86_64/amd64; other native architectures fail closed.
With no argument, `test.sh` builds and runs both tracks, but its success is
build and ABI evidence, not timing evidence. Formal timing still follows the
shared isolated-host protocol. The linked-symbol gate requires direct
`yyjson_write_opts` and `free` imports and rejects any writer shim symbol.

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
