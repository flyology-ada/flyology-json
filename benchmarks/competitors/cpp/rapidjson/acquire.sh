#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
destination="$root/upstream"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/flyology-json-rapidjson.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

revision=24b5e7a8b27f42fa16b96fc70aade9106cf7102f
prefix="rapidjson-$revision"
archive="$temporary/source.tar.gz"
staging="$temporary/materialized"
url="https://github.com/Tencent/rapidjson/archive/$revision.tar.gz"

digest()
{
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

curl -fsSL "$url" -o "$archive"

if [ "$(wc -c < "$archive" | tr -d ' ')" != 1116703 ]; then
    echo "RapidJSON archive byte count does not match sources.lock.tsv" >&2
    exit 1
fi
if [ "$(digest "$archive")" != 2d2601a82d2d3b7e143a3c8d43ef616671391034bc46891a9816b79cf2d3e7a8 ]; then
    echo "RapidJSON archive digest does not match sources.lock.tsv" >&2
    exit 1
fi

# Extract only the admitted implementation headers and license. In particular,
# the archive's non-free bin/jsonchecker tree is never materialized.
mkdir -p "$staging"
tar -xzf "$archive" -C "$staging" --strip-components=1 \
    "$prefix/license.txt" \
    "$prefix/include"

rm -rf "$destination"
mv "$staging" "$destination"
"$root/verify.sh"
