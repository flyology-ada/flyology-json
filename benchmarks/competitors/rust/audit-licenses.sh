#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum --check Cargo.lock.sha256
else
  shasum -a 256 --check Cargo.lock.sha256
fi

actual=$(mktemp "${TMPDIR:-/tmp}/flyology-json-rust-license-attestation.XXXXXX")
trap 'rm -f "$actual"' EXIT HUP INT TERM

./generate-license-attestation.sh >"$actual"

if ! diff -u licenses.tsv "$actual"; then
  echo "Rust dependency license attestation is stale or incomplete" >&2
  exit 1
fi

packages=$(sed -e '/^#/d' -e '/^$/d' licenses.tsv | cut -f 1,2 | LC_ALL=C sort -u | wc -l | tr -d ' ')
evidence=$(sed -e '/^#/d' -e '/^$/d' licenses.tsv | wc -l | tr -d ' ')
printf 'Rust license audit passed: packages=%s evidence-records=%s\n' "$packages" "$evidence"
