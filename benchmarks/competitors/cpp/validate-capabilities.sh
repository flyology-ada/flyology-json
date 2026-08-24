#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
comparison="$root/../../comparison"
node_command=${FLYOLOGY_JSON_BENCH_NODE:-node}

"$node_command" "$comparison/validate-records.mjs" \
    "$comparison/capability.schema.json" \
    "$root/simdjson/capability.json" \
    "$root/rapidjson/capability.json"

echo "C++ capability records passed Draft 2020-12 validation"
