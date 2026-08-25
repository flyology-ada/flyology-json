# Compact batched-event parser performance gate

Date: 2026-08-24

This review records directional evidence for the private compact event drain
and dense scalar-array fast paths. It is not a cross-platform performance
claim. The checkout also contains unrelated, preserved user work, so these are
dirty-tree measurements rather than an official clean-checkout baseline.

## Identities and environment

- Candidate parent commit: `37afa6a360c3dca1fe086cbe166ea8b18b32a266`
- Parser core body SHA-256:
  `ac5aede4427fd87160ba3b8eba0e27494d18fa1cc01f6363832d885ea20ad42a`
- Parser core specification SHA-256:
  `c0cfafbd6d263f57ab6e55b5186c7ebff06bbb0fad848dc74e00e8531d51793b`
- Number scanner body SHA-256:
  `3b47985b4275365613369f5693f9c427cec634a4cdcbfc5f88da82a1e8a9cc09`
- Number scanner specification SHA-256:
  `847a92c4500ec9cb0763ce8fcc49d463d7dd7511c6a340f73657c93a462ca5c9`
- Parser-core tests SHA-256:
  `43619c0b0db25f36e7d7e5b092fd9cfe9a81db3b2821b7b59c2ab7e2d6715de5`
- Offset tests SHA-256:
  `b04e8369ea7e0a4a4eec1ffdd863ec51a196a995e34e77af0130839fdddccdb0`
- Comparison driver SHA-256:
  `df374a6ebacc5a32d76152090152b040957bf41d3dda39e5ce10cbb4aff651c3`
- Portable comparison binary SHA-256:
  `2673f7fea58a4f88c3cd20a102ee3668e7cea98582b964543d701acea2a82b7a`

The exact post-P1, pre-zero baseline uses parser-core body
`ca5ebaa9310744a248ca43c6a920dffda22e65511305727a5f95f1c9ad19669c`,
the same comparison driver identified above, and portable binary
`ef686b2f2685fbb755a1286f5c3625c3644bfaa23ec00290160c774e226ae3cf`.

Environment: MacBook Pro `Mac15,9`, Apple M3 Max, macOS 26.5.2 build 25F84,
GNAT 16.1.0, GPRbuild 26.0.0, Alire 2.1.1, and portable release compilation
without a native CPU switch.

## Accepted design

`Next`, full-event `Drain`, and private `Buffered_Drain` instantiate one static
parser engine. The compact descriptor stores event kind, exact source range,
flags, and at most one decoded UTF-8 scalar in caller storage. Raw string and
number text remains in the caller's exact input array. The descriptor is
private, contains no access value, performs no allocation, and makes no layout
or ABI promise.

The dense scalar-array path validates a comma plus a complete `null`, `true`,
or `false` token before committing either effect. A complete `,0` transition
uses a capacity-aware transaction only when the caller has room for its exact
`Number_Begin`, `Number_Fragment`, and `Number_End` transcript. It advances
the comma and zero together and does not materialize resumable number-DFA
state. `Next`, capacities below three, non-final chunk ends, invalid number
continuations, and source-offset boundaries fall back to the ordinary state
machine. Longer integer runs retain the ordinary checked scanner.

The comparison adapter visits a 256-element caller buffer of compact
descriptors. That size is an explicit benchmark experiment, not a parser
capacity or public default. The benchmark documentation discloses that
Flyology and RapidJSON SAX have different event granularity and transport.

## Excluded pre-P1 timing history

The numbers in this section predate the benchmark-contract P1 fix that added
timed Flyology scalar-value and member-name counters. They are retained only as
development history. They are not measurements of the exact candidate binary
identified above and cannot satisfy this change's performance gate. The
post-fix binary passes its exact Flyology signature and the complete 63-case
comparison preflight; fresh timing awaits a quiet host.

The later comma-first child experiment below uses `feab029` as its exact
paired baseline. Its accepted timings are independent of the excluded
pre-P1 populations in this section.

The [retained predecessor review](2026-08-24-literal-scan.md) records 1.047 ms /
268.726 MiB/s for the same 294,913-octet `large_array` fixture. That predecessor
used one-event `Next` and reconstructed the full `Event` record, while this
candidate uses compact buffered descriptors. The comparison is useful
directional history, not a same-operation speedup population. Seven consecutive
pre-P1 candidate runs measured these medians:

| Run | Median ns | Decimal GB/s | MiB/s | Population CV |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 266,340.492 | 1.1073 | 1,056.0 | 3.10% |
| 2 | 266,737.625 | 1.1056 | 1,054.4 | 3.29% |
| 3 | 266,065.109 | 1.1084 | 1,057.1 | 8.23% |
| 4 | 267,489.258 | 1.1025 | 1,051.4 | 3.68% |
| 5 | 267,060.547 | 1.1043 | 1,053.1 | 7.92% |
| 6 | 266,156.898 | 1.1080 | 1,056.7 | 9.57% |
| 7 | 266,163.734 | 1.1080 | 1,056.7 | 6.06% |

The excluded repeated median range was 1.1025--1.1084 GB/s. It suggested that
the lower end of the approved 1--1.5 GB/s scalar goal was within reach, but it
does not prove the post-P1 candidate's performance.

The excluded pre-P1 sequential comparison measured:

| Implementation | Contract lane | Median ns | Decimal GB/s | MiB/s |
| --- | --- | ---: | ---: | ---: |
| Flyology_JSON | parse events | 266,331.047 | 1.107 | 1,056.0 |
| RapidJSON SAX | parse events | 290,822.266 | 1.014 | 967.1 |
| yyjson | validate | 132,377.934 | 2.228 | 2,124.6 |
| simdjson | DOM | 424,466.156 | 0.695 | 662.6 |
| RapidJSON | DOM | 678,501.313 | 0.435 | 414.5 |
| serde_json | DOM | 717,428.375 | 0.411 | 392.0 |
| sonic-rs | DOM | 927,148.438 | 0.318 | 303.4 |
| simd-json | DOM | 946,045.563 | 0.312 | 297.3 |

The lanes are deliberately not merged into a leaderboard. In particular,
yyjson validates without delivering events, while DOM lanes construct owned
values. RapidJSON SAX returns complete-token callbacks; Flyology returns
fine-grained compact descriptors and performs strict incremental validation.
The shared host showed outliers, including a 21.20% RapidJSON SAX population
CV, so the table is directional evidence only.

## Profile and assembly evidence

The exact pre-zero Time Profiler trace contains 604 relevant leaf samples:
467 in `Buffered_Drain`, 117 in the timed descriptor observer, and 423 in the
dense scalar interval. Literal validation and the ordinary zero-number path
were the largest parser-side concentrations. Descriptor construction/copy
alone accounted for about 8.1% of the trace. This evidence selected the zero
transaction; the change is not based on fixture-name dispatch.

In the exact candidate portable binary, `Buffered_Drain` begins at
`0x100015ce0`. The ARM64 zero success block at
`0x1000177d4`--`0x1000178a4` checks that at least three descriptor slots remain,
checks the offset and delimiter/final-input gates, writes three adjacent
24-octet descriptors, and performs one final capacity comparison. It contains
no `bl` instruction and no number-DFA or resumable-token setup. The literal
success loop also remains call-free. The release `Run_Next` instantiation does
not contain the statically impossible three-event transaction.

The timed descriptor observer remains a separate auto-vectorized pass. It
updates member-name, scalar-value, total-event, source-range, and kind counters;
the final checksum combines every counter. The exact 63-case preflight makes
event omission, coalescing, or movement of those observations outside timed
work detectable.

Rejected experiments are absent from the candidate: fieldwise copying of the
large convenience event, constructing a compact record after first building
that event, unchecked access overlays, link-time optimization, a larger fixed
benchmark buffer, and a generic shape-publisher prototype. A statically bound
bufferless observer was also rejected: fusing observation into parsing created
a serial checksum dependency, lost the vectorized second pass, and fell to
roughly 304--312 microseconds. A lookup-table observer likewise prevented
vectorization and fell to roughly 324--352 microseconds. These measurements are
experimental rejection evidence, not accepted baselines.

## Comma-first scalar child milestone

The child candidate starts from commit
`feab02907eea7248e28ecf37ad323357f4d9ed20`. Its only parser change tests the
comma delimiter directly before calling the general token-delimiter
classifier. `Is_Token_Delimiter` already contains comma, so the new arm is
semantically redundant and changes only the generated branch shape. The
candidate parser-core body SHA-256 is
`a933d766a9c6cdb4d545367b569d817a03762f2a35502feb97ec167b004c89b6`.

The paired portable GNAT 16.1 comparison binaries are:

- baseline SHA-256
  `66cccd628298ce6d2a31bc16b23607d5f04fd2105790b230d6ce8e97f1018df5`;
- candidate SHA-256
  `73e8bb9ebd6d87e74bf1478a17d2bc091c8d92341bec5edecab0c3ec2e71867b`.

Both binaries use the same comparison harness, dependency closure, portable
release switches, and `large_array` selector. Both preflights return the exact
signature `14497054742`. Two accepted order-reversed pairs measured:

| Pair order | Variant | Median ns | Decimal GB/s | MiB/s | CV |
| --- | --- | ---: | ---: | ---: | ---: |
| baseline, candidate | baseline | 258,232.430 | 1.1420 | 1,089.1 | 2.47% |
| baseline, candidate | candidate | 245,814.461 | 1.1997 | 1,144.2 | 2.30% |
| candidate, baseline | candidate | 244,703.125 | 1.2052 | 1,149.4 | 1.98% |
| candidate, baseline | baseline | 254,347.656 | 1.1595 | 1,105.8 | 3.30% |

The paired result is 3.79--4.81% lower median latency and 3.94--5.05% higher
throughput. One earlier pilot pair is excluded: the candidate population had
a 33.49% CV and an 852,326.813 ns preemption outlier. Its median pointed in
the same direction but is not accepted evidence.

ARM64 inspection shows the common comma success path replacing the general
range checks and delimiter mask with `cmp #44; b.eq`. This saves six executed
instructions per comma-delimited dense literal while increasing object text
by 40 bytes. The complete checked parser runner and corpus work guard pass.
Independent review found no P0, P1, or P2 issue in the change or evidence.

## Correctness and review

The GNAT 16 parser suite passes with validity, overflow, assertion, and style
checks. It covers `Next`/`Drain` parity, direct compact/full drain parity,
arbitrary input and output bounds, exhaustive unit-fixture splits, randomized
chunk schedules, null and exact-capacity buffers, provisional failure, reset,
offset exhaustion, Unicode, duplicates, malformed input, and truncation.
The zero transaction is compared against `Next` at capacities 1, 2, 3, 4, 7,
16, and 64 across every split. Focused cases cover `00`, `0x`, `0}`,
truncation after zero, whitespace delimiting, exact capacity three, arbitrary
buffer bounds, and source offsets at `Byte_Offset'Last - 2` and
`Byte_Offset'Last - 1`.

The pinned corpus verifier reports JSONTestSuite 314 fixtures, JSON Schema Test
Suite 80 fixtures, and three WPT evidence files. All 394 parser fixtures pass
monolithically, in one-byte chunks, and under eight deterministic randomized
schedules. A full-corpus `every-split` attempt was stopped after audit showed
that the 250,001-byte adversarial fixture alone requests about 62.5 billion
input-byte visits: 250,002 separate parses, each processing up to the complete
fixture through checked one-event `Next`. The run was finite and stable at
about 7 MiB RSS, but is intentionally not claimed as completed evidence. The
compact transition fixtures in the parser suite still test every split, and
small transition fixtures test every partition. The imported corpus runner now
requires an explicit caller work ceiling, preflights the campaign's minimum
work before parsing, and charges every planned input octet and `Next` call at
runtime. Its maintained tiny-corpus regression verifies arithmetic overflow,
atomic denial, pre-parser refusal, zero-progress protection, and that a
mismatch does not skip later split points. The guard's final P0/P1/P2 review
found no remaining findings. The 82,539,090,222-unit full campaign remains
intentionally unexecuted.

The portable competitor campaign passes 45 benchmark-contract tests, all
source and license attestations, yyjson direct-import ABI and symbol tests, C++
adapter and symbol tests, ten Rust adapter tests, 40 exact parser preflight
populations, and 63 exact comparison preflight populations. The post-P1
Flyology `large_array` signature is `14497054742`; the complete 63-case
post-P1 comparison preflight passes. The campaign used the pinned
Node 24.19.0 toolchain; an earlier invocation correctly rejected the host's
unreviewed Node 25.2.1 before adapter verification and is superseded by the
pinned successful run.

Independent review classified two P1 findings. First, a partial literal after
a completed dense literal could reuse the prior iteration's lookahead limit.
The fix resets that limit on every loop iteration, and focused
`[null,true,fa` regressions cover both full and compact drains. Second, the
Flyology comparison path claimed the shared event lane without counting scalar
values and member names in timed work. The fixed timed descriptor visit counts
both and preflights them against the fixture contract; this invalidated the old
timings above and changed the exact signatures. The correctness fix re-reviews
found no remaining P0, P1, or P2 findings.

The zero-transaction review then found two P1 test gaps: comma-zero malformed
and truncated continuations, and exact offset-exhaustion coverage in the new
batched path. It also found P2 documentation and release-assembly checks for
the publisher-capacity invariant, dormant DFA state, and `Next` specialization.
All were fixed. The complete parser suite and corpus work guard pass after the
fixes, and the independent fix re-review reports no remaining P0, P1, or P2
findings.
