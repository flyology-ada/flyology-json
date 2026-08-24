#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

digest()
{
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

check()
{
    path=$1
    expected=$2
    if [ ! -f "$root/upstream/$path" ]; then
        printf 'missing materialized yyjson file: %s\n' "$path" >&2
        exit 1
    fi
    actual=$(digest "$root/upstream/$path")
    if [ "$actual" != "$expected" ]; then
        printf '%s has digest %s, expected %s\n' "$path" "$actual" "$expected" >&2
        exit 1
    fi
}

check LICENSE 45e384d3d52c73cba3a64d6e6c25d47cd738cd8a55c30629e3201046eda62947
check yyjson.c ac2e9bbb2e2d9149d90878d40506a1d624fa0b33c979a11b61075c54782c6d6a
check yyjson.h 175867c5493a5df648cec566717fa1c29aa2f6096f5f0cf1efad0b65e1f6d7b3

printf 'verified yyjson 0.12.0 (8b4a38dc994a110abaec8a400615567bd996105f)\n'
