# TODO.AI.md

## script-lint violations in entrypoint.sh / functions/entrypoint.sh — FIXED

Flagged by `script-lint` 2026-08-21. Fixed at the upstream template source (per AI.md
non-negotiable rule #2 — generated files are never hand-tuned), then regenerated:
`/usr/local/share/CasjaysDev/scripts/templates/scripts/other/docker-entrypoint` (bare
`exit` → `exit 0` at 2 sites) and
`/usr/local/share/CasjaysDev/scripts/templates/scripts/functions/docker-entrypoint`
(missing `grep --` separator, 13 sites). `entrypoint.sh` and
`functions/entrypoint.sh` regenerated from the fixed templates via `gen-dockerfile
--dir <tmp> --nogit --template alpine --repo rust --org dockersrc` and copied forward.
`script-lint` re-run confirms all 19 original violations resolved.

A follow-up `script-lint` re-run surfaced 5 residuals in the same two upstream templates,
also now fixed:

- `other/docker-entrypoint`: `##@Version` header had no matching `VERSION=` assignment.
  Added `VERSION="GEN_SCRIPT_REPLACE_VERSION"` in the "Set bash options" block, and
  switched the header itself from a hardcoded date to the `GEN_SCRIPT_REPLACE_VERSION`
  placeholder (this template is `gen-script`-processed at generation time, so both now
  get stamped with the same timestamp — confirmed in the regenerated `entrypoint.sh`:
  header and `VERSION=` both read `202608211702-git`).
- `functions/docker-entrypoint`: `##@Version` header (202608030955-git) had no matching
  `VERSION=` assignment. Added `VERSION="202608030955-git"` (literal, matching the
  header) in a new "script variables" block after the shellcheck-disable header —
  this template is plain `cp`'d by `gen-dockerfile`, not `gen-script`-processed, so a
  `GEN_SCRIPT_REPLACE_VERSION` placeholder here would never get substituted and would
  ship broken in every generated repo.
- `functions/docker-entrypoint` line ~874 (x2): `$(dirname "$log_file")` → `${log_file%/*}`.
- `functions/docker-entrypoint` line ~992: `$(dirname "$create_env")` → `${create_env%/*}`.
- `functions/docker-entrypoint` line ~1106: `$(cat "$expected_pid_file" 2>/dev/null)` →
  `$(<"$expected_pid_file" 2>/dev/null)`.

`entrypoint.sh` and `functions/entrypoint.sh` regenerated again from the fixed templates
and copied forward. `script-lint` re-run confirms both files clean — 0 violations.

## GitHub API rate-limiting drops most cross tools on arm64 — CLOSED

Verified 2026-08-21, re-verified after fix: a pushed multi-platform build
(`docker.io/casjaysdev/rust:latest`, `linux/amd64,linux/arm64`) originally hit
unauthenticated GitHub API rate-limiting (60 req/hr) during the `rust-tools` stage's
`cargo binstall` tool loop, because both platforms build concurrently against the same
shared, unauthenticated budget.

Fix applied: `Dockerfile`'s `rust-tools` stage `cargo binstall` `RUN` now accepts an
optional BuildKit secret (`--mount=type=secret,id=github_token,env=GITHUB_TOKEN,
required=false`), matching the existing pattern in the sibling `go` image's Dockerfile.
The local build wrapper now supplies `--secret id=github_token,env=GITHUB_ACCESS_TOKEN`
on the real `docker buildx build` invocation (confirmed via `pgrep -af`).

**Confirmed resolved:** a fresh, wrapper-invoked, `--no-cache` multi-platform build
(runtime 1h37m) produced **0** `403 Forbidden` errors across the full build log
(`grep -c '403 Forbidden' /root/.local/log/buildx/docker.io/casjaysdev/rust/all.log` → 0).

## Tool-inventory gap — final status

Raw `command -v` check against the fixed, pushed image originally reported 12 tools
"MISSING" on amd64. Manual verification found 6 were false positives (crate name ≠
binary name) and 6 were genuine gaps. All genuine gaps have now been investigated and
either fixed or root-caused:

**False positives (no fix needed, binary confirmed working under its real name):**
`cargo-edit`→`cargo-add`/`cargo-rm`/`cargo-upgrade`/`cargo-set-version`,
`cargo-update`→`cargo-install-update`, `typos-cli`→`typos`, `taplo-cli`→`taplo`,
`wasm-bindgen-cli`→`wasm-bindgen`, `cargo-binutils`→`cargo-nm`/`cargo-objdump`/
`cargo-size`/`cargo-strip`.

**Fixed this session:**
- `cargo-public-api`, `cargo-dist`, `sea-orm-cli` — root cause: these 3 crates have no
  musl prebuilt (any platform) and fall through to the compile-fallback loop, where
  linking failed with `cannot find -lssl` / `cannot find -lcrypto`. Alpine's
  `openssl-dev` package ships only the shared libs; static linking against musl needs
  `openssl-libs-static` for `libssl.a`/`libcrypto.a`. Reproduced and fixed in a
  standalone debug container (`rust:alpine`, manual `apk add openssl-libs-static`), then
  confirmed all 3 now `cargo binstall -y` successfully (exit 0). Fix applied: added
  `RUN apk add --no-cache openssl-dev openssl-libs-static pkgconfig` immediately before
  the compile-fallback loop in `Dockerfile`.
- `probe-rs` — root cause: wrong crate name in the tool list. The `probe-rs` crate is a
  library with no installable binary (`cargo binstall` error: "no binaries specified nor
  inferred"); the CLI binaries (`probe-rs`, `cargo-flash`, `cargo-embed`) are published
  under the `probe-rs-tools` crate, which **does** have a musl prebuilt via QuickInstall
  (installs in ~2s, no compile needed). Fix applied: changed `probe-rs` → `probe-rs-tools`
  in the main prebuilt-fetch loop and removed it from the compile-fallback loop (no
  longer needed there).

**Genuine remaining limitation — documented, not fixed:**
- `cargo-spellcheck` — no musl prebuilt; compile-fallback fails. Root cause is deeper
  than a missing package: after installing `openssl-libs-static`, `g++`, and
  `clang22-libclang` (to satisfy successive `cc`/`c++`/`libclang.so` errors), the build
  still fails — the `hunspell-sys` dependency's build script
  (`hunspell-sys-*/build-script-build`) crashes with `SIGSEGV` (signal 11) while
  compiling the vendored C++ `hunspell` library, not a missing-dependency error. This is
  a crash inside a third-party build script under this musl cross-compile environment,
  not something fixable with an `apk add` line; not pursued further given the size of
  the additional dependencies required (`llvm`/`clang` ~480MiB in the intermediate stage
  alone) for a tool that still doesn't build. Left in the compile-fallback loop with
  `|| true` — will keep silently skipping on every build until upstream `hunspell-sys`
  or `cargo-spellcheck` fixes the underlying crash.

## mingw-w64-gcc has no arm64 Alpine package

Verified 2026-08-21 in the same build: `apk add --no-cache mingw-w64-gcc` succeeded on
`linux/amd64` (installed `mingw-w64-gcc-15.2.0-r0`) but failed with `ERROR: unable to
select packages: mingw-w64-gcc (no such package)` on `linux/arm64`. The install is wrapped
in `|| true` in `rootfs/root/docker/setup/05-custom.sh`, so the build doesn't fail, but the
`linux/arm64` variant of this image has the `x86_64-pc-windows-gnu` / `i686-pc-windows-gnu`
rustup targets registered with no working `x86_64-w64-mingw32-gcc` / `i686-w64-mingw32-gcc`
linker — `cargo build --target x86_64-pc-windows-gnu` will fail to link on that platform.
This is an Alpine package-availability limitation (mingw-w64-gcc is not published for
aarch64 in the Alpine repos as of this check), not a bug in this repo's scripts. No
in-repo fix available; document as a known limitation if not already covered by README's
existing Windows-MSVC/macOS-SDK caveats section.

**Workaround tested and failed:** `cargo zigbuild --target x86_64-pc-windows-gnu` was
tried on the arm64 image as a substitute cross-linker (zig is already used elsewhere in
this Dockerfile for musl cross-linking). It compiled the test crate but failed at link
time: `error: linking with .../zigcc-x86_64-pc-windows-gnu-*.sh failed: exit status: 1`,
no `.exe` produced (full log: `/tmp/zigbuild_test.log`, not preserved in-repo). Not a
working substitute — the arm64 `mingw-w64-gcc` limitation remains open with no known
workaround.
