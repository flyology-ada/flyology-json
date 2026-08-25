#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
object="$project_root/obj/public-writer-assembly/flyology_json_public_writer_assembly_probe.o"
executable="$project_root/tests/bin/flyology_json_public_writer_assembly_probe"

cd "$project_root"
alr exec -- gprbuild -f -p -j0 -P tests/flyology_json_public_writer_assembly_probe.gpr
"$executable"

hot_symbol_pattern='(writers__(put_string_fragment)|engine_writers__(put_string_fragment)'
hot_symbol_pattern="${hot_symbol_pattern}|writer_core.*put_string_fragment)"
undefined=$(nm -u "$object")
if printf '%s\n' "$undefined" | grep -Eiq "$hot_symbol_pattern"; then
  echo "public or core writer hot operation remained undefined in the probe" >&2
  exit 1
fi

symbols=$(nm -n "$object")
if ! printf '%s\n' "$symbols" | grep -Eq 'probe_fragment([.$]|$)'; then
  echo "public writer hot probe symbol is missing" >&2
  exit 1
fi

if command -v llvm-objdump >/dev/null 2>&1; then
  disassembly=$(llvm-objdump -dr --no-show-raw-insn "$object")
elif command -v otool >/dev/null 2>&1; then
  disassembly=$(otool -tvV "$object")
else
  disassembly=$(objdump -d "$object")
fi

probe_disassembly=$(
  printf '%s\n' "$disassembly" | awk '
    /probe_fragment.*:$/ {
      capture = 1
      found += 1
      print
      next
    }
    capture && (/^[^[:space:]].*:$/ || /^[[:xdigit:]]+[[:space:]]+<.*>:/) {
      capture = 0
    }
    capture { print }
    END { if (found < 1) exit 3 }
  '
)
if printf '%s\n' "$probe_disassembly" | grep -Eiq "$hot_symbol_pattern"; then
  echo "public or core writer hot operation remained out of line in the probe function" >&2
  exit 1
fi
if printf '%s\n' "$probe_disassembly" | grep -Eiq \
  '(_?ada__finalization|_?system__soft_links|_?system__tasking|_?system__secondary_stack|malloc|free)'; then
  echo "public writer hot function contains finalization, tasking, or allocation runtime calls" >&2
  exit 1
fi

echo "public writer assembly gate: PASS"
