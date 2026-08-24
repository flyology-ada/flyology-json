#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ ! -d "$root/upstream" ]; then
    echo "RapidJSON is not materialized; run acquire.sh" >&2
    exit 1
fi
if [ -e "$root/upstream/bin" ]; then
    echo "RapidJSON bin material was extracted; jsonchecker is forbidden" >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$root/upstream" && sha256sum -c "$root/files.sha256")
else
    (cd "$root/upstream" && shasum -a 256 -c "$root/files.sha256")
fi

expected=$(wc -l < "$root/files.sha256" | tr -d ' ')
actual=$(find "$root/upstream" -type f | wc -l | tr -d ' ')
if [ "$actual" != "$expected" ]; then
    echo "RapidJSON materialization contains an unattested file" >&2
    exit 1
fi

echo "verified RapidJSON 24b5e7a8b27f42fa16b96fc70aade9106cf7102f"
