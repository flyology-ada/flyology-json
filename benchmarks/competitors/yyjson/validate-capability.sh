#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
comparison="$root/../../comparison"

cd "$comparison"
node validate-records.mjs capability.schema.json "$root/capability.json"
printf 'yyjson capability passed the maintained contract validator\n'
