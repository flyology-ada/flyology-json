#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$root/../../.." && pwd)
destination="$root/upstream"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/flyology-json-yyjson.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

cache=${FLYOLOGY_JSON_BENCH_SOURCE_CACHE:-/tmp/flyology-json-benchmark-sources}
manifest="$project_root/benchmarks/comparison/sources.lock.tsv"
verifier="$project_root/scripts/verify-benchmark-sources.sh"

"$verifier" "$cache"

record=$(awk -F '|' '$1 == "yyjson" { print; found=1; exit } END { exit !found }' "$manifest")
old_ifs=$IFS
IFS='|'
set -f
set -- $record
set +f
IFS=$old_ifs

if [ "$#" -ne 11 ]; then
    printf 'yyjson source-lock record has %s fields, expected 11\n' "$#" >&2
    exit 1
fi

version=$2
revision=$3
archive=$4

if [ "$version" != 0.12.0 ] || \
   [ "$revision" != 8b4a38dc994a110abaec8a400615567bd996105f ]; then
    printf 'yyjson source-lock identity is not the reviewed 0.12.0 revision\n' >&2
    exit 1
fi

archive_path="$cache/$archive"
archive_root=$(tar -tf "$archive_path" | sed -n '1s|/$||p')
case "$archive_root" in
    '' | /* | ../* | */../* | */..)
        printf 'yyjson archive has an unsafe root: %s\n' "$archive_root" >&2
        exit 1
        ;;
esac

digest()
{
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

extract()
{
    path=$1
    expected=$2
    output="$temporary/$(basename "$path")"
    tar -xOf "$archive_path" "$archive_root/$path" > "$output"
    actual=$(digest "$output")
    if [ "$actual" != "$expected" ]; then
        printf 'yyjson %s has digest %s, expected %s\n' "$path" "$actual" "$expected" >&2
        exit 1
    fi
}

extract LICENSE 45e384d3d52c73cba3a64d6e6c25d47cd738cd8a55c30629e3201046eda62947
extract src/yyjson.c ac2e9bbb2e2d9149d90878d40506a1d624fa0b33c979a11b61075c54782c6d6a
extract src/yyjson.h 175867c5493a5df648cec566717fa1c29aa2f6096f5f0cf1efad0b65e1f6d7b3

mkdir -p "$destination"
install -m 0644 "$temporary/LICENSE" "$destination/LICENSE"
install -m 0644 "$temporary/yyjson.c" "$destination/yyjson.c"
install -m 0644 "$temporary/yyjson.h" "$destination/yyjson.h"

printf 'materialized yyjson %s from verified archive %s\n' "$revision" "$archive"
