# TODO.AI.md

## GitHub API rate-limiting drops most cross tools on arm64

Verified 2026-08-21: a pushed multi-platform build (`docker.io/casjaysdev/rust:latest`,
`linux/amd64,linux/arm64`) hit unauthenticated GitHub API rate-limiting (60 req/hr) during
the `rust-tools` stage's `cargo binstall` tool loop, because both platforms build
concurrently against the same shared, unauthenticated budget.

Verified tool inventory in the pushed image:

- `linux/amd64`: 14 of 60 tools missing (`cargo-edit`, `cargo-update`, `typos-cli`,
  `taplo-cli`, `wasm-bindgen-cli`, `cargo-binutils`, `cargo-public-api`,
  `cargo-spellcheck`, `cargo-dist`, `cargo-fuzz`, `flamegraph`, `probe-rs`, `sqlx-cli`,
  `sea-orm-cli`)
- `linux/arm64`: 40 of 60 tools missing (nearly the whole list, cascading from
  `cargo-binstall` itself onward once the rate limit was exhausted)

Fix applied in this session: `Dockerfile`'s `rust-tools` stage `cargo binstall` `RUN` now
accepts an optional BuildKit secret (`--mount=type=secret,id=github_token,env=GITHUB_TOKEN,
required=false`), matching the existing pattern already present in the sibling `go` image's
Dockerfile. This raises the GitHub API rate limit from 60 to 5000 req/hr when a token is
supplied.

**Still open — outside this repo's scope:** the local build wrapper
(`/usr/local/bin/buildx` → `/usr/local/share/CasjaysDev/scripts/bin/buildx`, a shared
CasjaysDev script, not owned by this repo) does not pass `--secret id=github_token,
env=GITHUB_TOKEN` on any `docker buildx build` invocation it generates — confirmed by
grepping the saved build command in `/root/.config/myscripts/buildx/scripts/casjaysdev/
rust-latest.sh`. Until that wrapper is updated (or the build is invoked manually with the
secret flag), this Dockerfile fix has no effect and future pushed builds will keep hitting
the same rate limit. This also affects the `go` image, which has carried the same
secret-mount plumbing without the wrapper ever supplying it.

Needs a decision from the user: fix the shared wrapper script (affects all dockersrc/
casjaysdevdocker image builds, not just this repo), or accept manual
`--secret id=github_token,env=GITHUB_TOKEN` invocation for now.

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
