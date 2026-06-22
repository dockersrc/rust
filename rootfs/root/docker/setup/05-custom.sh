#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202605311104-git
# @@Author           :  CasjaysDev
# @@Contact          :  CasjaysDev <docker-admin@casjaysdev.pro>
# @@License          :  MIT
# @@Copyright        :  Copyright 2026 CasjaysDev
# @@Created          :  Sun May 31 11:04:50 AM EDT 2026
# @@File             :  05-custom.sh
# @@Description      :  Install latest stable Rust toolchain with static-build tooling
# @@Changelog        :  newScript
# @@Other            :  N/A
# @@Resource         :  N/A
# @@Terminal App     :  yes
# @@sudo/root        :  yes
# @@Template         :  templates/dockerfiles/init_scripts/05-custom.sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set bash options
set -o pipefail
[ "$DEBUGGER" = "on" ] && echo "Enabling debugging" && set -x$DEBUGGER_OPTIONS
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set env variables
exitCode=0

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Predefined actions

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Main script

# Install C/C++ toolchain and static-build dependencies needed by Rust -sys crates
pkmgr install build-base musl-dev clang clang-dev llvm-dev lld cmake make perl openssl-dev openssl-libs-static pkgconf gdb

# Install cross-compile toolchains — failures are non-fatal on minimal mirrors
pkmgr install mingw-w64-gcc || true

# Install zig for cargo-zigbuild (C-dep cross-compilation without a sysroot)
pkmgr install zig || true

# Install binaryen (wasm-opt) for WASM size optimisation tooling
pkmgr install binaryen || true

# Install Linux perf — required by flamegraph and samply to record profiles;
# non-fatal because availability depends on the host kernel and Alpine mirror
pkmgr install perf || true

# - - - - - - - - - - - - - - - - - - - - - - - - -
# rustup paths — match the official rust:alpine convention so existing
# workflows work unchanged; volumes are declared at these paths in the Dockerfile
export RUSTUP_HOME="/usr/local/share/rustup"
export CARGO_HOME="/usr/local/share/cargo"
export PATH="$CARGO_HOME/bin:$PATH"

mkdir -p "$RUSTUP_HOME" "$CARGO_HOME/bin"

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Download the architecture-appropriate rustup-init and verify its SHA256
# before executing — this is the only thing that ever touches rust-lang.org
# directly; all subsequent installs go through rustup or cargo-binstall
RUSTUP_ARCH="$(uname -m)-unknown-linux-musl"
RUSTUP_URL="https://static.rust-lang.org/rustup/dist/${RUSTUP_ARCH}/rustup-init"

curl -sSfL "$RUSTUP_URL" -o /tmp/rustup-init
curl -sSfL "${RUSTUP_URL}.sha256" -o /tmp/rustup-init.sha256

EXPECTED_SHA="$(awk '{print $1}' /tmp/rustup-init.sha256)"
ACTUAL_SHA="$(sha256sum /tmp/rustup-init | awk '{print $1}')"
[ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] || {
  echo "rustup-init SHA256 mismatch: expected $EXPECTED_SHA got $ACTUAL_SHA" >&2
  exit 1
}
chmod +x /tmp/rustup-init

# Install the latest stable toolchain; --profile default includes rustfmt and clippy
/tmp/rustup-init -y --no-modify-path \
  --default-toolchain stable \
  --profile default

rm -f /tmp/rustup-init /tmp/rustup-init.sha256

# Add components not included in the default profile
rustup component add rust-src rust-analyzer llvm-tools-preview

# Nightly toolchain for miri and other unstable tooling; minimal profile
# keeps the download small — only the compiler and std/src are pulled in
rustup toolchain install nightly --profile minimal --component miri --component rust-src

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Cross-compile targets — Linux musl (fully static, no libc dependency)
rustup target add \
  x86_64-unknown-linux-musl \
  aarch64-unknown-linux-musl \
  i686-unknown-linux-musl \
  armv7-unknown-linux-musleabihf \
  riscv64gc-unknown-linux-musl

# Cross-compile targets — Linux glibc
rustup target add \
  x86_64-unknown-linux-gnu \
  aarch64-unknown-linux-gnu \
  i686-unknown-linux-gnu \
  armv7-unknown-linux-gnueabihf \
  arm-unknown-linux-gnueabi \
  riscv64gc-unknown-linux-gnu \
  powerpc64le-unknown-linux-gnu \
  s390x-unknown-linux-gnu

# Cross-compile targets — Windows GNU ABI (MSVC ABI is not supported)
rustup target add \
  x86_64-pc-windows-gnu \
  i686-pc-windows-gnu \
  aarch64-pc-windows-gnullvm

# Cross-compile targets — macOS (pure-Rust only; Apple SDK not bundled)
rustup target add \
  x86_64-apple-darwin \
  aarch64-apple-darwin

# Cross-compile targets — BSD
rustup target add \
  x86_64-unknown-freebsd

# Cross-compile targets — WebAssembly
rustup target add \
  wasm32-unknown-unknown \
  wasm32-wasip1 \
  wasm32-wasip2 \
  wasm32-unknown-emscripten

# Cross-compile targets — Embedded ARM (require no_std source)
rustup target add \
  thumbv6m-none-eabi \
  thumbv7em-none-eabihf \
  thumbv8m.main-none-eabi

# Cross-compile targets — Embedded RISC-V (require no_std source)
rustup target add \
  riscv32imc-unknown-none-elf \
  riscv32imac-unknown-none-elf

# Cross-compile targets — Android
rustup target add \
  aarch64-linux-android

# - - - - - - - - - - - - - - - - - - - - - - - - -
# All Rust tool binaries (cargo-edit, cargo-deny, sqlx-cli, sea-orm-cli, probe-rs,
# sccache, etc.) are compiled natively in the Dockerfile's rust-tools stage and
# copied to $CARGO_HOME/bin before this script runs — no cargo install here.
# The symlink loop below picks them all up.

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Linker configuration for cross-compilation targets.
# rust-lld handles ARM/RISC-V/embedded; mingw-w64 gcc handles Windows GNU.
mkdir -p "$CARGO_HOME"
cat > "$CARGO_HOME/config.toml" << 'CARGOCONFIG'
[target.aarch64-unknown-linux-musl]
linker = "rust-lld"

[target.armv7-unknown-linux-musleabihf]
linker = "rust-lld"

[target.armv7-unknown-linux-gnueabihf]
linker = "rust-lld"

[target.arm-unknown-linux-gnueabi]
linker = "rust-lld"

[target.thumbv6m-none-eabi]
linker = "rust-lld"

[target.thumbv7em-none-eabihf]
linker = "rust-lld"

[target.thumbv8m.main-none-eabi]
linker = "rust-lld"

[target.riscv32imc-unknown-none-elf]
linker = "rust-lld"

[target.riscv32imac-unknown-none-elf]
linker = "rust-lld"

[target.x86_64-pc-windows-gnu]
linker = "x86_64-w64-mingw32-gcc"
ar = "x86_64-w64-mingw32-ar"

[target.i686-pc-windows-gnu]
linker = "i686-w64-mingw32-gcc"
ar = "i686-w64-mingw32-ar"
CARGOCONFIG

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Symlink every cargo/bin tool into /usr/local/bin so they are reachable
# without a login shell — the Dockerfile's PATH includes /usr/local/bin
for bin_file in "$CARGO_HOME/bin"/*; do
  [ -x "$bin_file" ] || continue
  ln -sf "$bin_file" "/usr/local/bin/${bin_file##*/}"
done

# Home-relative symlinks expected by rustup, cargo, and most documentation
ln -sf "$CARGO_HOME" "/root/.cargo"
ln -sf "$RUSTUP_HOME" "/root/.rustup"

# Profile.d entry so login shells get the full environment
cat > /etc/profile.d/rust.sh << PROFILE
export RUSTUP_HOME="${RUSTUP_HOME}"
export CARGO_HOME="${CARGO_HOME}"
export RUSTUP_TOOLCHAIN="stable"
export PATH="${CARGO_HOME}/bin:\${PATH}"
if command -v sccache > /dev/null 2>&1; then
  export SCCACHE_DIR="\${SCCACHE_DIR:-/root/.cache/sccache}"
  export RUSTC_WRAPPER="\${RUSTC_WRAPPER:-sccache}"
fi
export CARGO_INCREMENTAL="\${CARGO_INCREMENTAL:-0}"
PROFILE

# Work directories mounted or referenced in the README
mkdir -p /app /work /root/app /root/project /data/build /root/.cache/sccache

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the exit code
exitCode=$?
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit $exitCode
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
