#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
alr=$("$project_root/scripts/find-alr.sh")
api_output="$project_root/docs/api"
theme_output="$project_root/docs/gnatdoc/html"
website_kit="$project_root/vendor/website-kit"

if [ ! -f "$website_kit/scripts/render-gnatdoc-theme.mjs" ]; then
   printf '%s\n' \
     "website-kit submodule is missing; run: git submodule update --init --recursive" >&2
   exit 1
fi

if ! command -v gnatdoc >/dev/null 2>&1; then
   installed_gnatdoc="${ALIRE_INSTALL_PREFIX:-"$HOME/.alire"}/bin/gnatdoc"
   if [ ! -x "$installed_gnatdoc" ]; then
      printf '%s\n' \
        "gnatdoc not found; install it with: $alr install gnatdoc_bin=26.0.0" >&2
      exit 1
   fi
   PATH=$(dirname "$installed_gnatdoc"):$PATH
   export PATH
fi

gnatdoc_version=$(gnatdoc --version 2>&1 | sed -n '1p')
case "$gnatdoc_version" in
   "GNATdoc 26.0.0 "*) ;;
   *)
      printf '%s\n' \
        "GNATdoc 26.0.0 is required; found: $gnatdoc_version" >&2
      exit 1
      ;;
esac

case "$api_output" in
   "$project_root"/docs/api) ;;
   *)
      printf '%s\n' "refusing unsafe documentation output path: $api_output" >&2
      exit 1
      ;;
esac
case "$theme_output" in
   "$project_root"/docs/gnatdoc/html) ;;
   *)
      printf '%s\n' "refusing unsafe GNATdoc theme path: $theme_output" >&2
      exit 1
      ;;
esac

cd "$project_root"
"$alr" build
rm -rf "$api_output" "$theme_output"
node "$website_kit/scripts/render-gnatdoc-theme.mjs" \
  "$project_root/docs/gnatdoc-theme.json" \
  "$theme_output"

gnatdoc_log=$(mktemp -t flyology-json-gnatdoc.XXXXXX)
trap 'rm -f "$gnatdoc_log"' EXIT HUP INT TERM
if ! "$alr" exec -- gnatdoc \
  --backend=html \
  --generate=public \
  --warnings \
  --style=leading \
  -P flyology_json.gpr \
  -O docs/api >"$gnatdoc_log" 2>&1
then
   cat "$gnatdoc_log" >&2
   exit 1
fi
cat "$gnatdoc_log"
node "$project_root/scripts/check-gnatdoc-diagnostics.mjs" \
  "$gnatdoc_log" \
  "$project_root/docs/gnatdoc-diagnostics.txt" \
  "$project_root/docs/gnatdoc-public-units.txt" \
  "$project_root"
rm -f "$gnatdoc_log"
trap - EXIT HUP INT TERM

node "$project_root/scripts/normalize-gnatdoc-html.mjs" "$api_output"
node "$project_root/scripts/exclude-gnatdoc-units.mjs" \
  "$api_output" \
  "$project_root/docs/gnatdoc-excluded-units.txt"

mkdir -p "$api_output/fonts"
cp "$website_kit/assets/fonts/geologica-latin-variable.woff2" "$api_output/fonts/"
cp "$project_root/website/assets/brand/flyology-mark-transparent.svg" \
  "$api_output/flyology-mark.svg"
cp "$website_kit/assets/scripts/ada-highlight.js" "$api_output/ada-highlight.js"
node "$website_kit/scripts/build-api-search-index.mjs" "$api_output"
if grep -q 'FlyologyApiSearch = \[\];' "$api_output/search-index.js"; then
   node "$project_root/scripts/build-legacy-api-index.mjs" "$api_output"
fi
node "$project_root/scripts/check-gnatdoc-public-units.mjs" \
  "$api_output" \
  "$project_root/docs/gnatdoc-public-units.txt"

test -s "$api_output/index.html"
test -s "$api_output/search-index.js"
test -s "$api_output/flyology-mark.svg"
test -s "$api_output/ada-highlight.js"
