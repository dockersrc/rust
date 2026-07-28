#!/bin/sh
set -x
echo "== rustc =="; rustc --version
echo "== cargo =="; cargo --version
echo "== rustfmt =="; rustfmt --version
echo "== clippy =="; cargo clippy --version
echo "== just =="; just --version
echo "== sccache =="; sccache --version
echo "== cargo-nextest =="; cargo nextest --version
echo "== cargo-audit =="; cargo audit --version
echo "== cargo-binstall =="; cargo binstall --version
echo "== targets installed =="; rustup target list --installed
echo "== nightly + miri =="; rustup run nightly rustc --version; cargo +nightly miri --version
echo "== cross compile aarch64-musl hello world =="
mkdir -p /tmp/hello && cd /tmp/hello
cat > Cargo.toml <<'EOF'
[package]
name = "hello"
version = "0.1.0"
edition = "2021"
EOF
mkdir -p src
echo 'fn main() { println!("hello cross"); }' > src/main.rs
cargo build --release --target aarch64-unknown-linux-musl
file target/aarch64-unknown-linux-musl/release/hello
echo "== rust-workflow help =="
rust-workflow --help 2>&1 | head -20 || echo "rust-workflow not found or errored"
echo "== ALL DONE =="
