#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] ||
   { [ "$1" != candidate ] && [ "$1" != indexed ]; }; then
  echo "usage: ./scripts/verify-release.sh candidate|indexed [ORIGIN-COMMIT]" >&2
  exit 2
fi

mode=$1
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
crate_name=$(sed -n 's/^name = "\([^"]*\)"$/\1/p' "$project_root/alire.toml")
version=$(sed -n 's/^version = "\([^"]*\)"$/\1/p' "$project_root/alire.toml")

if [ -z "$crate_name" ] || [ -z "$version" ]; then
  echo "could not read the crate name and version from alire.toml" >&2
  exit 1
fi
origin_commit=${2:-$(git -C "$project_root" rev-parse HEAD)}
case "$origin_commit" in
  *[!0-9a-f]* | '')
    echo "release origin must be a lowercase full commit ID" >&2
    exit 1
    ;;
esac
if [ "${#origin_commit}" -ne 40 ] ||
   [ "$(git -C "$project_root" rev-parse --verify "$origin_commit^{commit}" 2>/dev/null || true)" != "$origin_commit" ]; then
  echo "release origin must be a canonical full commit ID: $origin_commit" >&2
  exit 1
fi
git -C "$project_root" fetch --quiet origin main
if ! git -C "$project_root" merge-base --is-ancestor "$origin_commit" refs/remotes/origin/main; then
  echo "release origin is not reachable from public origin/main: $origin_commit" >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/flyology-json-release.XXXXXX")
cleanup() {
  rm -rf -- "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

verify_deployed_source() {
  expected_root=$1
  deployed_root=$2
  (
    cd "$expected_root"
    find . -type f -print | LC_ALL=C sort |
      while IFS= read -r relative_path; do
        if [ "$relative_path" = ./alire.toml ]; then
          continue
        fi
        if [ ! -f "$deployed_root/$relative_path" ] ||
           ! cmp -s "$relative_path" "$deployed_root/$relative_path" ||
           { [ -x "$relative_path" ] && [ ! -x "$deployed_root/$relative_path" ]; } ||
           { [ ! -x "$relative_path" ] && [ -x "$deployed_root/$relative_path" ]; }; then
          echo "deployed source differs from release origin: $relative_path" >&2
          exit 1
        fi
      done
  )
}

source_root="$temporary_root/source"
mkdir -p "$source_root"
git -C "$project_root" archive --format=tar "$origin_commit" | tar -xf - -C "$source_root"

if find "$source_root" -name alire.lock -o -name alire.lock.yaml | grep . >/dev/null; then
  echo "release archive contains a host-local Alire lock" >&2
  exit 1
fi
if grep -n '^\[\[pins\]\]' "$source_root/alire.toml" >/dev/null; then
  echo "release manifest contains a non-propagating pin" >&2
  exit 1
fi

echo "Testing source archive for $crate_name=$version at $origin_commit"
test_root="$temporary_root/test-source"
cp -R "$source_root" "$test_root"
(
  cd "$test_root"
  alr --non-interactive test
)

settings_root="$temporary_root/alire-settings"
mkdir -p "$settings_root"
index_source=${FLYOLOGY_ALIRE_INDEX_SOURCE:-https://github.com/flyology-ada/alire-index.git}
index_root="$temporary_root/index"
git clone --quiet "$index_source" "$index_root"
manifest_directory="$index_root/index/fl/$crate_name"
manifest_path="$manifest_directory/$crate_name-$version.toml"
expected_manifest="$temporary_root/$crate_name-$version.toml"
cp "$source_root/alire.toml" "$expected_manifest"
{
  printf '\n[origin]\n'
  printf 'commit = "%s"\n' "$origin_commit"
  printf 'url = "git+https://github.com/flyology-ada/flyology-json.git"\n'
} >>"$expected_manifest"

if [ "$mode" = candidate ]; then
  if [ -e "$manifest_path" ]; then
    if ! cmp -s "$expected_manifest" "$manifest_path"; then
      case "$version" in
        *-dev)
          # Development snapshots are identified by their exact indexed
          # origin.  Candidate mode may evaluate an authorized successor in
          # its temporary index clone; it never mutates the published index.
          cp "$expected_manifest" "$manifest_path"
          ;;
        *)
          echo "published stable manifest differs from the release candidate: $manifest_path" >&2
          exit 1
          ;;
      esac
    fi
  else
    mkdir -p "$manifest_directory"
    cp "$expected_manifest" "$manifest_path"
  fi
  (
    cd "$index_root"
    alr --non-interactive --settings="$settings_root" index --check
  )
  alr --non-interactive --settings="$settings_root" index --reset-community
  alr --non-interactive --settings="$settings_root" index \
    --add="file:$index_root" --name=release_candidate --before=community
  candidate_root="$temporary_root/candidate-downstream"
  mkdir -p "$candidate_root"
  (
    cd "$candidate_root"
    deployment=$(alr --non-interactive --settings="$settings_root" get --dirname "$crate_name=$version")
    alr --non-interactive --settings="$settings_root" get --only "$crate_name=$version"
    case "$deployment" in
      /*) deployed_root=$deployment ;;
      *) deployed_root="$candidate_root/$deployment" ;;
    esac
    verify_deployed_source "$source_root" "$deployed_root"
  )
  echo "Candidate index manifest passed: $manifest_path"
  exit 0
fi

if [ ! -f "$manifest_path" ] || ! cmp -s "$expected_manifest" "$manifest_path"; then
  echo "published manifest does not identify the reviewed release origin: $manifest_path" >&2
  exit 1
fi

alr --non-interactive --settings="$settings_root" index --reset-community
alr --non-interactive --settings="$settings_root" index \
  --add="git+$index_source" --name=flyology --before=community

downstream_root="$temporary_root/downstream"
mkdir -p "$downstream_root"
(
  cd "$downstream_root"
  deployment=$(alr --non-interactive --settings="$settings_root" get --dirname "$crate_name=$version")
  alr --non-interactive --settings="$settings_root" get "$crate_name=$version"
  case "$deployment" in
    /*) deployed_root=$deployment ;;
    *) deployed_root="$downstream_root/$deployment" ;;
  esac
  verify_deployed_source "$source_root" "$deployed_root"
  if grep -n '^\[\[pins\]\]' "$deployed_root/alire.toml" >/dev/null; then
    echo "indexed deployment contains a non-propagating pin" >&2
    exit 1
  fi
  cd "$deployed_root"
  alr --non-interactive --settings="$settings_root" test
)

echo "Fresh indexed solve passed for $crate_name=$version at $origin_commit"
