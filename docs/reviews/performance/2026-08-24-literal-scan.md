# Literal-scan parser performance gate

Date: 2026-08-24

This review gates the register-local scan of `null`, `true`, and `false`. It is
directional before/after evidence, not a cross-platform performance claim. The
host was shared and several populations show interference, so the committed
baseline remains only a retained directional reference.

## Identities

- Baseline commit: `d7b32a28f8944501221e388b921ec34844c5f993`
- Candidate parent commit: `f4af6d0f8718a83642a2c40e80a7e3ce7555bf4f`
- Candidate parser core SHA-256:
  `940aa705cf47411fa0dd3f4efd1149098214ba67a32cc8ff1e12332aef829ec8`
- Candidate parser tests SHA-256:
  `639424d15aa6b33c432c0227fc5c195d4be7684bffdda9fca1520da1a591cd51`
- Candidate offset tests SHA-256:
  `7be18d658041438b175f465df302597e429c0fc9bef49d6f651abf6ff69f43cf`
- Candidate release binary SHA-256:
  `781a97ecb609cd128f8e0ff6107893b16895966798c42c7670da597ad7fd6c8c`
- Candidate release object SHA-256:
  `a652afe10fa4f39ca839b049ad8d6350ca7995ef32046af5aceceabee99ee784`
- ARM64 assembly slice SHA-256:
  `6c87fdcf374e6bd4deeeb741b39c3e404493dc4a08b2a6a5300fc83040e4abae`
- Fresh comparison JSONL SHA-256:
  `9b509484a5fcdd4e841b5c5c3184b136daa0843bef2cadb32abc9b696f07dbfd`
- Fresh comparison TSV SHA-256:
  `c10003355e22a0a482788cd3dcfc701c5eeb1f18200fdff28e87aaae1c49c249`

The complete 31 MiB dirty-tree campaign remains at the ignored repo-relative
path `benchmarks/obj/perf_gate_results/literal-scan-f4af6d0-working-tree-20260824/`.

Environment: MacBook Pro `Mac15,9`, Apple M3 Max, macOS 26.5.2 build 25F84,
GNAT 16.1.0, GPRbuild 26.0.0, Alire 2.1.1, Node 24.19.0, Rust 1.97.1,
Apple Clang 21.0.0, and portable release compilation without a native CPU
switch. The complete environment record has SHA-256
`f6347f4d5f3f8ddfb47c25b50a780a0b046e7e3b8bcd4ec774e39bf4c65c822f`.

## Method and result

Time Profiler identified repeated literal processing as a dominant leaf in the
literal-heavy large-array fixture. The accepted change keeps consumed count,
absolute offset, and literal position in local variables during a scan and
commits them together before every observable return. It retains ordinary byte
loads, preserves offset-failure precedence, and now checks representability
before each input access.

Five targeted reruns of the candidate measured 276.8, 280.2, 279.7, 277.4,
and 277.8 MiB/s for `large_array`, versus an immediate 207.6 MiB/s parent
measurement. Their coefficients of variation ranged from 1.33% to 13.72%.
These targeted runs suggest about 34% higher throughput.

The complete maintained portable comparison campaign then rebuilt every
adapter, validated 45 benchmark-contract tests and all 40 parser preflight
populations, and measured all 63 supported comparison populations. Against
the retained baseline, Flyology's `large_array` median changed from
1.345 ms / 209.061 MiB/s to 1.047 ms / 268.726 MiB/s: 22.2% lower latency and
28.5% higher throughput. The fresh population CV was 6.96%.

| Implementation | Contract lane | Fresh MiB/s |
| --- | --- | ---: |
| Flyology_JSON | parse events | 268.726 |
| RapidJSON SAX | parse events | 1,045.264 |
| yyjson | validate | 1,797.690 |
| simdjson | DOM | 660.587 |
| RapidJSON | DOM | 443.383 |
| serde_json | DOM | 395.281 |
| sonic-rs | DOM | 302.292 |
| simd-json | DOM | 314.418 |

The lanes intentionally differ. Flyology emits fine-grained events, validates
the strict profile, preserves exact number lexemes, and performs decoded-name
duplicate work; validation and DOM lanes have different outputs and lifetime
costs. The table is useful for optimization direction, not a claim of semantic
equivalence.

Other Flyology fixture deltas versus the retained run were between -3.4% and
+5.1%, except for the intended `large_array` gain. That range is consistent
with shared-host noise and does not establish unrelated speedups or
regressions.

Two alternatives were rejected. Clearing less of each result object improved
`large_array` only 2.2% and moved `large_object` by -1.6%. A success-only
literal fast path produced branch-heavy GNAT output and regressed
`large_array` to 136--177 MiB/s. Neither experiment remains in the source.

The maintained campaign command was:

```sh
PATH=/tmp/node-v24.19.0-darwin-arm64/bin:$PATH \
  ./scripts/run-weekly-benchmarks.sh portable OUTPUT_DIRECTORY
```

The retained function-only assembly slice is reproduced from the exact binary
identified above with:

```sh
/opt/homebrew/opt/llvm/bin/llvm-objdump \
  --disassemble --demangle --no-show-raw-insn \
  --start-address=0x10000bd20 --stop-address=0x10000c640 \
  benchmarks/bin/flyology_json-parser_benchmark \
  >process-literal-arm64.asm
```

## Generated-code and correctness review

The accepted ARM64 release loop uses byte loads, keeps cursor state in
registers across the valid path, and commits parser offset and literal position
after multiple input bytes instead of after each byte. Error, exhaustion, and
chunk-boundary exits each commit the exact progress they observed. There is no
source-level SIMD, wide input load, alignment, endianness, ABI, or native-ISA
assumption. GNAT unrolling increases the generated hot function by roughly
1.5 KiB; this is accepted provisionally because the measured literal-heavy
gain is material, while instruction-cache behavior remains a profiling target.

The parser suite passed with GNAT 16 validity, overflow, assertion, and
110-column style checks. Tests cover arbitrary Ada bounds, exact literal raw
ranges, delimiter lookahead without stale slices, every valid partition of
`null`, `true`, and `false`, every partition of each short mismatch and
truncation fixture, exact maximum-offset boundaries for four- and five-byte
literals, and error-precedence cases.

Final independent review after both test fixes found P0 0, P1 0, and P2 0.
The optimization is accepted as a directional parser milestone. A quiet-host
weekly run and additional compiler/OS measurements remain required before a
broader performance or portability claim.
