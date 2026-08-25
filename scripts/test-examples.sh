#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

cd "$repo_root"
alr build
alr exec -- gprbuild -f -p -j0 -P examples/flyology_json_examples.gpr
"$repo_root/examples/bin/streaming_parser"
"$repo_root/examples/bin/transactional_writer"
"$repo_root/examples/bin/landing_samples"
