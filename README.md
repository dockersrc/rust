## 👋 Welcome to rust 🚀  

A Docker image for building Rust projects. Installs the latest stable
Rust toolchain via the official `rustup-init` bootstrapper at image
build time (SHA256-verified from `static.rust-lang.org`) so the image
is never behind upstream. Includes 30 pre-installed cross-compile
targets and a comprehensive set of cargo dev tools, plus the common
build deps (git, make, build-base, clang, lld, mingw-w64, zig, cmake,
perl, openssl-dev, protobuf, jq, binaryen, wabt).

The image is a build environment — it idles after init so you can
`docker exec` into it or use `docker compose exec` for one-off `cargo
build`, `cargo test`, `cargo clippy`, etc.

### What's included

- **Toolchain components** (via rustup): rustfmt, clippy, rust-src,
  rust-analyzer, llvm-tools-preview
- **Workflow**: cargo-binstall, cargo-edit, cargo-watch, cargo-update,
  cargo-outdated, cargo-expand, cargo-info, bacon
- **Test / coverage / mutation**: cargo-nextest, cargo-llvm-cov,
  cargo-tarpaulin, cargo-mutants
- **QA / audit / policy**: cargo-audit, cargo-deny, cargo-machete,
  cargo-msrv, cargo-semver-checks
- **Build / packaging / release**: cargo-make, cargo-deb, cargo-generate,
  cargo-release, cargo-dist, cargo-chef, cargo-zigbuild, just
- **Docs**: mdbook, mdbook-toc
- **WASM**: wasm-pack, wasm-bindgen-cli, wasm-tools, trunk
- **Cross / embedded**: cargo-binutils, cargo-cross, flip-link,
  probe-rs, cargo-ndk, cbindgen
- **Profiling / inspection**: samply, cargo-bloat, cargo-asm
- **DB migrations / ORMs**: sqlx-cli, sea-orm-cli *(best-effort —
  may need manual install with project-specific feature flags)*
- **Misc**: tokei, hyperfine, cargo-flamegraph

  
## Install my system scripts  

```shell
 sudo bash -c "$(curl -q -LSsf "https://github.com/systemmgr/installer/raw/main/install.sh")"
 sudo systemmgr --config && sudo systemmgr install scripts  
```
  
## Automatic install/update  
  
```shell
dockermgr update rust
```
  
## Install and run container
  
```shell
dockerHome="/var/lib/srv/$USER/docker/casjaysdevdocker/rust/rust/latest/volumes"
mkdir -p "/var/lib/srv/$USER/docker/rust/volumes"
git clone "https://github.com/dockermgr/rust" "$HOME/.local/share/CasjaysDev/dockermgr/rust"
cp -Rfva "$HOME/.local/share/CasjaysDev/dockermgr/rust/rootfs/." "$dockerHome/"
docker run -d \
--restart always \
--privileged \
--name casjaysdevdocker-rust-latest \
--hostname rust \
-e TZ=${TIMEZONE:-America/New_York} \
-v "$dockerHome/data:/data:z" \
-v "$dockerHome/config:/config:z" \
casjaysdevdocker/rust:latest
```
  
## via docker-compose  
  
```yaml
version: "2"
services:
  ProjectName:
    image: casjaysdevdocker/rust
    container_name: casjaysdevdocker-rust
    environment:
      - TZ=America/New_York
      - HOSTNAME=rust
    volumes:
      - "/var/lib/srv/$USER/docker/casjaysdevdocker/rust/rust/latest/volumes/data:/data:z"
      - "/var/lib/srv/$USER/docker/casjaysdevdocker/rust/rust/latest/volumes/config:/config:z"
    restart: always
```
  
## Usage

The container idles after init. Use `docker exec` (or `docker compose
exec`) to run cargo commands against a project mounted into the
container, or do a one-shot build with `docker run --rm`:

```shell
# one-off build (mount your project at /app)
docker run --rm -it \
  -v "$PWD:/app" \
  -w /app \
  casjaysdevdocker/rust:latest \
  bash -lc 'cargo build --release'

# interactive dev shell
docker run --rm -it \
  -v "$PWD:/app" \
  -w /app \
  casjaysdevdocker/rust:latest \
  bash -l

# exec into the long-running container
docker exec -it casjaysdevdocker-rust-latest bash -l
docker exec casjaysdevdocker-rust-latest cargo test
docker exec casjaysdevdocker-rust-latest cargo clippy --all-targets
docker exec casjaysdevdocker-rust-latest cargo nextest run
```

`WORKDIR` inside the image is `/app`. Project code can also be mounted
at `/work`, `/root/app`, `/root/project`, or `/data/build` — all are
created on startup.

## Cross-compile

A pre-configured `$CARGO_HOME/config.toml` ships with the image. It
points cross-compile linkers at `rust-lld` (for ARM/aarch64/embedded)
or `*-w64-mingw32-gcc` (for Windows GNU), so plain `cargo build
--target=...` works for **pure-Rust** crates against most targets out
of the box:

```shell
cargo build --release --target aarch64-unknown-linux-musl   # rust-lld
cargo build --release --target armv7-unknown-linux-musleabihf
cargo build --release --target x86_64-pc-windows-gnu        # mingw
cargo build --release --target wasm32-wasip1
```

For crates with C deps (`*-sys`, openssl-sys, ring, etc.) or targets
that need a target-arch libc, use `cargo zigbuild` — it bundles Zig as
a universal C cross-toolchain and handles both linking and C compilation:

```shell
cargo zigbuild --release --target riscv64gc-unknown-linux-musl
cargo zigbuild --release --target s390x-unknown-linux-gnu
cargo zigbuild --release --target x86_64-apple-darwin
cargo zigbuild --release --target aarch64-apple-darwin
```

Run `rustup target list --installed` inside the container for the full
target list, or `rustup target add <target>` to grab anything else.

### Pre-installed targets

| Family | Targets |
|---|---|
| Linux musl | x86_64, aarch64, i686, armv7, riscv64gc |
| Linux glibc | x86_64, aarch64, i686, armv7, arm, riscv64gc, ppc64le, s390x |
| Windows | x86_64-gnu, i686-gnu, aarch64-gnullvm |
| macOS | x86_64, aarch64 |
| BSD | x86_64-freebsd |
| WASM | wasm32-unknown-unknown, wasm32-wasip1, wasm32-wasip2, wasm32-emscripten |
| Embedded ARM | thumbv6m, thumbv7em, thumbv8m.main |
| Embedded RISC-V | riscv32imc, riscv32imac |
| Android | aarch64-linux-android |

### Caveats

- **macOS SDK is not bundled.** Pure-Rust + `cargo zigbuild` builds for
  `*-apple-darwin` work without it. Code that calls into Apple system
  frameworks (Cocoa, CoreFoundation, etc.) needs the SDK separately.
- **Windows MSVC ABI** (`*-pc-windows-msvc`) is not supported. Use
  `*-pc-windows-gnu` or `*-pc-windows-gnullvm` instead.
- **Embedded targets** (`thumbv*`, `riscv32*-none-*`) require `no_std`
  source code with a `#[panic_handler]` — a `std` hello-world won't
  compile for them.

## Environment variables

| Var                | Default                       | Purpose                                  |
|--------------------|-------------------------------|------------------------------------------|
| `CARGO_HOME`       | `/usr/local/share/cargo`      | Registry, crates, installed cargo bins   |
| `RUSTUP_HOME`      | `/usr/local/share/rustup`     | Toolchains and components                |
| `RUSTUP_TOOLCHAIN` | `stable`                      | Default channel                          |
| `TZ`               | `America/New_York`            | Override at run time (`-e TZ=...`)       |

`CARGO_TARGET_DIR` is intentionally **not** set so each project keeps
its own `./target/` (standard cargo behavior). Export it yourself if
you want a shared cache across projects.

## Persistence

Rust state lives at two canonical FHS paths, both declared as Docker
`VOLUME`s:

- **`/usr/local/share/cargo`** — registry index, downloaded crates,
  user-installed cargo binaries
- **`/usr/local/share/rustup`** — toolchains and components

Mount named volumes so they survive container rebuilds — saves
bandwidth and dramatically speeds up subsequent builds:

```shell
# named volumes (managed by docker, recommended)
docker run \
  -v rust-cargo:/usr/local/share/cargo \
  -v rust-rustup:/usr/local/share/rustup \
  ...

# or share with the host's own Rust state (bind mounts)
docker run \
  -v ~/.cargo:/usr/local/share/cargo \
  -v ~/.rustup:/usr/local/share/rustup \
  ...
```

For convenience these all resolve to the canonical dirs via symlinks:

- `/root/.cargo` → `/usr/local/share/cargo` (default rustup location)
- `/root/.rustup` → `/usr/local/share/rustup`
- `/data/cargo` → `/usr/local/share/cargo` (created at container start)
- `/data/rustup` → `/usr/local/share/rustup` (created at container start)

  
## Get source files  
  
```shell
dockermgr download src casjaysdevdocker/rust
```
  
OR
  
```shell
git clone "https://github.com/casjaysdevdocker/rust" "$HOME/Projects/github/casjaysdevdocker/rust"
```
  
## Build container  
  
```shell
cd "$HOME/Projects/github/casjaysdevdocker/rust"
buildx 
```
  
## Authors  
  
🤖 casjay: [Github](https://github.com/casjay) 🤖  
⛵ casjaysdevdocker: [Github](https://github.com/casjaysdevdocker) [Docker](https://hub.docker.com/u/casjaysdevdocker) ⛵  
