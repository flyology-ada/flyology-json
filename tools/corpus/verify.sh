#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
corpus_root="$repository_root/tests/corpus"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/flyology-json-corpus-verify.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

fail()
{
    printf 'corpus verification failed: %s\n' "$1" >&2
    exit 1
}

digest()
{
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        fail "neither sha256sum nor shasum is available"
    fi
}

check_digest()
{
    actual=$(digest "$1")
    [ "$actual" = "$2" ] || fail "$1 has digest $actual, expected $2"
}

check_manifest()
{
    corpus=$1
    manifest=$2
    expected_count=$3
    expected_bytes=$4

    sed 's/^[0-9a-f][0-9a-f]*  //' "$manifest" > "$temporary_root/expected-paths"
    (
        cd "$corpus"
        LC_ALL=C find . -type f -name '*.json' -print | sed 's#^./##' | LC_ALL=C sort
    ) > "$temporary_root/actual-paths"
    cmp -s "$temporary_root/expected-paths" "$temporary_root/actual-paths" ||
        fail "$corpus contains missing or unexpected JSON files"

    count=$(wc -l < "$temporary_root/actual-paths" | tr -d ' ')
    [ "$count" = "$expected_count" ] ||
        fail "$corpus contains $count JSON files, expected $expected_count"

    bytes=0
    while IFS= read -r fixture; do
        size=$(wc -c < "$corpus/$fixture" | tr -d ' ')
        bytes=$((bytes + size))
    done < "$temporary_root/actual-paths"
    [ "$bytes" = "$expected_bytes" ] ||
        fail "$corpus contains $bytes JSON bytes, expected $expected_bytes"

    while IFS='  ' read -r expected fixture; do
        actual=$(digest "$corpus/$fixture")
        [ "$actual" = "$expected" ] ||
            fail "$corpus/$fixture has digest $actual, expected $expected"
    done < "$manifest"
}

check_exact_files()
{
    corpus=$1
    manifest=$2
    shift 2

    sed 's/^[0-9a-f][0-9a-f]*  //' "$manifest" > "$temporary_root/allowed-files"
    for metadata in "$@"; do
        printf '%s\n' "$metadata"
    done >> "$temporary_root/allowed-files"
    LC_ALL=C sort "$temporary_root/allowed-files" > "$temporary_root/allowed-files-sorted"
    (
        cd "$corpus"
        LC_ALL=C find . -type f -print | sed 's#^./##' | LC_ALL=C sort
    ) > "$temporary_root/all-files"
    cmp -s "$temporary_root/allowed-files-sorted" "$temporary_root/all-files" ||
        fail "$corpus contains missing or unexpected files"
}

jts="$corpus_root/json_test_suite"
schema="$corpus_root/json_schema_test_suite"
wpt="$corpus_root/wpt_encoding"

printf '%s\n' README.md json_schema_test_suite json_test_suite wpt_encoding |
    LC_ALL=C sort > "$temporary_root/allowed-corpus-root"
(
    cd "$corpus_root"
    LC_ALL=C find . -mindepth 1 -maxdepth 1 -print | sed 's#^./##' | LC_ALL=C sort
) > "$temporary_root/actual-corpus-root"
cmp -s "$temporary_root/allowed-corpus-root" "$temporary_root/actual-corpus-root" ||
    fail "$corpus_root contains missing or unexpected top-level entries"

check_digest "$jts/LICENSE" 8bd0e0578be788c617ea01d18b2a8146e3746ae50bddadc65a5f9d3aad08ad49
check_digest "$jts/fixtures.sha256" 630835cd094ba815763b07ad577cf87511f4a50d2591b0390f3dd5d68df6ea7f
check_digest "$jts/expectations.tsv" dae37a27a099c4c9cceba9a84e1be48218ebc05f900aa9e0f7cddd39534aaff1
check_digest "$jts/exclusions.tsv" f24f7add50ab4c0bf14769ba6185320de70107c7afa10165988b224c6d6b4057
check_manifest "$jts" "$jts/fixtures.sha256" 314 353992
awk -F '\t' \
    'NF != 2 || $2 !~ /^(accept|reject_malformed|reject_duplicate|depth_dependent_accept)$/ { exit 1 }' \
    "$jts/expectations.tsv" || fail "JSONTestSuite expectations contain an unknown outcome"
cut -f 1 "$jts/expectations.tsv" > "$temporary_root/expectation-paths"
cmp -s "$temporary_root/expected-paths" "$temporary_root/expectation-paths" ||
    fail "JSONTestSuite expectations do not cover the exact selected paths"
check_exact_files "$jts" "$jts/fixtures.sha256" LICENSE expectations.tsv exclusions.tsv fixtures.sha256

check_digest "$schema/LICENSE" 837402bd25fad9b704265801ca3f92566a98157c1f9a7acd6f446299ba1c305a
check_digest "$schema/fixtures.sha256" beaf413b86145dee9d0f0b2b22299af14403c9fba910e53beef27561acff4ae0
check_digest "$schema/expectations.tsv" 294d7bca1142982294786605acb91e9cd2cfc099c75229e474ee92ebd038393a
check_manifest "$schema" "$schema/fixtures.sha256" 80 592224
awk -F '\t' 'NF != 2 || $2 != "accept" { exit 1 }' "$schema/expectations.tsv" ||
    fail "JSON Schema expectations contain an unknown outcome"
cut -f 1 "$schema/expectations.tsv" > "$temporary_root/expectation-paths"
cmp -s "$temporary_root/expected-paths" "$temporary_root/expectation-paths" ||
    fail "JSON Schema expectations do not cover the exact selected paths"
check_exact_files "$schema" "$schema/fixtures.sha256" LICENSE expectations.tsv fixtures.sha256

check_digest "$wpt/LICENSE.md" 5fac07febb0e2a97fb0d7b0def149ec08b642e1ba4b9c345283ab1cbd2af6570
check_digest "$wpt/evidence.sha256" fce6b4e6edfe4e0dfb3aa94ff75161e0708e1f1df4ec3dc9eb8439f95874ef61
[ "$(find "$wpt" -type f | wc -l | tr -d ' ')" = 2 ] ||
    fail "WPT evidence directory contains missing or unexpected files"

if find "$wpt" -type f -name '*.js' | grep . >/dev/null 2>&1; then
    fail "WPT executable JavaScript was vendored; only its digest attestation is allowed"
fi
if find "$corpus_root" -type l | grep . >/dev/null 2>&1; then
    fail "vendored corpus contains a symbolic link"
fi

printf 'corpus verification passed: JSONTestSuite=314, JSON-Schema=80, WPT evidence=3\n'
