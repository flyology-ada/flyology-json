#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
runner="$repository_root/tests/bin/flyology_json-corpus_runner"
accept_root="$repository_root/tests/corpus_runner/accept"
mismatch_root="$repository_root/tests/corpus_runner/mismatch"
poison_root="$repository_root/tests/corpus_runner/poison"
stdout_file=$(mktemp "${TMPDIR:-/tmp}/flyology-json-work-guard-out.XXXXXX")
stderr_file=$(mktemp "${TMPDIR:-/tmp}/flyology-json-work-guard-err.XXXXXX")
trap 'rm -f "$stdout_file" "$stderr_file"' EXIT HUP INT TERM

expect_failure() {
  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    echo "expected failure: $*" >&2
    exit 1
  fi
}

cd "$repository_root"
alr exec -- gprbuild -p -j1 -P tools/corpus/corpus_runner.gpr

"$runner" --self-test-work-accounting >"$stdout_file"
grep -Fqx 'every-split work-accounting self-test: PASS' "$stdout_file"

expect_failure "$runner" "$accept_root" every-split
grep -Fq 'requires an explicit positive' "$stderr_file"

expect_failure "$runner" "$accept_root" every-split not-a-number
grep -Fq 'must be a positive unsigned integer' "$stderr_file"

expect_failure "$runner" "$accept_root" every-split 0
grep -Fq 'must be greater than zero' "$stderr_file"

expect_failure "$runner" "$accept_root" every-split 18_446_744_073_709_551_616
grep -Fq 'must be a positive unsigned integer' "$stderr_file"

expect_failure "$runner" "$repository_root/tests/corpus_runner/does-not-exist" typo
grep -Fqx 'unknown schedule: typo' "$stderr_file"

expect_failure "$runner" "$poison_root" every-split 41
grep -Fq 'refused before parsing: minimum work units= 42' "$stderr_file"
test ! -s "$stdout_file"

expect_failure "$runner" "$accept_root" every-split 42
grep -Fq 'every-split minimum work units= 42 ceiling= 42' "$stdout_file"
grep -Fq 'denied by caller work ceiling= 42' "$stderr_file"
grep -Fq 'after accepted work units= 39' "$stderr_file"

"$runner" "$accept_root" every-split 100 >"$stdout_file" 2>"$stderr_file"
test ! -s "$stderr_file"
grep -Fq 'corpus parser: fixtures= 1 unexpected= 0' "$stdout_file"
accept_work=$(sed -n 's/^every-split actual work units= *//p' "$stdout_file")
test -n "$accept_work"
test "$accept_work" -gt 42

expect_failure "$runner" "$mismatch_root" every-split 100
grep -Fq 'corpus parser: fixtures= 1 unexpected= 1' "$stdout_file"
mismatch_work=$(sed -n 's/^every-split actual work units= *//p' "$stdout_file")
test "$mismatch_work" = "$accept_work"

echo "corpus work guard: PASS"
