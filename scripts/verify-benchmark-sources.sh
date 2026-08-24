#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_manifest="$project_root/benchmarks/comparison/sources.lock.tsv"
license_manifest="$project_root/benchmarks/comparison/licenses.lock.tsv"
cache_dir=${1:-${FLYOLOGY_JSON_BENCH_SOURCE_CACHE:-/tmp/flyology-json-benchmark-sources}}
offline=${FLYOLOGY_JSON_BENCH_OFFLINE:-0}

case "$offline" in
  0 | 1) ;;
  *)
    echo "FLYOLOGY_JSON_BENCH_OFFLINE must be 0 or 1" >&2
    exit 2
    ;;
esac

if command -v sha256sum >/dev/null 2>&1
then
  sha256_file()
  {
    sha256sum "$1" | awk '{print $1}'
  }
  sha256_stdin()
  {
    sha256sum | awk '{print $1}'
  }
elif command -v shasum >/dev/null 2>&1
then
  sha256_file()
  {
    shasum -a 256 "$1" | awk '{print $1}'
  }
  sha256_stdin()
  {
    shasum -a 256 | awk '{print $1}'
  }
else
  echo "sha256sum or shasum is required" >&2
  exit 2
fi

mkdir -p "$cache_dir"

if ! awk -F '|' '
  /^#/ { next }
  NF != 11 || $1 == "" { exit 1 }
  seen[$1]++ { exit 1 }
' "$source_manifest"
then
  echo "source manifest has a malformed or duplicate record" >&2
  exit 1
fi

if ! awk -F '|' '
  /^#/ { next }
  NF != 4 || $1 == "" || $2 == "" || $3 == "" || $4 == "" { exit 1 }
  seen[$1 SUBSEP $2]++ { exit 1 }
' "$license_manifest"
then
  echo "license manifest has a malformed or duplicate record" >&2
  exit 1
fi

while IFS='|' read -r source_id version revision archive expected_bytes expected_sha \
  archive_license admitted_license format url admission
do
  case "$source_id" in
    '' | \#*) continue ;;
  esac

  case "$archive" in
    '' | *[!A-Za-z0-9._-]*)
      echo "$source_id has unsafe archive name: $archive" >&2
      exit 1
      ;;
  esac
  case "$url" in
    https://*) ;;
    *)
      echo "$source_id does not use HTTPS: $url" >&2
      exit 1
      ;;
  esac
  case "$expected_bytes" in
    '' | *[!0-9]*)
      echo "$source_id has invalid byte length: $expected_bytes" >&2
      exit 1
      ;;
  esac
  if ! printf '%s\n' "$expected_sha" | grep -Eq '^[0-9a-f]{64}$'
  then
    echo "$source_id has invalid SHA-256: $expected_sha" >&2
    exit 1
  fi
  if ! awk -F '|' -v wanted="$source_id" \
    '$1 == wanted { found=1 } END { exit !found }' "$license_manifest"
  then
    echo "$source_id has no license evidence" >&2
    exit 1
  fi
  if [ -e "$cache_dir/$archive" ] && [ ! -f "$cache_dir/$archive" ]
  then
    echo "$source_id cache target is not a regular file: $cache_dir/$archive" >&2
    exit 1
  fi

  target="$cache_dir/$archive"
  if [ ! -f "$target" ]
  then
    if [ "$offline" = 1 ]
    then
      echo "missing offline source: $target" >&2
      exit 1
    fi
    partial=$(mktemp "$cache_dir/.download.XXXXXX")
    if ! curl --fail --location --proto '=https' --tlsv1.2 \
      --user-agent 'flyology-json-benchmark-provenance' \
      --output "$partial" "$url"
    then
      rm -f "$partial"
      exit 1
    fi
    actual_sha=$(sha256_file "$partial")
    if [ "$actual_sha" != "$expected_sha" ]
    then
      echo "$source_id download SHA-256 mismatch" >&2
      rm -f "$partial"
      exit 1
    fi
    mv "$partial" "$target"
  fi

  actual_bytes=$(wc -c < "$target" | tr -d ' ')
  actual_sha=$(sha256_file "$target")
  if [ "$actual_bytes" != "$expected_bytes" ]
  then
    echo "$source_id byte length mismatch: $actual_bytes != $expected_bytes" >&2
    exit 1
  fi
  if [ "$actual_sha" != "$expected_sha" ]
  then
    echo "$source_id SHA-256 mismatch: $actual_sha != $expected_sha" >&2
    exit 1
  fi

  case "$format" in
    tar.gz | crate)
      tar -tf "$target" >/dev/null
      ;;
    zip)
      unzip -tq "$target" >/dev/null
      ;;
    *)
      echo "$source_id has unsupported archive format: $format" >&2
      exit 1
      ;;
  esac

  printf '%s %s %s %s\n' "$source_id" "$version" "$revision" "$actual_sha"
done < "$source_manifest"

while IFS='|' read -r source_id archive_path expected_sha evidence
do
  case "$source_id" in
    '' | \#*) continue ;;
  esac

  case "$archive_path" in
    /* | ../* | */../* | */..)
      echo "$source_id has unsafe license evidence path: $archive_path" >&2
      exit 1
      ;;
  esac

  archive=$(awk -F '|' -v wanted="$source_id" \
    '$1 == wanted { print $4; exit }' "$source_manifest")
  format=$(awk -F '|' -v wanted="$source_id" \
    '$1 == wanted { print $9; exit }' "$source_manifest")
  if [ -z "$archive" ]
  then
    echo "license source is absent from source manifest: $source_id" >&2
    exit 1
  fi

  case "$format" in
    tar.gz | crate)
      actual_sha=$(tar -xOf "$cache_dir/$archive" "$archive_path" | sha256_stdin)
      ;;
    zip)
      actual_sha=$(unzip -p "$cache_dir/$archive" "$archive_path" | sha256_stdin)
      ;;
    *)
      echo "$source_id has unsupported license archive format: $format" >&2
      exit 1
      ;;
  esac

  if [ "$actual_sha" != "$expected_sha" ]
  then
    echo "$source_id license evidence mismatch for $archive_path" >&2
    exit 1
  fi
done < "$license_manifest"

rapidjson_archive=$(awk -F '|' '$1 == "rapidjson" { print $4; exit }' "$source_manifest")
rapidjson_root=$(tar -tf "$cache_dir/$rapidjson_archive" | sed -n '1s|/$||p')
if ! tar -tf "$cache_dir/$rapidjson_archive" | \
  grep -q "^$rapidjson_root/bin/jsonchecker/"
then
  echo "RapidJSON archive no longer contains the reviewed exclusion path" >&2
  exit 1
fi

echo "verified benchmark sources and license evidence in $cache_dir"
echo "RapidJSON bin/jsonchecker is excluded and was not extracted"
