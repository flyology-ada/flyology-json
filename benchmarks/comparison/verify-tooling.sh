#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$root"

if [ "$(node --version)" != v24.19.0 ]; then
  echo "benchmark contract validation requires Node v24.19.0" >&2
  exit 1
fi
if [ "$(npm --version)" != 11.17.0 ]; then
  echo "benchmark contract validation requires npm 11.17.0" >&2
  exit 1
fi

actual=$(mktemp "${TMPDIR:-/tmp}/flyology-json-node-licenses.XXXXXX")
expected=$(mktemp "${TMPDIR:-/tmp}/flyology-json-node-licenses.XXXXXX")
trap 'rm -f "$actual" "$expected"' EXIT HUP INT TERM

jq -r '
  .packages
  | to_entries[]
  | select(.key | startswith("node_modules/"))
  | [(.key | sub("^node_modules/"; "")), .value.version, .value.license, .value.integrity]
  | @tsv
' package-lock.json | LC_ALL=C sort >"$actual"

awk -F '|' '!/^#/ { print $1 "\t" $2 "\t" $3 "\t" $4 }' \
  tooling-licenses.lock.tsv | LC_ALL=C sort >"$expected"
diff -u "$expected" "$actual"

while IFS='|' read -r package version license integrity license_path expected_sha
do
  case "$package" in
    '' | \#*) continue ;;
  esac
  evidence="node_modules/$package/$license_path"
  if [ ! -f "$evidence" ]; then
    echo "missing license evidence: $evidence" >&2
    exit 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    actual_sha=$(sha256sum "$evidence" | awk '{print $1}')
  else
    actual_sha=$(shasum -a 256 "$evidence" | awk '{print $1}')
  fi
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "license evidence digest mismatch: $evidence" >&2
    exit 1
  fi
done < tooling-licenses.lock.tsv

npm audit --omit=optional
