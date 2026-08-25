#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
corpus_root="$repository_root/tests/corpus"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/flyology-json-corpus-import.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

jts_commit=1ef36fa01286573e846ac449e8683f8833c5b26a
wpt_commit=58cbe5f7fe5d539a565c82666b82abfc52f017ce
schema_commit=b01af8c8d50244a2eb4dd3e01073e24823aa8691

for required in curl tar; do
    command -v "$required" >/dev/null 2>&1 || {
        printf 'required command is unavailable: %s\n' "$required" >&2
        exit 1
    }
done

digest()
{
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        printf 'required command is unavailable: sha256sum or shasum\n' >&2
        exit 1
    fi
}

exclusion_ledger="$corpus_root/json_test_suite/exclusions.tsv"
[ "$(digest "$exclusion_ledger")" = \
    f24f7add50ab4c0bf14769ba6185320de70107c7afa10165988b224c6d6b4057 ] || {
    printf 'JSONTestSuite exclusion ledger does not match its reviewed digest\n' >&2
    exit 1
}

curl -fsSL "https://github.com/nst/JSONTestSuite/archive/$jts_commit.tar.gz" \
    -o "$temporary_root/json-test-suite.tar.gz"
curl -fsSL \
    "https://github.com/json-schema-org/JSON-Schema-Test-Suite/archive/$schema_commit.tar.gz" \
    -o "$temporary_root/json-schema-test-suite.tar.gz"
mkdir -p "$temporary_root/wpt/encoding/streams"
wpt_raw="https://raw.githubusercontent.com/web-platform-tests/wpt/$wpt_commit"
curl -fsSL "$wpt_raw/encoding/textdecoder-fatal.any.js" \
    -o "$temporary_root/wpt/encoding/textdecoder-fatal.any.js"
curl -fsSL \
    "$wpt_raw/encoding/streams/decode-split-character.any.js" \
    -o "$temporary_root/wpt/encoding/streams/decode-split-character.any.js"
curl -fsSL \
    "$wpt_raw/encoding/streams/decode-incomplete-input.any.js" \
    -o "$temporary_root/wpt/encoding/streams/decode-incomplete-input.any.js"
curl -fsSL "$wpt_raw/LICENSE.md" \
    -o "$temporary_root/wpt/LICENSE.md"

mkdir -p "$temporary_root/source"
tar -xzf "$temporary_root/json-test-suite.tar.gz" -C "$temporary_root/source"
tar -xzf "$temporary_root/json-schema-test-suite.tar.gz" -C "$temporary_root/source"
jts="$temporary_root/source/JSONTestSuite-$jts_commit"
schema="$temporary_root/source/JSON-Schema-Test-Suite-$schema_commit"

tail -n +2 "$exclusion_ledger" > "$temporary_root/jts-exclusions"
cut -f 1 "$temporary_root/jts-exclusions" > "$temporary_root/jts-excluded-paths"
tab=$(printf '\t')
while IFS="$tab" read -r fixture expected_hash expected_bytes reason; do
    [ -n "$reason" ] || {
        printf 'missing exclusion rationale for %s\n' "$fixture" >&2
        exit 1
    }
    actual_hash=$(digest "$jts/$fixture")
    actual_bytes=$(wc -c < "$jts/$fixture" | tr -d ' ')
    [ "$actual_hash" = "$expected_hash" ] && [ "$actual_bytes" = "$expected_bytes" ] || {
        printf 'excluded upstream fixture changed: %s\n' "$fixture" >&2
        exit 1
    }
done < "$temporary_root/jts-exclusions"

LC_ALL=C find "$jts/test_parsing" -type f -name '*.json' -print |
    sed "s#^$jts/##" | LC_ALL=C sort |
    grep -Fvx -f "$temporary_root/jts-excluded-paths" \
    > "$temporary_root/jts-paths"
while IFS= read -r fixture; do
    hash=$(digest "$jts/$fixture")
    printf '%s  %s\n' "$hash" "$fixture"
done < "$temporary_root/jts-paths" > "$temporary_root/jts-manifest"
[ "$(wc -l < "$temporary_root/jts-manifest" | tr -d ' ')" = 314 ]
[ "$(digest "$temporary_root/jts-manifest")" = \
    630835cd094ba815763b07ad577cf87511f4a50d2591b0390f3dd5d68df6ea7f ]
[ "$(digest "$jts/LICENSE")" = \
    8bd0e0578be788c617ea01d18b2a8146e3746ae50bddadc65a5f9d3aad08ad49 ]

LC_ALL=C find "$schema/tests/draft2020-12" -type f -name '*.json' -print |
    sed "s#^$schema/##" | LC_ALL=C sort > "$temporary_root/schema-paths"
while IFS= read -r fixture; do
    hash=$(digest "$schema/$fixture")
    printf '%s  %s\n' "$hash" "$fixture"
done < "$temporary_root/schema-paths" > "$temporary_root/schema-manifest"
[ "$(wc -l < "$temporary_root/schema-manifest" | tr -d ' ')" = 80 ]
[ "$(digest "$temporary_root/schema-manifest")" = \
    beaf413b86145dee9d0f0b2b22299af14403c9fba910e53beef27561acff4ae0 ]
[ "$(digest "$schema/LICENSE")" = \
    837402bd25fad9b704265801ca3f92566a98157c1f9a7acd6f446299ba1c305a ]

printf '%s  %s\n' \
    "$(digest "$temporary_root/wpt/encoding/streams/decode-incomplete-input.any.js")" \
    encoding/streams/decode-incomplete-input.any.js \
    "$(digest "$temporary_root/wpt/encoding/streams/decode-split-character.any.js")" \
    encoding/streams/decode-split-character.any.js \
    "$(digest "$temporary_root/wpt/encoding/textdecoder-fatal.any.js")" \
    encoding/textdecoder-fatal.any.js > "$temporary_root/wpt-manifest"
[ "$(digest "$temporary_root/wpt-manifest")" = \
    fce6b4e6edfe4e0dfb3aa94ff75161e0708e1f1df4ec3dc9eb8439f95874ef61 ]
[ "$(digest "$temporary_root/wpt/LICENSE.md")" = \
    5fac07febb0e2a97fb0d7b0def149ec08b642e1ba4b9c345283ab1cbd2af6570 ]

if [ ! -e "$corpus_root/json_test_suite/test_parsing" ]; then
    mkdir -p "$corpus_root/json_test_suite/test_parsing"
    while IFS= read -r fixture; do
        cp "$jts/$fixture" "$corpus_root/json_test_suite/$fixture"
    done < "$temporary_root/jts-paths"
fi
[ -e "$corpus_root/json_test_suite/LICENSE" ] ||
    cp "$jts/LICENSE" "$corpus_root/json_test_suite/LICENSE"
[ -e "$corpus_root/json_test_suite/fixtures.sha256" ] ||
    cp "$temporary_root/jts-manifest" "$corpus_root/json_test_suite/fixtures.sha256"

if [ ! -e "$corpus_root/json_schema_test_suite/tests" ]; then
    mkdir -p "$corpus_root/json_schema_test_suite/tests/draft2020-12"
    while IFS= read -r fixture; do
        target="$corpus_root/json_schema_test_suite/$fixture"
        mkdir -p "$(dirname "$target")"
        cp "$schema/$fixture" "$target"
    done < "$temporary_root/schema-paths"
fi
[ -e "$corpus_root/json_schema_test_suite/LICENSE" ] ||
    cp "$schema/LICENSE" "$corpus_root/json_schema_test_suite/LICENSE"
[ -e "$corpus_root/json_schema_test_suite/fixtures.sha256" ] ||
    cp "$temporary_root/schema-manifest" "$corpus_root/json_schema_test_suite/fixtures.sha256"

mkdir -p "$corpus_root/wpt_encoding"
[ -e "$corpus_root/wpt_encoding/LICENSE.md" ] ||
    cp "$temporary_root/wpt/LICENSE.md" "$corpus_root/wpt_encoding/LICENSE.md"
[ -e "$corpus_root/wpt_encoding/evidence.sha256" ] ||
    cp "$temporary_root/wpt-manifest" "$corpus_root/wpt_encoding/evidence.sha256"

"$repository_root/tools/corpus/verify.sh"
