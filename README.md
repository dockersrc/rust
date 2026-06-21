# rust

A Docker image that ships the **latest stable Rust toolchain** (fetched from
`static.rust-lang.org` at image build time, SHA256-verified) together with a
comprehensive set of tools for building, testing, linting, formatting,
debugging, profiling, fuzzing, and releasing Rust projects. Based on Alpine
with full musl static-build support and 30 pre-installed cross-compile targets.

---

## 📦 Pull

```shell
docker pull casjaysdev/rust:latest
```

---

## 🚀 Install and run container

```shell
dockermgr update rust
```

Or manually:

```shell
dockerHome="/var/lib/srv/$USER/docker/casjaysdevdocker/rust/rust/latest/volumes"
mkdir -p "$dockerHome"
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
  -v rust-cargo:/usr/local/share/cargo \
  -v rust-rustup:/usr/local/share/rustup \
  -v rust-sccache:/root/.cache/sccache \
  casjaysdev/rust:latest
```

---

## ⚡ rust-workflow

**`rust-workflow`** is a four-step pipeline included in the image. It must
be called explicitly — running the container with no arguments starts it in
monitoring mode, it does not execute `rust-workflow` automatically:

```
fmt check  →  clippy -D warnings  →  cargo test --all  →  cargo build --release
```

```shell
# run the full workflow against your project
docker run --rm -it \
  -v "$PWD:/app" \
  casjaysdev/rust:latest rust-workflow
```

Override the working directory with `CARGO_WORKDIR`, or target a specific
cross-compile triple with `CARGO_BUILD_TARGET`:

```shell
docker run --rm -it \
  -v "$PWD:/app" \
  -e CARGO_BUILD_TARGET=aarch64-unknown-linux-musl \
  casjaysdev/rust:latest rust-workflow
```

---

## 🐳 Docker

### Quick one-shot commands

```shell
# build release binary
docker run --rm -it -v "$PWD:/app" casjaysdev/rust:latest \
  cargo build --release

# run tests with cargo-nextest
docker run --rm -it -v "$PWD:/app" casjaysdev/rust:latest \
  cargo nextest run

# lint
docker run --rm -it -v "$PWD:/app" casjaysdev/rust:latest \
  cargo clippy --all-targets --all-features -- -D warnings

# check formatting
docker run --rm -it -v "$PWD:/app" casjaysdev/rust:latest \
  cargo fmt --all -- --check

# audit dependencies for known vulnerabilities
docker run --rm -it -v "$PWD:/app" casjaysdev/rust:latest \
  cargo audit

# interactive shell
docker run --rm -it -v "$PWD:/app" casjaysdev/rust:latest bash -l
```

### Long-running container

```shell
docker run -d \
  --restart always \
  --name casjaysdev-rust \
  --hostname rust \
  -e TZ=${TIMEZONE:-America/New_York} \
  -v rust-cargo:/usr/local/share/cargo \
  -v rust-rustup:/usr/local/share/rustup \
  -v rust-sccache:/root/.cache/sccache \
  -v "$PWD:/app" \
  casjaysdev/rust:latest

# exec into it
docker exec -it casjaysdev-rust bash -l
docker exec casjaysdev-rust cargo test
docker exec casjaysdev-rust cargo clippy --all-targets
docker exec casjaysdev-rust cargo nextest run
docker exec casjaysdev-rust cargo audit
```

### docker-compose

```yaml
services:
  rust:
    image: casjaysdev/rust:latest
    container_name: casjaysdev-rust
    hostname: rust
    environment:
      - TZ=America/New_York
    volumes:
      - rust-cargo:/usr/local/share/cargo
      - rust-rustup:/usr/local/share/rustup
      - rust-sccache:/root/.cache/sccache
      - .:/app
    restart: always

volumes:
  rust-cargo:
  rust-rustup:
  rust-sccache:
```

---

## 🔧 Included tools

### Toolchain (via rustup — stable)

| Component | Purpose |
|-----------|---------|
| `rustc` | Rust compiler |
| `cargo` | Package manager and build tool |
| `rustfmt` | Official code formatter |
| `clippy` | Lint collection — catches correctness and style issues |
| `rust-src` | Standard library source — required by rust-analyzer and miri |
| `rust-analyzer` | Language server — IDE integration |
| `llvm-tools-preview` | LLVM utilities — used by coverage and binutils tools |

### Toolchain (via rustup — nightly, minimal)

| Component | Purpose |
|-----------|---------|
| `miri` | Interpreter that detects undefined behavior, borrow violations, and memory errors at runtime |
| `rust-src` (nightly) | Required by miri |

Run miri with: `cargo +nightly miri test`

### Linting & static analysis

| Tool | Purpose |
|------|---------|
| `cargo-clippy` | Bundled with toolchain; `cargo clippy --all-targets --all-features` |
| `cargo-geiger` | Counts `unsafe` blocks and dependencies — reports unsafe surface area |
| `cargo-deny` | Policy enforcement — license allow-lists, ban crates, advisories |
| `cargo-audit` | Scan `Cargo.lock` against the RustSec advisory DB |
| `cargo-machete` | Detect unused dependencies (stable) |
| `cargo-udeps` | Detect unused dependencies (nightly; `cargo +nightly udeps`) |
| `cargo-hack` | Test all feature flag combinations to catch cfg-gated bugs |
| `cargo-minimal-versions` | Verify the crate compiles with the minimum versions declared in `Cargo.toml` |
| `cargo-semver-checks` | Detect breaking API changes against a published version |
| `cargo-public-api` | Diff the public API between commits or versions |
| `typos` | Fast source-code spell checker — catches typos in identifiers and strings |
| `cargo-spellcheck` | Doc-comment spell checker — catches typos in `///` and `//!` docs |

### Formatting

| Tool | Purpose |
|------|---------|
| `rustfmt` | Bundled; `cargo fmt --all` |
| `taplo` | TOML formatter and linter — format `Cargo.toml`, `.cargo/config.toml`, etc. |
| `dprint` | Pluggable formatter — supports Rust (via rustfmt plugin), TOML, JSON, Markdown |
| `cargo-sort` | Sort `[dependencies]` sections in `Cargo.toml` alphabetically |

### Testing & coverage

| Tool | Purpose |
|------|---------|
| `cargo-nextest` | Faster test runner — parallel, per-test timeouts, JUnit output |
| `cargo-llvm-cov` | Source-based code coverage using LLVM instrumentation |
| `cargo-tarpaulin` | Coverage via ptrace — useful when LLVM instrumentation isn't available |
| `grcov` | Mozilla's LLVM coverage aggregator — converts profraw data to lcov/HTML |
| `cargo-mutants` | Mutation testing — checks that tests actually catch code changes |
| `miri` | Run tests under the interpreter to catch UB (see nightly above) |

### Benchmarking & profiling

| Tool | Purpose |
|------|---------|
| `cargo-criterion` | Criterion-based benchmark runner with statistical analysis |
| `hyperfine` | Command-line benchmarking tool — wall-clock timing with statistics |
| `samply` | Sampling profiler — records perf profiles, opens in Firefox Profiler |
| `flamegraph` | Generate flame graphs from `cargo bench` or any cargo command (`cargo flamegraph`) |

> **Perf note:** `perf` is installed from the Alpine package repo. Profiling with
> `samply` or `flamegraph` inside Docker requires elevated capabilities at runtime:
> `--privileged` or `--cap-add SYS_ADMIN --cap-add PERFMON`. This is a host grant
> — it cannot be baked into the image.

### Fuzzing

| Tool | Purpose |
|------|---------|
| `cargo-fuzz` | libFuzzer integration for Rust — `cargo fuzz run <target>` |

### Debugging

| Tool | Purpose |
|------|---------|
| `gdb` | GNU debugger — `rust-gdb` wrapper is provided by the toolchain |
| `miri` | Undefined-behavior detector — catches memory errors before they reach gdb |
| `cargo-careful` | Run tests and binaries with extra UB checks (`-Z randomize-layout`, `panic-on-ub`) |
| `probe-rs` | On-chip debugger for embedded targets — flashes and debugs ARM/RISC-V |

### Code analysis & inspection

| Tool | Purpose |
|------|---------|
| `cargo-expand` | Expand proc-macros and `macro_rules!` to plain Rust |
| `cargo-asm` | Disassemble a function to see the emitted assembly |
| `cargo-bloat` | Identify what is taking space in your binary |
| `cargo-binutils` | `llvm-size`, `llvm-nm`, `llvm-objdump`, etc. via `cargo-` wrappers |
| `tokei` | Count lines of code by language |

### Build & release

| Tool | Purpose |
|------|---------|
| `cargo-make` | Task runner (`Makefile.toml`) — replaces `make` for Rust projects |
| `just` | Command runner (`justfile`) — simpler `make` alternative |
| `cargo-release` | Automate version bumps, changelog, tag, and publish |
| `cargo-dist` | Cross-platform release artifact builder and installer generator |
| `cargo-deb` | Build `.deb` packages directly from `Cargo.toml` |
| `cargo-generate` | Scaffold new crates from templates |
| `cargo-chef` | Docker layer caching for Cargo builds — pre-cook dependencies |

### Cross-compilation

| Tool | Purpose |
|------|---------|
| `cargo-zigbuild` | Cross-compile using Zig as a universal C/C++ toolchain — no sysroot needed |
| `cross` | Cross-compile runner using QEMU inside Docker — full stdlib support |
| `cargo-ndk` | Build Android libraries with the NDK |
| `cbindgen` | Generate C/C++ headers from Rust code |
| `flip-link` | Embedded linker that moves the stack below `.bss` to catch stack overflows |

### WASM

| Tool | Purpose |
|------|---------|
| `wasm-pack` | Build, test, and publish Rust-generated WASM packages |
| `wasm-bindgen-cli` | Generate JS/TS bindings for Rust WASM modules |
| `wasm-tools` | Low-level WASM binary toolkit — validate, transform, component model |
| `trunk` | Rust/WASM bundler for web frontends — live-reload dev server |
| `wasm-opt` (binaryen) | WASM binary optimiser — shrinks and speeds up `.wasm` output |

### Docs

| Tool | Purpose |
|------|---------|
| `mdbook` | Build documentation books from Markdown |
| `mdbook-toc` | Auto-generate table-of-contents for mdBook chapters |

### Workflow & dev loop

| Tool | Purpose |
|------|---------|
| `bacon` | Background build/test runner — re-runs on file save, stays in terminal |
| `cargo-watch` | Re-run any cargo command on file change |
| `cargo-edit` | `cargo add`, `cargo rm`, `cargo upgrade` — edit `Cargo.toml` from CLI |
| `cargo-update` | Update installed cargo binaries (`cargo install-update -a`) |
| `cargo-outdated` | Show outdated `Cargo.toml` dependencies |
| `cargo-info` | Detailed crate info from crates.io |
| `cargo-msrv` | Find and verify the minimum supported Rust version |

### Compilation cache

| Tool | Purpose |
|------|---------|
| `sccache` | Shared compilation cache — cache on local disk, S3, Redis, GCS, or Azure |

### Database (best-effort)

| Tool | Purpose |
|------|---------|
| `sqlx-cli` | Compile-time SQL verification and migration runner for sqlx |
| `sea-orm-cli` | Migration generator and entity scaffolder for SeaORM |

Both are built with `rustls` instead of `native-tls` (pure-Rust TLS stack,
no OpenSSL dependency) and support postgres, mysql, and sqlite. Projects with
unusual feature requirements may `cargo install` them again with different flags.

---

## 💾 Cache & persistence

Four paths are declared as Docker `VOLUME`s:

| Volume path | Contents |
|-------------|----------|
| `/usr/local/share/cargo` | Registry index, downloaded crate tarballs, installed binaries |
| `/usr/local/share/rustup` | Toolchains and components |
| `/root/.cache/sccache` | Compiled artifact cache (sccache) |
| `/config`, `/data` | Container config and data |

### Named volumes (recommended)

```shell
docker run --rm -v "$PWD:/app" \
  -v rust-cargo:/usr/local/share/cargo \
  -v rust-rustup:/usr/local/share/rustup \
  -v rust-sccache:/root/.cache/sccache \
  casjaysdev/rust:latest
```

### Share with the host's own Rust installation

```shell
docker run --rm -v "$PWD:/app" \
  -v ~/.cargo:/usr/local/share/cargo \
  -v ~/.rustup:/usr/local/share/rustup \
  -v ~/.cache/sccache:/root/.cache/sccache \
  casjaysdev/rust:latest
```

### sccache compilation caching (on by default)

`sccache` is installed and **active by default**. `RUSTC_WRAPPER=sccache` is
set in `/etc/profile.d/rust.sh` so every login shell automatically routes
`rustc` invocations through the cache. `SCCACHE_DIR` points to
`/root/.cache/sccache`, which is declared as a Docker volume.

```shell
docker run --rm -v "$PWD:/app" \
  -v rust-sccache:/root/.cache/sccache \
  casjaysdev/rust:latest cargo build --release
```

Cache hits skip recompilation entirely, dramatically speeding up incremental
and repeated builds. `CARGO_INCREMENTAL` is forced to `0` because cargo's own
incremental compilation conflicts with sccache's shared cache.

To opt out: `-e RUSTC_WRAPPER=`

#### Remote sccache backends

Point sccache at S3, Redis, GCS, or Azure by setting the relevant env vars
before the run. The sccache documentation covers the full list; a quick
example for S3:

```shell
docker run --rm -v "$PWD:/app" \
  -e RUSTC_WRAPPER=sccache \
  -e SCCACHE_BUCKET=my-bucket \
  -e SCCACHE_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID=... \
  -e AWS_SECRET_ACCESS_KEY=... \
  casjaysdev/rust:latest
```

### BuildKit cache mounts (for image builds)

The `Dockerfile` uses `--mount=type=cache` across all stages. This keeps the
apk index, cargo registry, rustup downloads, and sccache populated between
`docker build` runs so rebuilding after a change does not re-download or
recompile anything:

```shell
# BuildKit is the default since Docker 23; no flags needed
docker build --tag casjaysdev/rust:local .
```

| Stage | Cache mount ID | Contents |
|-------|----------------|----------|
| `build` | `apk-cache-<arch>` | Alpine package index and downloaded APKs |
| `build` | `rustup-downloads-<arch>` | rustup toolchain and component tarballs |
| `build` | `sccache-build-<arch>` | sccache compiled-artifact cache for the build stage |
| `rust-tools` | `cargo-registry-native` | Cargo registry index and crate tarballs (native) |
| `rust-tools` | `cargo-git-native` | Cargo git dependencies (native) |
| `rust-tools` | `sccache-native` | sccache cache for source-compiled tools in the native stage |

`<arch>` is `amd64` or `arm64`. Per-arch IDs prevent cross-arch cache
corruption in multi-platform builds.

---

## ⚙️ Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CARGO_HOME` | `/usr/local/share/cargo` | Registry, crates, installed cargo binaries |
| `RUSTUP_HOME` | `/usr/local/share/rustup` | Toolchains and components |
| `RUSTUP_TOOLCHAIN` | `stable` | Default channel |
| `SCCACHE_DIR` | `/root/.cache/sccache` | Local sccache storage directory |
| `CARGO_INCREMENTAL` | `0` | Disabled — conflicts with sccache shared cache |
| `RUSTC_WRAPPER` | `sccache` | Active by default; set to empty string to disable |
| `CARGO_WORKDIR` | *(unset)* | Override working directory for `rust-workflow` |
| `CARGO_BUILD_TARGET` | *(unset)* | Cross-compile triple for `rust-workflow` |
| `TZ` | `America/New_York` | Override at run time with `-e TZ=...` |

`CARGO_TARGET_DIR` is intentionally **not** set so each project keeps its own
`./target/` directory. Export it yourself if you want a shared build cache
across projects.

Convenience symlinks so standard tools find their home:

| Symlink | Target |
|---------|--------|
| `/root/.cargo` | `/usr/local/share/cargo` |
| `/root/.rustup` | `/usr/local/share/rustup` |

---

## 🌐 Cross-compile

### Pre-installed targets

| Family | Targets |
|--------|---------|
| Linux musl | `x86_64`, `aarch64`, `i686`, `armv7`, `riscv64gc` |
| Linux glibc | `x86_64`, `aarch64`, `i686`, `armv7`, `arm`, `riscv64gc`, `ppc64le`, `s390x` |
| Windows GNU | `x86_64-gnu`, `i686-gnu`, `aarch64-gnullvm` |
| macOS | `x86_64-apple-darwin`, `aarch64-apple-darwin` |
| BSD | `x86_64-unknown-freebsd` |
| WASM | `wasm32-unknown-unknown`, `wasm32-wasip1`, `wasm32-wasip2`, `wasm32-unknown-emscripten` |
| Embedded ARM | `thumbv6m-none-eabi`, `thumbv7em-none-eabihf`, `thumbv8m.main-none-eabi` |
| Embedded RISC-V | `riscv32imc-unknown-none-elf`, `riscv32imac-unknown-none-elf` |
| Android | `aarch64-linux-android` |

`rustup target add <triple>` to install any additional target at runtime.

### Pure-Rust crates — `cargo build`

A pre-configured `$CARGO_HOME/config.toml` maps cross-compile linkers:
`rust-lld` for ARM/aarch64/embedded and `*-w64-mingw32-gcc` for Windows GNU.
Plain `cargo build --target` works for pure-Rust crates on most targets:

```shell
cargo build --release --target aarch64-unknown-linux-musl
cargo build --release --target armv7-unknown-linux-musleabihf
cargo build --release --target x86_64-pc-windows-gnu
cargo build --release --target wasm32-wasip1
```

### Crates with C dependencies — `cargo zigbuild`

For crates that link against C code (`*-sys`, `openssl-sys`, `ring`, etc.) use
`cargo zigbuild`. Zig ships as a universal C/C++ cross-toolchain and handles
linking and C compilation without a target sysroot:

```shell
cargo zigbuild --release --target riscv64gc-unknown-linux-musl
cargo zigbuild --release --target s390x-unknown-linux-gnu
cargo zigbuild --release --target x86_64-apple-darwin
cargo zigbuild --release --target aarch64-apple-darwin
```

### Full stdlib cross-compile — `cross`

`cross` runs the official cross-rs container for targets that need a complete
target-arch libc or runtime:

```shell
cross build --release --target powerpc64le-unknown-linux-gnu
```

### Caveats

- **macOS SDK not bundled.** Pure-Rust + `cargo zigbuild` works. Code that
  calls Apple system frameworks (Cocoa, CoreFoundation, etc.) needs the SDK.
- **Windows MSVC ABI** (`*-pc-windows-msvc`) is not supported — use
  `*-pc-windows-gnu` or `*-pc-windows-gnullvm`.
- **Embedded targets** (`thumbv*`, `riscv32*-none-*`) require `no_std` source
  with a `#[panic_handler]` — a `std` hello-world will not compile for them.

---

## 🧪 Miri (undefined behavior detection)

Miri is installed on the nightly toolchain and detects undefined behavior,
incorrect use of unsafe, borrow violations across FFI, and data races in tests:

```shell
# run your test suite under miri
cargo +nightly miri test

# run a specific test
cargo +nightly miri test my_test_name

# run miri in tree mode for finer control
cargo +nightly miri run
```

Miri is slower than a normal test run — use it targeted on unsafe code or
after a refactor rather than in the default CI path.

---

## 🛠️ Development

```shell
git clone "https://github.com/dockersrc/rust" "$HOME/Projects/github/dockersrc/rust"
cd "$HOME/Projects/github/dockersrc/rust"
docker build --tag casjaysdev/rust:local .
```

BuildKit is required (default in Docker 23+). Cache mounts keep subsequent
builds fast — cargo registry, rustup downloads, and sccache data persist in
BuildKit's own cache layer storage.

### Build architecture — native cross-compilation

The `Dockerfile` uses the same `--platform=$BUILDPLATFORM` pattern as the
Go image's `go-tools` stage. A dedicated `rust-tools` stage runs natively on
the build host (always amd64 in CI) and cross-compiles or downloads all
~50 Rust tool binaries for the target arch before the main build stage ever
starts. This eliminates QEMU emulation for tool compilation:

| How | What |
|-----|------|
| `cargo binstall --target <triple>` | Fetches prebuilt binaries from GitHub releases — no compilation |
| `cargo install --target <triple>` | Source-compiles natively on amd64 via the `musl-cross` toolchain |
| `sccache` (native x86_64) | Caches all source compilations across rebuilds |

Tools with C dependencies use pure-Rust alternatives wherever possible:
`rustls` instead of `native-tls`/OpenSSL (sqlx-cli, sea-orm-cli, trunk);
bundled SQLite via `rusqlite`'s `bundled` feature. `probe-rs` (needs libusb)
is best-effort: downloaded if a prebuilt exists, silently skipped otherwise.

**Expected multi-arch build times:**

| Arch | Before (QEMU) | After (native cross-compile) |
|------|---------------|------------------------------|
| `linux/amd64` | ~20 min | ~20 min |
| `linux/arm64` | ~15 hours | ~30–60 min |

---

## 📄 License

WTFPL

---

🤖 [casjay](https://github.com/casjay)  
⛵ [casjaysdevdocker](https://github.com/casjaysdevdocker) — [Docker Hub](https://hub.docker.com/r/casjaysdev/rust)  
