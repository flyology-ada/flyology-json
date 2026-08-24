#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "usage: ./scripts/write-benchmark-manifest.sh OUTPUT_DIRECTORY" >&2
  exit 2
fi

output_directory=$1
(
  cd "$output_directory"
  if command -v sha256sum >/dev/null 2>&1; then
    find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort \
      | sed 's#^./##' | xargs sha256sum >SHA256SUMS
  else
    find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort \
      | sed 's#^./##' | xargs shasum -a 256 >SHA256SUMS
  fi
)
