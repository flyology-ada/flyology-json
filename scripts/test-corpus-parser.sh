#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
schedule=${1:-monolith}

if [ "$schedule" = every-split ]; then
  if [ "$#" -ne 2 ]; then
    echo "usage: $0 every-split MAX-WORK-UNITS" >&2
    exit 2
  fi
elif [ "$#" -gt 1 ]; then
  echo "usage: $0 {monolith|one-byte|randomized}" >&2
  exit 2
fi

cd "$repository_root"
scripts/verify-corpora.sh
alr exec -- gprbuild -f -p -j0 -P tools/corpus/corpus_runner.gpr
if [ "$schedule" = every-split ]; then
  exec tests/bin/flyology_json-corpus_runner tests/corpus "$schedule" "$2"
fi
exec tests/bin/flyology_json-corpus_runner tests/corpus "$schedule"
