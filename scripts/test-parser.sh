#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$project_root"
alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_parser_tests.gpr

for test_program in \
  flyology_json-number_dfa_tests \
  flyology_json-utf8_tests \
  flyology_json-duplicate_index_tests \
  flyology_json-parser_core_tests \
  flyology_json-parser_core-offset_tests \
  flyology_json-parser_unicode_escape_tests
do
  "$project_root/tests/bin/$test_program"
done
