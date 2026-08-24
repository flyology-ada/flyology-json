# Comparison CI protocol

External comparison support is maintained code, not a one-time local setup.
The repository's root test actions and CI call the same acquisition, build,
ABI, correctness, and benchmark entry points. A workflow must not reproduce
dependency or compiler setup in private inline shell.

## Pull requests and pushes

Every supported macOS and Linux PR/push job must:

1. verify the source and license locks, using a read-through cache only after
   digest verification;
2. materialize only admitted source paths, including the RapidJSON exclusion;
3. build all supported competitors and Flyology JSON in the portable track;
4. compile the native track where the runner/toolchain supports it, without
   treating its timing as a portable result;
5. run fixed-width ABI/symbol/nullability/lifetime tests for every C, C++, and
   Rust boundary;
6. run valid, invalid, truncation, Unicode, depth, duplicate, number, parse
   checksum, and writer-output smoke fixtures for every supported lane; and
7. validate emitted capability and result records against the committed
   schemas.

A competitor may be skipped only when its checked-in capability record declares
the exact lane, operating system, architecture, or toolchain unsupported. CI
must emit a structured skip with implementation, source revision, job, reason,
and capability-record SHA-256 conforming to `skip.schema.json`. Missing tools,
failed acquisition, checksum or license mismatch, compilation failure, ABI
failure, crash, wrong acceptance, or wrong output are failures—not skips.

PR/push runners are ordinary correctness/build CI. Their short timing smoke can
detect a broken harness or catastrophic slowdown, but shared-runner numbers are
never added to the controlled scorecard and never gate on a single latency
sample.

## Weekly scorecards

Weekly CI runs the complete portable comparison matrix on controlled benchmark
runners. It retains raw samples, capability records, source/license locks,
Cargo lock, build logs, tool versions, host controls, fixtures, JSONL results,
and a regression summary as durable artifacts. The summary compares only exact
matching contract/lane/profile/fixture/chunk/track populations.

Native-CPU scorecards run only on stable named machines where CPU identity and
host controls remain comparable. They are labeled `native`, published apart
from the portable scorecard, and never merged into one leaderboard.

A regression gate is based on the maintained statistical analysis of the raw
sample distributions and repeated interleaved rounds. The analysis and its
threshold/configuration are checked-in reviewable inputs. A single sample,
fastest-run selection, unmatched host, changed contract, or mixed build track
cannot fail or pass the gate. A statistically indicated regression triggers
review of profiles, work counters, generated code, and host evidence before it
is classified as a parser/writer regression.

If a scheduled runner cannot satisfy the isolated-host protocol, the workflow
marks its result `directional`; it does not silently publish a `formal` result.

## CI provenance

Every emitted result records the CI trigger/provider/workflow/job/run/attempt,
runner name and image, result URL, repository commit, executable and adapter
digests, source and license contract digests, Cargo lock digest when applicable,
validator, Node/npm package-manifest and tooling-lock digests,
compiler/linker/target/flags, host controls, seeded run order, and result
classification. Local results use trigger `local` and empty CI strings, but
must retain the same build, source, host, and contract provenance.
