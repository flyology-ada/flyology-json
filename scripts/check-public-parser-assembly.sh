#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
object="$project_root/obj/public-parser-assembly/flyology_json_public_parser_assembly_probe.o"
executable="$project_root/tests/bin/flyology_json_public_parser_assembly_probe"

cd "$project_root"
alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_public_parser_assembly_probe.gpr
"$executable"

undefined=$(nm -u "$object")
hot_symbol_pattern='((strict|preserve)_parsing__(drain|core_drain|kind|source|has_raw_slice|resolve_raw_range|decoded_kind|decoded_source|decoded_scalar|boolean_data)|parser_core__(drain|buffered_kind|buffered_source|buffered_has_raw_slice|buffered_boolean_data|buffered_decoded_kind|buffered_decoded_source|buffered_decoded_scalar)|convert_event)'
if printf '%s\n' "$undefined" | grep -Eiq "$hot_symbol_pattern"; then
  echo "public or core parser hot operation remained undefined in the probe" >&2
  exit 1
fi

symbols=$(nm -n "$object")
for mode in strict preserve; do
  if ! printf '%s\n' "$symbols" | grep -Eq "probe_${mode}([.$]|$)"; then
    echo "public parser ${mode} hot probe symbol is missing" >&2
    exit 1
  fi
done
if printf '%s\n' "$symbols" | grep -Eiq "$hot_symbol_pattern"; then
  echo "public or core parser hot operation remained as an object symbol" >&2
  exit 1
fi

if command -v otool >/dev/null 2>&1; then
  disassembly=$(otool -tvV "$object")
  relocations=$(otool -rv "$object")
else
  disassembly=$(objdump -d "$object")
  relocations=$(objdump -r "$object")
fi
if printf '%s\n' "$relocations" | grep -Eiq "$hot_symbol_pattern"; then
  echo "public or core parser hot operation remained as a probe relocation" >&2
  exit 1
fi

probe_disassembly=$(
  printf '%s\n' "$disassembly" | awk '
    /probe_(strict|preserve).*:$/ {
      capture = 1
      found += 1
      print
      next
    }
    capture && (/^[^[:space:]].*:$/ || /^[[:xdigit:]]+[[:space:]]+<.*>:/) {
      capture = 0
    }
    capture { print }
    END { if (found < 2) exit 3 }
  '
)
if printf '%s\n' "$probe_disassembly" | grep -Eiq "$hot_symbol_pattern"; then
  echo "public or core parser hot operation remained out of line in a probe hot function" >&2
  exit 1
fi
if printf '%s\n' "$probe_disassembly" | grep -Eq \
  '(^|[[:space:]])blr([[:space:]]|$)|callq?[[:space:]]+\*'; then
  echo "public parser strict or preserve hot function contains an indirect call" >&2
  exit 1
fi

echo "public parser strict/preserve assembly gate: PASS"
