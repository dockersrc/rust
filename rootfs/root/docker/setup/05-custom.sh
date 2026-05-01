#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202604221922-git
# @@Author           :  CasjaysDev
# @@Contact          :  CasjaysDev <docker-admin@casjaysdev.pro>
# @@License          :  MIT
# @@Copyright        :  Copyright 2026 CasjaysDev
# @@Created          :  Wed Apr 22 07:22:57 PM EDT 2026
# @@File             :  05-custom.sh
# @@Description      :  script to run custom
# @@Changelog        :  newScript
# @@TODO             :  Refactor code
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

# Install Rust developer tools into $CARGO_HOME/bin (which is on PATH
# via the symlinks created in 02-packages.sh).
#
# Strategy: bootstrap `cargo-binstall` first via its upstream installer
# script, then use it for everything else. binstall fetches prebuilt
# binaries when the upstream crate publishes them and falls back to a
# normal `cargo install` otherwise - dramatically faster than
# source-compiling 30+ tools sequentially.
export CARGO_HOME="${CARGO_HOME:-/usr/local/share/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/share/rustup}"
export PATH="${CARGO_HOME}/bin:${PATH}"
mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"

if command -v cargo >/dev/null 2>&1; then
  echo "Installing Rust developer tools with $(rustc --version)"

  # cargo-binstall: bootstrap via `cargo install`. Compiles from
  # crates.io (~3-5 min cold) but avoids the upstream install script's
  # curl-pipe-to-bash, which has been observed to fail with TLS SAN
  # errors when fetching the prebuilt binary from github.com inside
  # certain build environments. Slower but bulletproof.
  cargo install cargo-binstall --locked \
    || echo "  WARN: cargo-binstall bootstrap failed - falling through" >&2

  # Use binstall for the remainder. --no-confirm skips prompts;
  # --locked uses each crate's checked-in Cargo.lock for reproducibility;
  # binstall transparently falls back to `cargo install` when no
  # prebuilt binary is available.
  for tool in \
    cargo-edit \
    cargo-watch \
    cargo-update \
    cargo-outdated \
    cargo-expand \
    cargo-info \
    cargo-nextest \
    cargo-llvm-cov \
    cargo-tarpaulin \
    cargo-mutants \
    cargo-audit \
    cargo-deny \
    cargo-machete \
    cargo-msrv \
    cargo-semver-checks \
    cargo-make \
    cargo-deb \
    cargo-generate \
    cargo-release \
    cargo-dist \
    cargo-chef \
    cargo-zigbuild \
    cargo-flamegraph \
    bacon \
    mdbook \
    mdbook-toc \
    wasm-pack \
    wasm-bindgen-cli \
    wasm-tools \
    sqlx-cli \
    sea-orm-cli \
    trunk \
    samply \
    just \
    tokei \
    hyperfine \
    cargo-binutils \
    cargo-cross \
    flip-link \
    probe-rs-tools \
    cargo-ndk \
    cbindgen \
    cargo-bloat \
    cargo-asm \
    ; do
    echo "cargo binstall $tool"
    # Best-effort: skip individual tool failures rather than aborting
    # the whole build. binstall falls back to `cargo install` when no
    # prebuilt is available; if both fail (stale deps, etc.), warn
    # and move on.
    cargo binstall --no-confirm --locked "$tool" \
      || echo "  WARN: skipping $tool (install failed)" >&2
  done

  # Re-link any newly installed cargo-* binaries into /usr/local/bin so
  # they're discoverable for non-login `docker exec` invocations.
  for bin in "${CARGO_HOME}"/bin/*; do
    [ -e "$bin" ] || continue
    name="$(basename "$bin")"
    [ -e "/usr/local/bin/${name}" ] || ln -sf "$bin" "/usr/local/bin/${name}"
  done
  unset bin name

  # Drop the registry cache + git checkouts; they balloon the image and
  # get rehydrated on first `cargo build` against a real volume.
  rm -rf "${CARGO_HOME}/registry" "${CARGO_HOME}/git" 2>/dev/null || true
else
  echo "cargo binary not found; skipping Rust dev tools" >&2
fi

# Always succeed: tool installation is best-effort, the build environment
# is functional even if some optional dev tools didn't make it. The
# rustup toolchain itself was already verified by 02-packages.sh.
exit 0
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
