#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

alr exec -- gprbuild -q -P tests/flyology_json_writer_corpus_tests.gpr
tests/bin/flyology_json-writer_corpus_tests
node tests/writer-corpus/verify-independent.mjs
