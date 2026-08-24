# Local directional comparison baseline

This baseline was collected sequentially, portable first and native second,
from clean detached commit `d7b32a28f8944501221e388b921ec34844c5f993`:

```sh
./scripts/run-weekly-benchmarks.sh portable OUTPUT_DIRECTORY
./scripts/run-weekly-benchmarks.sh native OUTPUT_DIRECTORY
```

The host was an Apple M3 Max Mac15,9 running macOS 26.5.2 build 25F84. It was
not isolated, frequency-locked, affinity-pinned, or thermally controlled, so
these results are directional rather than a formal regression scorecard.

Each track retains the complete parser and comparison JSONL summaries, derived
comparison TSV, structured skip, environment record, and the original full
artifact manifest. The omitted binaries, fixtures, build logs, locks, source
copies, and capability records remain digest-attested by
`artifact-SHA256SUMS`, but they are not locally inspectable from this compact
baseline. No durable external copy of the complete bundles is claimed.

`SHA256SUMS` covers every retained file except itself. Validate it from this
directory with:

```sh
shasum -a 256 -c SHA256SUMS
```

Semantic validation must use Node 24.19.0 and the scripts and schemas from the
recorded harness commit, not a future checkout. From this directory, with
`recorded_checkout` naming a clean checkout of that commit, run:

```sh
npm ci --ignore-scripts --prefix "$recorded_checkout/benchmarks/comparison"
baseline_scratch=$(mktemp -d)
trap 'rm -rf "$baseline_scratch"' EXIT
node "$recorded_checkout/scripts/validate-parser-benchmarks.mjs" portable/flyology-parser.jsonl
node "$recorded_checkout/scripts/validate-parser-benchmarks.mjs" native/flyology-parser.jsonl
node "$recorded_checkout/scripts/summarize-comparison-benchmarks.mjs" portable \
  portable/comparison-summary.jsonl >"$baseline_scratch/portable-regenerated.tsv"
node "$recorded_checkout/scripts/summarize-comparison-benchmarks.mjs" native \
  native/comparison-summary.jsonl >"$baseline_scratch/native-regenerated.tsv"
cmp portable/comparison-summary.tsv "$baseline_scratch/portable-regenerated.tsv"
cmp native/comparison-summary.tsv "$baseline_scratch/native-regenerated.tsv"
node "$recorded_checkout/benchmarks/comparison/validate-records.mjs" \
  "$recorded_checkout/benchmarks/comparison/skip.schema.json" \
  portable/comparison-skip.json native/comparison-skip.json
grep '  fixtures/' portable/artifact-SHA256SUMS >"$baseline_scratch/portable-fixtures.sha256"
grep '  fixtures/' native/artifact-SHA256SUMS >"$baseline_scratch/native-fixtures.sha256"
cmp "$baseline_scratch/portable-fixtures.sha256" "$baseline_scratch/native-fixtures.sha256"
```

The two validator calls each require exactly 40 parser populations; TSV
regeneration requires exactly 63 comparison populations with 50 samples each.
The environment records must identify the directory commit and contain an
empty `working_tree_status` section.

The result interpretation and mandatory review are recorded in
`docs/reviews/performance/2026-08-24-benchmark-ci.md`.
