#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
site="$project_root/build/site"
kit="$project_root/vendor/website-kit"

test -f "$kit/scripts/install-assets.mjs" || {
   printf '%s\n' \
     "website-kit submodule is missing; run: git submodule update --init --recursive" >&2
   exit 1
}

case "$site" in
   "$project_root"/build/site) ;;
   *) printf '%s\n' "refusing unsafe site output path: $site" >&2; exit 1 ;;
esac

"$project_root/scripts/verify-website-examples.mjs" "$project_root/website"
"$project_root/scripts/test-examples.sh"
"$project_root/scripts/docs.sh"
rm -rf "$site"
mkdir -p "$project_root/build"
cp -R "$project_root/website" "$site"
rm -f "$site/AGENTS.md"
node "$kit/scripts/install-assets.mjs" "$site"
mkdir -p "$site/api"
cp -R "$project_root/docs/api/." "$site/api/"
node "$project_root/scripts/resolve-api-links.mjs" "$site"
node "$project_root/scripts/cache-bust-site-assets.mjs" "$site"
touch "$site/.nojekyll"
node "$kit/scripts/check-site.mjs" "$site"
node "$project_root/scripts/verify-llms-txt.mjs" "$site"

test -s "$site/index.html"
test "$(cat "$site/CNAME")" = "json.flyology.org"
test -s "$site/llms.txt"
test -s "$site/guide/index.html"
test -s "$site/guide/getting-started/index.html"
test -s "$site/guide/parsing/index.html"
test -s "$site/guide/writing/index.html"
test -s "$site/guide/tokens-and-numbers/index.html"
test -s "$site/guide/profiles-and-errors/index.html"
test -s "$site/architecture/index.html"
test -s "$site/support/index.html"
test -s "$site/api/index.html"

printf '%s\n' "site built at $site"
