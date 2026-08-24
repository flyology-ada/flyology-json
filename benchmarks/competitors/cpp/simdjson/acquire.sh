#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$root/../../../.." && pwd)
destination="$root/upstream"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/flyology-json-simdjson.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

revision=17fef66827864c33170996554b7aa0598da080cd
prefix="simdjson-$revision"
cache_dir=${FLYOLOGY_JSON_BENCH_SOURCE_CACHE:-/tmp/flyology-json-benchmark-sources}
archive="$cache_dir/simdjson-4.6.8-17fef668.tar.gz"
staging="$temporary/materialized"

digest()
{
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

if [ ! -f "$archive" ]; then
    "$project_root/scripts/verify-benchmark-sources.sh" "$cache_dir"
fi

if [ "$(wc -c < "$archive" | tr -d ' ')" != 6691503 ]; then
    echo "simdjson archive byte count does not match sources.lock.tsv" >&2
    exit 1
fi
if [ "$(digest "$archive")" != 5b95ee177ab5780f16eb2338ed4c6daa4c3613a9e0b0c0a2500904d9b3b8e88c ]; then
    echo "simdjson archive digest does not match sources.lock.tsv" >&2
    exit 1
fi

mkdir -p "$staging"
tar -xzf "$archive" -C "$staging" --strip-components=1 \
    "$prefix/LICENSE" \
    "$prefix/LICENSE-MIT" \
    "$prefix/singleheader/simdjson.h" \
    "$prefix/singleheader/simdjson.cpp"
mv "$staging/singleheader/simdjson.h" "$staging/simdjson.h"
mv "$staging/singleheader/simdjson.cpp" "$staging/simdjson.cpp"
rmdir "$staging/singleheader"

rm -rf "$destination"
mv "$staging" "$destination"
"$root/verify.sh"
