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

Fresh portable and native runs completed sequentially from clean detached
commit `d7b32a28f8944501221e388b921ec34844c5f993` on an Apple M3 Max
(Mac15,9), macOS 26.5.2 build 25F84. The measured Ada, C, and C++ units used
GNAT-FSF GCC/G++ 16.1.0. The selected GPRbuild provider is 26.0.1, while its
executable reports 26.0.0. Rust used 1.97.1. Node/npm used 24.19.0/11.17.0.
Apple Clang 21.0.0 built only standalone ABI smoke executables, not the linked
comparison driver.

Both runs passed all adapter suites, exact 40-population parser validation,
exact 63-population comparison validation, semantic checksum preflights, the
structured serde_json/deep-nesting skip, and all 66 artifact manifest entries.
The portable harness applied no host-detected/native tuning switch; GNAT still
emitted its target baseline for binder code. Native Ada/C/C++ used
`-mcpu=native`, and native Rust used `-Ctarget-cpu=native`.

The complete bundles' `SHA256SUMS` file digests are:

- portable: `df82b498b862266097f7b031180db5430bbd23618aa1a4c96823578f923365b5`;
- native: `c566b9c933e93269d6986a1ad2e4ff7145852d9286e94776a40ccefc944f4ca7`.

The compact machine-readable baseline is retained under
`benchmarks/baselines/directional/local/2026-08-24/d7b32a28f8944501221e388b921ec34844c5f993/`.
It includes both JSONL result sets, derived TSVs, structured skips, environment
records, dependency resolution, and a manifest. The full bundles have no
durable external location; their omitted binaries, fixtures, locks, and logs
remain digest-attested but are not locally inspectable from the compact copy.
Linux execution remains CI evidence to collect after push. No Linux or
multi-GNAT performance claim is made from this local run.

## Directional comparison

Each cell is median binary throughput in MiB/s over 50 `flyology_bench`
samples. These shared, non-isolated local runs are directional, and several
populations have high variance. Lanes describe materially different work and
must not be combined into one leaderboard.

Portable track:

| Fixture | Flyology events | RapidJSON SAX events | yyjson validate | simdjson DOM | RapidJSON DOM | serde_json DOM | sonic-rs DOM | simd-json DOM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small mixed | 128.9 | 535.0 | 491.4 | 486.6 | 106.3 | 112.5 | 147.4 | 53.2 |
| large mixed | 159.1 | 507.1 | 1,771.6 | 612.4 | 338.3 | 115.7 | 329.4 | 106.0 |
| string heavy | 703.1 | 495.2 | 3,883.9 | 910.5 | 336.3 | 822.6 | 839.5 | 764.9 |
| number heavy | 163.0 | 255.2 | 1,081.1 | 655.6 | 448.8 | 351.0 | 403.3 | 310.5 |
| long mantissas | 301.4 | 260.5 | 1,978.9 | 9.0 | 1,002.9 | 1,048.6 | 951.2 | 721.5 |
| deep nesting | 155.9 | 226.2 | 677.4 | 154.0 | 92.9 | skipped | 44.7 | 14.6 |
| large array | 209.1 | 1,075.0 | 1,796.5 | 665.4 | 426.6 | 406.8 | 315.0 | 312.7 |
| large object | 150.5 | 860.5 | 3,320.6 | 413.8 | 384.4 | 75.7 | 852.5 | 193.1 |

Native track:

| Fixture | Flyology events | RapidJSON SAX events | yyjson validate | simdjson DOM | RapidJSON DOM | serde_json DOM | sonic-rs DOM | simd-json DOM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small mixed | 132.3 | 529.9 | 495.0 | 487.2 | 107.4 | 112.0 | 144.6 | 52.4 |
| large mixed | 156.9 | 503.7 | 1,787.3 | 611.8 | 331.5 | 113.2 | 311.1 | 105.6 |
| string heavy | 699.1 | 494.1 | 3,843.7 | 910.2 | 336.4 | 810.5 | 831.1 | 750.6 |
| number heavy | 160.6 | 254.1 | 1,096.5 | 654.5 | 470.6 | 368.0 | 411.3 | 314.5 |
| long mantissas | 296.4 | 257.2 | 1,987.3 | 9.0 | 996.8 | 1,050.7 | 962.2 | 676.9 |
| deep nesting | 155.5 | 221.2 | 662.3 | 154.5 | 27.1 | skipped | 16.7 | 14.6 |
| large array | 193.4 | 966.1 | 1,737.7 | 660.1 | 437.2 | 384.3 | 313.0 | 286.1 |
| large object | 151.9 | 857.7 | 3,298.7 | 909.4 | 418.9 | 83.5 | 831.4 | 211.9 |

Flyology events versus RapidJSON SAX is the closest directional context, not a
contract-comparable result. Flyology rejects decoded duplicate names with a
bounded crit-bit index and explicit capacities; RapidJSON preserves duplicates
and declares no equivalent depth limit. These valid fixtures avoid outcome
disagreement, but Flyology still performs the additional duplicate-index work.
RapidJSON also emits coarser complete-token callbacks while Flyology emits its
incremental begin/fragment/end grammar.

In the lower-variance portable run, whose event-lane CVs ranged from 0.55% to
8.86%, observed Flyology median throughput was 1.42x RapidJSON SAX on
string-heavy input and 1.16x on the adversarial 19-significant-digit mantissa
input. RapidJSON's observed median was about 1.5x to 5.7x Flyology on the other
six fixtures; the largest gaps remain the structurally dense array and
duplicate-checked object. These medians identify optimization priorities and
do not establish population-level speed claims.

yyjson's validation lane and all DOM lanes remain useful context, not peers.
The 19-significant-digit mantissa stress case drove simdjson DOM to about
9 MiB/s in both tracks; that observation is not representative numeric
throughput. Several native populations had high variance, and native-track
medians were not uniformly higher, reinforcing the directional classification.

## Findings

P0: none.

P1: none after correcting parser lifecycle fairness, observation work, Rust
ownership, cross-language linking, exact matrix validation, durable baseline
retention, compiler identity, and artifact-finalization failure handling.

P2: none for this directional milestone after separating target-reported parser
storage from exact semantic identities and making native architecture support
fail closed. Raw per-sample scorecards, interleaved controlled-host runs,
allocation hooks, Ada competitor lanes, and writer comparisons remain explicit
future work rather than claims made by these results.
