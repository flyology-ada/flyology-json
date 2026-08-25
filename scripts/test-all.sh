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

alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_public_foundation_tests.gpr
"$project_root/tests/bin/flyology_json-public_foundation_tests"

alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_public_parsing_tests.gpr
"$project_root/tests/bin/flyology_json-public_parsing_tests"

#  Materialize Alire's host-local generated project configuration before the
#  external consumer imports the crate's public GPR project. Clean source
#  archives intentionally do not contain config/.
alr build
alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_external_consumer_smoke.gpr
"$project_root/tests/bin/flyology_json_external_consumer_smoke"

"$project_root/scripts/check-public-parser-assembly.sh"
"$project_root/scripts/check-public-writer-assembly.sh"

alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_writer_core_tests.gpr
"$project_root/tests/bin/flyology_json-writer_core_tests"

alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_public_writing_tests.gpr
"$project_root/tests/bin/flyology_json-public_writing_tests"

"$project_root/scripts/test-writer-corpus.sh"

for corpus_schedule in monolith one-byte randomized
do
  "$project_root/scripts/test-corpus-parser.sh" "$corpus_schedule"
done

"$project_root/scripts/test-corpus-work-guard.sh"
