#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202604221922-git
# @@Author           :  CasjaysDev
# @@Contact          :  CasjaysDev <docker-admin@casjaysdev.pro>
# @@License          :  MIT
# @@Copyright        :  Copyright 2026 CasjaysDev
# @@Created          :  Wed Apr 22 07:22:56 PM EDT 2026
# @@File             :  02-packages.sh
# @@Description      :  script to run packages
# @@Changelog        :  newScript
# @@TODO             :  Refactor code
# @@Other            :  N/A
# @@Resource         :  N/A
# @@Terminal App     :  yes
# @@sudo/root        :  yes
# @@Template         :  templates/dockerfiles/init_scripts/02-packages.sh
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

# Install the latest stable Rust toolchain via the official rustup-init
# bootstrapper. CARGO_HOME and RUSTUP_HOME are pinned to /usr/local/share
# so the toolchain lives in a system path that's easy to volume-mount
# and shareable across users (vs the default ~/.cargo, ~/.rustup).
#
# Wrapped in a subshell with `set -euo pipefail` so any single step
# (curl, sha256sum, rustup, rustup target add, ...) that fails aborts
# the whole installer and the parent script returns non-zero - the
# Dockerfile then fails the build rather than silently producing a
# broken image.
(
  set -euo pipefail

  export CARGO_HOME="/usr/local/share/cargo"
  export RUSTUP_HOME="/usr/local/share/rustup"
  mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"

  case "$(uname -m)" in
    x86_64)   RUST_ARCH="x86_64-unknown-linux-musl";  RUSTUP_ARCH="x86_64-unknown-linux-musl" ;;
    aarch64)  RUST_ARCH="aarch64-unknown-linux-musl"; RUSTUP_ARCH="aarch64-unknown-linux-musl" ;;
    armv7l)   RUST_ARCH="armv7-unknown-linux-musleabihf"; RUSTUP_ARCH="armv7-unknown-linux-musleabihf" ;;
    i686|i386) RUST_ARCH="i686-unknown-linux-musl";   RUSTUP_ARCH="i686-unknown-linux-musl" ;;
    ppc64le)  RUST_ARCH="powerpc64le-unknown-linux-gnu"; RUSTUP_ARCH="powerpc64le-unknown-linux-gnu" ;;
    s390x)    RUST_ARCH="s390x-unknown-linux-gnu";    RUSTUP_ARCH="s390x-unknown-linux-gnu" ;;
    riscv64)  RUST_ARCH="riscv64gc-unknown-linux-gnu"; RUSTUP_ARCH="riscv64gc-unknown-linux-gnu" ;;
    *)
      echo "Unsupported architecture for rustup install: $(uname -m)" >&2
      exit 1
      ;;
  esac

  # Pull rustup-init from the official static.rust-lang.org distribution
  # point. The script form (sh.rustup.rs) is a thin wrapper that does
  # exactly this; we go direct so we can SHA256-verify the binary.
  RUSTUP_INIT_URL="https://static.rust-lang.org/rustup/dist/${RUSTUP_ARCH}/rustup-init"
  RUSTUP_SHA_URL="${RUSTUP_INIT_URL}.sha256"
  echo "Fetching rustup-init for ${RUSTUP_ARCH}"
  curl -fsSL "$RUSTUP_INIT_URL" -o /tmp/rustup-init
  RUSTUP_SHA256="$(curl -fsSL "$RUSTUP_SHA_URL" | awk '{print $1}')"
  if [ -z "$RUSTUP_SHA256" ]; then
    echo "Failed to fetch rustup-init SHA256 from $RUSTUP_SHA_URL" >&2
    exit 1
  fi
  echo "${RUSTUP_SHA256}  /tmp/rustup-init" | sha256sum -c -
  chmod +x /tmp/rustup-init

  echo "Installing stable Rust toolchain via rustup"
  # --component accepts comma-separated values; passing space-separated
  # makes clap take only the first as the value and treat the rest as
  # stray positional args (which fails with "unexpected argument").
  /tmp/rustup-init -y \
    --no-modify-path \
    --default-toolchain stable \
    --profile minimal \
    --default-host "$RUSTUP_ARCH" \
    --component rustfmt,clippy,rust-src,rust-analyzer,llvm-tools-preview
  rm -f /tmp/rustup-init

  # Expose rustc/cargo/rustup/rustfmt/clippy on /usr/local/bin so they
  # work without the profile.d export (e.g. one-shot `docker run ... cargo build`).
  for bin in rustc cargo rustup rustfmt cargo-fmt cargo-clippy clippy-driver rust-analyzer rust-gdb rust-lldb; do
    if [ -e "${CARGO_HOME}/bin/${bin}" ]; then
      ln -sf "${CARGO_HOME}/bin/${bin}" "/usr/local/bin/${bin}"
    fi
  done

  # rust-lld lives inside the toolchain's rustlib dir (shipped via the
  # llvm-tools-preview component). Putting it on PATH lets the cargo
  # config.toml `linker = "rust-lld"` overrides resolve - this enables
  # plain `cargo build --target=...` to work for ARM/aarch64 musl and
  # bare-metal embedded targets without an external C cross-toolchain.
  RUST_LLD="$(rustc --print sysroot)/lib/rustlib/${RUSTUP_ARCH}/bin/rust-lld"
  if [ -e "$RUST_LLD" ]; then
    ln -sf "$RUST_LLD" /usr/local/bin/rust-lld
  fi

  # Pre-install Rust std for a broad cross-compile matrix. Each target
  # adds ~50-150MB; the full set below expands the image by ~2-3GB but
  # gives "Go-style" cross-compile turn-key support out of the box.
  # Pair with cargo-zigbuild (installed in 05-custom.sh) for the C side
  # of any *-sys / build.rs cross builds.
  for target in \
    x86_64-unknown-linux-gnu \
    x86_64-unknown-linux-musl \
    aarch64-unknown-linux-gnu \
    aarch64-unknown-linux-musl \
    i686-unknown-linux-gnu \
    i686-unknown-linux-musl \
    armv7-unknown-linux-gnueabihf \
    armv7-unknown-linux-musleabihf \
    arm-unknown-linux-gnueabihf \
    riscv64gc-unknown-linux-gnu \
    riscv64gc-unknown-linux-musl \
    powerpc64le-unknown-linux-gnu \
    s390x-unknown-linux-gnu \
    x86_64-pc-windows-gnu \
    i686-pc-windows-gnu \
    aarch64-pc-windows-gnullvm \
    x86_64-apple-darwin \
    aarch64-apple-darwin \
    x86_64-unknown-freebsd \
    wasm32-unknown-unknown \
    wasm32-wasip1 \
    wasm32-wasip2 \
    wasm32-unknown-emscripten \
    thumbv6m-none-eabi \
    thumbv7em-none-eabihf \
    thumbv8m.main-none-eabihf \
    riscv32imc-unknown-none-elf \
    riscv32imac-unknown-none-elf \
    aarch64-linux-android \
    ; do
    echo "rustup target add $target"
    rustup target add "$target" || true
  done

  # Sanity-check the install before subsequent setup steps depend on it.
  /usr/local/bin/rustc --version
  /usr/local/bin/cargo --version
  rustup target list --installed

  # Trim docs that the toolchain ships - we don't need them inside a
  # build container (saves ~150MB across all installed toolchains).
  rm -rf "${RUSTUP_HOME}/toolchains"/*/share/doc \
         "${RUSTUP_HOME}/toolchains"/*/share/man || true
)
__rust_install_rc=$?
# Note: this is intentionally a separate statement, not `(...) || exit`.
# Bash silently disables `set -e` inside an explicit subshell when the
# subshell appears on the left of && or ||, so the form below is the
# only reliable way to propagate set -e failures from the subshell.
if [ "$__rust_install_rc" -ne 0 ]; then
  exit "$__rust_install_rc"
fi
unset __rust_install_rc

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the exit code
#exitCode=$?
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit $exitCode
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
