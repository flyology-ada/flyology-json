#!/bin/sh
set -eu

if command -v alr >/dev/null 2>&1; then
   command -v alr
   exit 0
fi

candidate="${ALIRE_INSTALL_PREFIX:-"$HOME/.alire"}/bin/alr"
if [ -x "$candidate" ]; then
   printf '%s\n' "$candidate"
   exit 0
fi

printf '%s\n' "alr not found in PATH or the Alire install prefix" >&2
exit 1
