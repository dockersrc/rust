# syntax=docker/dockerfile:1
# Docker image for rust using the alpine template
ARG IMAGE_NAME="rust"
ARG PHP_SERVER="rust"
ARG BUILD_DATE="202605311109"
ARG LANGUAGE="en_US.UTF-8"
ARG TIMEZONE="America/New_York"
ARG WWW_ROOT_DIR="/usr/local/share/httpd/default"
ARG DEFAULT_FILE_DIR="/usr/local/share/template-files"
ARG DEFAULT_DATA_DIR="/usr/local/share/template-files/data"
ARG DEFAULT_CONF_DIR="/usr/local/share/template-files/config"
ARG DEFAULT_TEMPLATE_DIR="/usr/local/share/template-files/defaults"
ARG PATH="/usr/local/etc/docker/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ARG USER="root"
ARG SHELL_OPTS="set -e -o pipefail"

ARG SERVICE_PORT=""
ARG EXPOSE_PORTS=""
ARG PHP_VERSION="system"
ARG NODE_VERSION="system"
ARG NODE_MANAGER="system"

ARG IMAGE_REPO="casjaysdev/rust"
ARG IMAGE_VERSION="latest"
ARG CONTAINER_VERSION=""

ARG PULL_URL="casjaysdev/alpine"
ARG DISTRO_VERSION="${IMAGE_VERSION}"
ARG BUILD_VERSION="${BUILD_DATE}"

FROM tianon/gosu:latest AS gosu

# ─── native cross-compile stage ───────────────────────────────────────────────
# Mirrors the go-tools pattern: runs on the build platform (always native amd64
# in CI). For arm64 targets the musl cross-toolchain compiles natively instead
# of under QEMU — turning a 15-hour emulated build into a 30-60 minute one.
# cargo binstall --target fetches prebuilt binaries from GitHub releases;
# for tools without prebuilts it falls back to native cross-compilation.
FROM --platform=$BUILDPLATFORM rust:alpine AS rust-tools
ARG TARGETARCH

# zig acts as a universal C/C++ cross-compiler — ships with bundled musl headers
# and stdlib for all targets, so no separate musl-cross toolchain is needed.
# Wrapper scripts named aarch64-linux-musl-{gcc,g++,ar} let the CARGO_TARGET_*
# env vars below work without any changes.
RUN apk add --no-cache zig \
    && printf '#!/bin/sh\nexec zig cc -target aarch64-linux-musl "$@"\n' \
         > /usr/local/bin/aarch64-linux-musl-gcc \
    && printf '#!/bin/sh\nexec zig c++ -target aarch64-linux-musl "$@"\n' \
         > /usr/local/bin/aarch64-linux-musl-g++ \
    && printf '#!/bin/sh\nexec zig ar "$@"\n' \
         > /usr/local/bin/aarch64-linux-musl-ar \
    && chmod +x /usr/local/bin/aarch64-linux-musl-gcc \
                /usr/local/bin/aarch64-linux-musl-g++ \
                /usr/local/bin/aarch64-linux-musl-ar

# Resolve Docker TARGETARCH → Rust target triple
RUN case "${TARGETARCH}" in \
      amd64) echo "x86_64-unknown-linux-musl" ;; \
      arm64) echo "aarch64-unknown-linux-musl" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac > /tmp/rust-target

# Register the cross-compile target with the native (x86_64) Rust toolchain
RUN RUST_TARGET="$(cat /tmp/rust-target)" && rustup target add "${RUST_TARGET}"

# Linker and compiler overrides for aarch64-musl; harmless when TARGETARCH=amd64
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-musl-gcc
ENV CC_aarch64_unknown_linux_musl=aarch64-linux-musl-gcc
ENV CXX_aarch64_unknown_linux_musl=aarch64-linux-musl-g++
ENV AR_aarch64_unknown_linux_musl=aarch64-linux-musl-ar

# Bootstrap cargo-binstall via cargo install — avoids system curl's SSL issues.
# Cargo uses its own bundled TLS stack (not affected by the host SSL intercept
# that blocks curl to *.github.com). Layer cache absorbs the one-time compile cost.
RUN cargo install cargo-binstall

# All tool binaries land in /rust-tools/bin — cleanly separate from rustup shims
RUN mkdir -p /rust-tools/bin

# CARGO_INSTALL_ROOT routes both `cargo install` and `cargo binstall` to /rust-tools/bin
ENV CARGO_INSTALL_ROOT=/rust-tools

# Install all Rust tools for the target arch with the native build cache active.
# Prebuilts are downloaded directly; source fallbacks cross-compile on amd64.
RUN --mount=type=cache,id=cargo-registry-native,sharing=shared,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-git-native,sharing=locked,target=/usr/local/cargo/git \
    set -o pipefail; \
    RUST_TARGET="$(cat /tmp/rust-target)"; \
    cargo binstall -y --target "${RUST_TARGET}" \
      cargo-edit \
      cargo-watch \
      cargo-update \
      cargo-outdated \
      cargo-expand \
      cargo-info \
      bacon \
      cargo-llvm-cov \
      cargo-tarpaulin \
      cargo-audit \
      cargo-deny \
      cargo-machete \
      cargo-semver-checks \
      cargo-make \
      cargo-deb \
      cargo-generate \
      cargo-release \
      cargo-chef \
      cargo-zigbuild \
      just \
      tokei \
      hyperfine \
      wasm-pack \
      wasm-tools \
      wasm-bindgen-cli \
      cbindgen \
      cargo-binutils \
      cargo-bloat \
      cargo-asm \
      mdbook \
      mdbook-toc \
      sccache \
      typos-cli \
      taplo-cli \
      cargo-sort \
      cargo-hack \
      cargo-criterion \
      dprint \
      cargo-careful \
      cargo-public-api \
      cargo-spellcheck \
      cargo-geiger \
      grcov || true; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-nextest 2>/dev/null || \
      cargo install --locked --target "${RUST_TARGET}" cargo-nextest || true; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-dist 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cargo-dist || true; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-msrv 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cargo-msrv; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-mutants 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cargo-mutants; \
    cargo binstall -y --target "${RUST_TARGET}" flip-link 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" flip-link; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-ndk 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cargo-ndk; \
    cargo binstall -y --target "${RUST_TARGET}" trunk 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" trunk 2>/dev/null || true; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-udeps 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cargo-udeps || true; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-fuzz 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cargo-fuzz || true; \
    cargo binstall -y --target "${RUST_TARGET}" cargo-minimal-versions 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cargo-minimal-versions || true; \
    cargo binstall -y --target "${RUST_TARGET}" cross 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" cross 2>/dev/null || true; \
    cargo binstall -y --target "${RUST_TARGET}" samply 2>/dev/null || true; \
    cargo binstall -y --target "${RUST_TARGET}" flamegraph 2>/dev/null || \
      cargo install --target "${RUST_TARGET}" flamegraph || true; \
    cargo install --target "${RUST_TARGET}" probe-rs --features cli 2>/dev/null || true; \
    cargo install --target "${RUST_TARGET}" sqlx-cli \
      --no-default-features --features rustls,postgres,mysql,sqlite 2>/dev/null || true; \
    cargo install --target "${RUST_TARGET}" sea-orm-cli \
      --no-default-features --features codegen,sqlx-mysql,sqlx-postgres,sqlx-sqlite,runtime-tokio-rustls 2>/dev/null || true

FROM ${PULL_URL}:${DISTRO_VERSION} AS build
ARG TZ
ARG USER
ARG LICENSE
ARG TIMEZONE
ARG LANGUAGE
ARG IMAGE_NAME
ARG BUILD_DATE
ARG SERVICE_PORT
ARG EXPOSE_PORTS
ARG BUILD_VERSION
ARG IMAGE_VERSION
ARG WWW_ROOT_DIR
ARG DEFAULT_FILE_DIR
ARG DEFAULT_DATA_DIR
ARG DEFAULT_CONF_DIR
ARG DEFAULT_TEMPLATE_DIR
ARG DISTRO_VERSION
ARG NODE_VERSION
ARG NODE_MANAGER
ARG PHP_VERSION
ARG PHP_SERVER
ARG SHELL_OPTS
ARG PATH
ARG TARGETARCH

ARG PACK_LIST="bash tini bash-completion git curl wget sudo unzip iproute2 openrc ssmtp openssl jq tzdata mailcap ncurses util-linux pciutils usbutils coreutils binutils findutils grep rsync zip py3-pip procps net-tools sed gawk attr readline lsof less shadow ca-certificates "

ENV ENV=~/.profile
ENV SHELL="/bin/sh"
ENV PATH="${PATH}"
ENV TZ="${TIMEZONE}"
ENV TIMEZONE="${TZ}"
ENV LANG="${LANGUAGE}"
ENV TERM="xterm-256color"
ENV HOSTNAME="casjaysdevdocker-rust"

USER ${USER}
WORKDIR /root

COPY ./rootfs/. /

RUN set -e; \
  echo "Updating the system and ensuring bash is installed"; \
  pkmgr update;pkmgr install bash

RUN set -e; \
  echo "Setting up prerequisites"; \
  true

ENV SHELL="/bin/bash"
SHELL [ "/bin/bash", "-c" ]

COPY --from=gosu /usr/local/bin/gosu /usr/local/bin/gosu

RUN echo "Initializing the system"; \
  $SHELL_OPTS; \
  mkdir -p "${DEFAULT_DATA_DIR}" "${DEFAULT_CONF_DIR}" "${DEFAULT_TEMPLATE_DIR}" "/root/docker/setup" "/etc/profile.d"; \
  if [ -f "/root/docker/setup/00-init.sh" ];then echo "Running the init script";/root/docker/setup/00-init.sh||{ echo "Failed to execute /root/docker/setup/00-init.sh" >&2 && exit 10; };echo "Done running the init script";fi; \
  echo ""

RUN echo "Creating and editing system files "; \
  $SHELL_OPTS; \
  [ -f "/root/.profile" ] || touch "/root/.profile"; \
  if [ -f "/root/docker/setup/01-system.sh" ];then echo "Running the system script";/root/docker/setup/01-system.sh||{ echo "Failed to execute /root/docker/setup/01-system.sh" >&2 && exit 10; };echo "Done running the system script";fi; \
  echo ""

RUN echo "Running pre-package commands"; \
  $SHELL_OPTS; \
  echo ""

RUN --mount=type=cache,id=apk-cache-${TARGETARCH},sharing=locked,target=/var/cache/apk \
  echo "Setting up and installing packages"; \
  $SHELL_OPTS; \
  if [ -n "${PACK_LIST}" ];then echo "Installing packages: $PACK_LIST";echo "${PACK_LIST}" >/root/docker/setup/packages.txt;pkmgr install ${PACK_LIST};fi; \
  echo ""

RUN echo "Initializing packages before copying files to image"; \
  $SHELL_OPTS; \
  if [ -f "/root/docker/setup/02-packages.sh" ];then echo "Running the packages script";/root/docker/setup/02-packages.sh||{ echo "Failed to execute /root/docker/setup/02-packages.sh" >&2 && exit 10; };echo "Done running the packages script";fi; \
  echo ""

COPY ./Dockerfile /root/docker/Dockerfile

RUN echo "Updating system files "; \
  $SHELL_OPTS; \
  echo "$TIMEZONE" >"/etc/timezone"; \
  touch "/etc/profile" "/root/.profile"; \
  echo 'hosts: files dns' >"/etc/nsswitch.conf"; \
  [ "$PHP_VERSION" = "system" ] && PHP_VERSION="php" || true; \
  PHP_BIN="$(command -v ${PHP_VERSION} 2>/dev/null || true)"; \
  set -- /usr/*bin/php*fpm*; [ -e "$1" ] && PHP_FPM="$1" || PHP_FPM=""; \
  pip_bin="$(command -v python3 2>/dev/null || command -v python2 2>/dev/null || command -v python 2>/dev/null || true)"; \
  py_version="$(command $pip_bin --version | sed 's|[pP]ython ||g' | awk -F '.' '{print $1$2}' | grep '[0-9]' || true)"; \
  [ "$py_version" -gt "310" ] && pip_opts="--break-system-packages " || pip_opts=""; \
  [ -f "/usr/share/zoneinfo/${TZ}" ] && ln -sf "/usr/share/zoneinfo/${TZ}" "/etc/localtime" || true; \
  [ -n "$PHP_BIN" ] && [ -z "$(command -v php 2>/dev/null)" ] && ln -sf "$PHP_BIN" "/usr/bin/php" 2>/dev/null || true; \
  [ -n "$PHP_FPM" ] && [ -z "$(command -v php-fpm 2>/dev/null)" ] && ln -sf "$PHP_FPM" "/usr/bin/php-fpm" 2>/dev/null || true; \
  if [ -f "/etc/profile.d/color_prompt.sh.disabled" ]; then mv -f "/etc/profile.d/color_prompt.sh.disabled" "/etc/profile.d/color_prompt.sh";fi ; \
  { [ -f "/etc/bash/bashrc" ] && cp -Rf "/etc/bash/bashrc" "/root/.bashrc"; } || { [ -f "/etc/bashrc" ] && cp -Rf "/etc/bashrc" "/root/.bashrc"; } || { [ -f "/etc/bash.bashrc" ] && cp -Rf "/etc/bash.bashrc" "/root/.bashrc"; } || true; \
  if [ -z "$(command -v "apt-get" 2>/dev/null)" ];then grep -sh -q 'alias quit' "/root/.bashrc" || printf '# Profile\n\n%s\n%s\n%s\n' '. /etc/profile' '. /root/.profile' "alias quit='exit 0 2>/dev/null'" >>"/root/.bashrc"; fi; \
  if [ "$PHP_VERSION" != "system" ] && [ -e "/etc/php" ] && [ -d "/etc/${PHP_VERSION}" ];then rm -Rf "/etc/php";fi; \
  if [ "$PHP_VERSION" != "system" ] && [ -n "${PHP_VERSION}" ] && [ -d "/etc/${PHP_VERSION}" ];then ln -sf "/etc/${PHP_VERSION}" "/etc/php";fi; \
  if [ -f "/root/docker/setup/03-files.sh" ];then echo "Running the files script";/root/docker/setup/03-files.sh||{ echo "Failed to execute /root/docker/setup/03-files.sh" >&2 && exit 10; };echo "Done running the files script";fi; \
  echo ""

RUN echo "Custom Settings"; \
  $SHELL_OPTS; \
echo ""

RUN echo "Setting up users and scripts "; \
  $SHELL_OPTS; \
  if [ -f "/root/docker/setup/04-users.sh" ];then echo "Running the users script";/root/docker/setup/04-users.sh||{ echo "Failed to execute /root/docker/setup/04-users.sh" >&2 && exit 10; };echo "Done running the users script";fi; \
  echo ""

RUN echo "Running the user init commands"; \
  $SHELL_OPTS; \
  echo ""

RUN echo "Setting OS Settings "; \
  $SHELL_OPTS; \
  echo ""

RUN echo "Custom Applications"; \
  $SHELL_OPTS; \
echo ""

# Target-arch tool binaries compiled natively in the rust-tools stage;
# copied here before 05-custom.sh runs so the symlink loop picks them up
COPY --from=rust-tools /rust-tools/bin/ /usr/local/share/cargo/bin/

RUN --mount=type=cache,id=rustup-downloads-${TARGETARCH},sharing=locked,target=/usr/local/share/rustup/downloads \
    --mount=type=cache,id=sccache-build-${TARGETARCH},sharing=locked,target=/root/.cache/sccache \
    echo "Running custom commands"; \
  export RUSTC_WRAPPER=/usr/local/share/cargo/bin/sccache; \
  export SCCACHE_DIR=/root/.cache/sccache; \
  if [ -f "/root/docker/setup/05-custom.sh" ];then echo "Running the custom script";/root/docker/setup/05-custom.sh||{ echo "Failed to execute /root/docker/setup/05-custom.sh" && exit 10; };echo "Done running the custom script";fi; \
  echo ""

RUN echo "Running final commands before cleanup"; \
  $SHELL_OPTS; \
  if [ -f "/root/docker/setup/06-post.sh" ];then echo "Running the post script";/root/docker/setup/06-post.sh||{ echo "Failed to execute /root/docker/setup/06-post.sh" >&2 && exit 10; };echo "Done running the post script";fi; \
  echo ""

RUN echo "Deleting unneeded files"; \
  $SHELL_OPTS; \
  pkmgr clean; \
  rm -Rf "/config" "/data" || true; \
  rm -rf /etc/systemd/system/*.wants/* || true; \
  rm -rf /lib/systemd/system/systemd-update-utmp* || true; \
  rm -rf /lib/systemd/system/anaconda.target.wants/* || true; \
  rm -rf /lib/systemd/system/local-fs.target.wants/* || true; \
  rm -rf /lib/systemd/system/multi-user.target.wants/* || true; \
  rm -rf /lib/systemd/system/sockets.target.wants/*udev* || true; \
  rm -rf /lib/systemd/system/sockets.target.wants/*initctl* || true; \
  rm -Rf /usr/share/doc/* /var/tmp/* /var/cache/*/* /root/.cache/* /usr/share/info/* /tmp/* || true; \
  if [ -d "/lib/systemd/system/sysinit.target.wants" ];then cd "/lib/systemd/system/sysinit.target.wants" && for want_file in *; do [ "$want_file" = "systemd-tmpfiles-setup" ] || rm -f "$want_file"; done; fi; \
  if [ -f "/root/docker/setup/07-cleanup.sh" ];then echo "Running the cleanup script";/root/docker/setup/07-cleanup.sh||{ echo "Failed to execute /root/docker/setup/07-cleanup.sh" >&2 && exit 10; };echo "Done running the cleanup script";fi; \
  echo ""

RUN echo "Init done"
FROM scratch
ARG TZ
ARG PATH
ARG USER
ARG TIMEZONE
ARG LANGUAGE
ARG IMAGE_NAME
ARG BUILD_DATE
ARG SERVICE_PORT
ARG EXPOSE_PORTS
ARG BUILD_VERSION
ARG IMAGE_VERSION
ARG GIT_COMMIT
ARG WWW_ROOT_DIR
ARG DEFAULT_FILE_DIR
ARG DEFAULT_DATA_DIR
ARG DEFAULT_CONF_DIR
ARG DEFAULT_TEMPLATE_DIR
ARG DISTRO_VERSION
ARG NODE_VERSION
ARG NODE_MANAGER
ARG PHP_VERSION
ARG PHP_SERVER
ARG LICENSE="WTFPL"
ARG ENV_PORTS="${EXPOSE_PORTS}"

USER ${USER}
WORKDIR /app

LABEL maintainer="CasjaysDev <docker-admin@casjaysdev.pro>"
LABEL org.opencontainers.image.vendor="CasjaysDev"
LABEL org.opencontainers.image.authors="CasjaysDev"
LABEL org.opencontainers.image.description="Containerized version of ${IMAGE_NAME}"
LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.base.name="${IMAGE_NAME}"
LABEL org.opencontainers.image.authors="${LICENSE}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.version="${BUILD_VERSION}"
LABEL org.opencontainers.image.schema-version="${BUILD_VERSION}"
LABEL org.opencontainers.image.url="https://hub.docker.com/r/casjaysdev/rust"
LABEL org.opencontainers.image.vcs-type="Git"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.source="https://github.com/dockersrc/rust"
LABEL org.opencontainers.image.documentation="https://github.com/dockersrc/rust"
LABEL com.github.containers.toolbox="false"

ENV ENV=~/.bashrc
ENV USER="${USER}"
ENV PATH="${PATH}"
ENV TZ="${TIMEZONE}"
ENV SHELL="/bin/bash"
ENV TIMEZONE="${TZ}"
ENV LANG="${LANGUAGE}"
ENV TERM="xterm-256color"
ENV PORT="${SERVICE_PORT}"
ENV ENV_PORTS="${ENV_PORTS}"
ENV CONTAINER_NAME="${IMAGE_NAME}"
ENV HOSTNAME="casjaysdev-${IMAGE_NAME}"
ENV PHP_SERVER="${PHP_SERVER}"
ENV NODE_VERSION="${NODE_VERSION}"
ENV NODE_MANAGER="${NODE_MANAGER}"
ENV PHP_VERSION="${PHP_VERSION}"
ENV DISTRO_VERSION="${IMAGE_VERSION}"
ENV WWW_ROOT_DIR="${WWW_ROOT_DIR}"
ENV RUSTUP_HOME="/usr/local/share/rustup"
ENV CARGO_HOME="/usr/local/share/cargo"
ENV RUSTUP_TOOLCHAIN="stable"
ENV SCCACHE_DIR="/root/.cache/sccache"
ENV CARGO_INCREMENTAL="0"

COPY --from=build /. /

VOLUME [ "/config","/data","/usr/local/share/cargo","/usr/local/share/rustup","/root/.cache/sccache" ]

EXPOSE ${SERVICE_PORT} ${ENV_PORTS}

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT [ "tini", "-p", "SIGTERM","--", "/usr/local/bin/entrypoint.sh" ]
HEALTHCHECK --start-period=10m --interval=5m --timeout=15s CMD [ "/usr/local/bin/entrypoint.sh", "healthcheck" ]

