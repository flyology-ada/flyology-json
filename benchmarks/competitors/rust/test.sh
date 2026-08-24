#!/bin/sh
# Copyright (c) 2026 Yurii Rashkovskii
# SPDX-License-Identifier: MIT OR Apache-2.0

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

if [ "$#" -gt 1 ]; then
  echo "usage: ./test.sh [portable|native]" >&2
  exit 2
fi

tuning=${1:-${FLYOLOGY_JSON_BENCH_TUNING:-portable}}
if [ "$#" -eq 1 ] && [ -n "${FLYOLOGY_JSON_BENCH_TUNING:-}" ] && \
   [ "$1" != "$FLYOLOGY_JSON_BENCH_TUNING" ]; then
  echo "track argument conflicts with FLYOLOGY_JSON_BENCH_TUNING" >&2
  exit 2
fi
target_dir="$script_dir/target/$tuning"
cargo_home="$target_dir/cargo-home"

if env | grep -Eq '^(RUSTFLAGS|CARGO_ENCODED_RUSTFLAGS|RUSTC|RUSTC_WRAPPER|RUSTC_WORKSPACE_WRAPPER|CARGO_BUILD_|CARGO_PROFILE_|CARGO_TARGET_|CC|CXX|AR|CFLAGS|CXXFLAGS)(_|=)'; then
  echo "unreviewed compiler or Cargo build environment is set" >&2
  exit 2
fi

repository_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
config_directory=$script_dir
while :; do
  for config_name in config config.toml; do
    if [ -e "$config_directory/.cargo/$config_name" ]; then
      echo "unreviewed Cargo configuration: $config_directory/.cargo/$config_name" >&2
      exit 2
    fi
  done
  if [ "$config_directory" = "$repository_root" ]; then
    break
  fi
  config_directory=$(dirname -- "$config_directory")
done

mkdir -p "$cargo_home"
case "$tuning" in
  portable)
    run_cargo() {
      env -u RUSTFLAGS -u CARGO_ENCODED_RUSTFLAGS \
        CARGO_HOME="$cargo_home" CARGO_TARGET_DIR="$target_dir" cargo "$@"
    }
    effective_rustflags="<cleared>"
    ;;
  native)
    run_cargo() {
      env -u RUSTFLAGS -u CARGO_ENCODED_RUSTFLAGS \
        CARGO_HOME="$cargo_home" CARGO_TARGET_DIR="$target_dir" \
        RUSTFLAGS=-Ctarget-cpu=native cargo "$@"
    }
    effective_rustflags="-Ctarget-cpu=native"
    ;;
  *)
    echo "FLYOLOGY_JSON_BENCH_TUNING must be portable or native" >&2
    exit 2
    ;;
esac

printf 'track=%s\n' "$tuning"
printf 'rustflags=%s\n' "$effective_rustflags"
rustc --version --verbose
cargo --version
cc --version | sed -n '1p'
uname -a

run_cargo fetch --locked
env CARGO_HOME="$cargo_home" ./audit-licenses.sh

(
  cd ../../comparison
  npm run validate:capabilities
)

run_cargo build --release --locked --verbose
run_cargo test --release --locked --verbose

case "$(uname -s)" in
  Linux)
    cc -std=c11 -Wall -Wextra -Werror \
      -Iinclude \
      tests/abi_smoke.c \
      "$target_dir/release/libflyology_json_rust_bench_adapters.a" \
      -ldl -lpthread -lm \
      -o "$target_dir/release/rust-bench-abi-smoke"
    ;;
  Darwin)
    cc -std=c11 -Wall -Wextra -Werror \
      -Iinclude \
      tests/abi_smoke.c \
      "$target_dir/release/libflyology_json_rust_bench_adapters.a" \
      -o "$target_dir/release/rust-bench-abi-smoke"
    ;;
  *)
    echo "unsupported Rust ABI smoke-test host: $(uname -s)" >&2
    exit 2
    ;;
esac

"$target_dir/release/rust-bench-abi-smoke"

(
  cd ../..
  env RUST_ADAPTER_DIR="$target_dir/release" \
    alr exec -- gprbuild -f -p -P competitors/rust/rust_adapter_tests.gpr
)

"$script_dir/target/ada_bin/flyology_json-benchmark_rust_tests"
