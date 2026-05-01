# Rust environment - sourced by /etc/profile for interactive login shells.
#
# All Rust state lives under /usr/local/share/cargo (registry, target
# cache, user-installed cargo binaries) and /usr/local/share/rustup
# (toolchains and components), both declared as Docker VOLUMEs. The
# paths /root/.cargo, /root/.rustup, /data/cargo, /data/rustup are
# symlinks to these locations so any of them can be used interchangeably
# and the data persists across container rebuilds with named volumes.

export CARGO_HOME="${CARGO_HOME:-/usr/local/share/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/share/rustup}"
export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"

case ":${PATH}:" in
  *":${CARGO_HOME}/bin:"*) ;;
  *) export PATH="${CARGO_HOME}/bin:${PATH}" ;;
esac
