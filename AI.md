# CasjaysDev Docker Base Image Specification (dockersrc)

**Name**: {name}

**About this file:** This is the complete, authoritative specification for a CasjaysDev
Docker **base image** repository (`dockersrc/{name}`). It is a master template — copied
into a base image repo as that repo's `AI.md`. It is **permanent** — never delete it from
a repo that carries it.

**Note:** `{name}` in this file is a reference token, not setup-time replacement text. Its
value is always the repo directory basename (`basename "$PWD"`).

**Maintenance procedure:** The bootstrap/update runbook (regenerating files after upstream
template changes, creating new repos) is NOT in this file — it lives in the
`dockersrc-bootstrap` agent. This file defines the standards that procedure enforces.

---

# PART INDEX

| PART | Title |
|------|-------|
| 0 | Critical rules |
| 1 | Repository model & structure |
| 2 | Template system reference |
| 3 | Tooling — gen-dockerfile & gen-script |
| 4 | `.env.scripts` reference |
| 5 | Runtime system — setup scripts, entrypoint, init.d |
| 6 | README.md standard layout |
| 7 | CI/CD workflows |
| 8 | Verification & commit |

---

# PART 0: CRITICAL RULES

## Org mapping

| System | Org | Example |
|--------|-----|---------|
| GitHub (source) | `dockersrc` | `https://github.com/dockersrc/{name}` |
| Docker Hub (push) | `casjaysdev` | `casjaysdev/{name}` |

`dockersrc` repos are **OS bases and toolchains** (alpine, debian, ubuntu, almalinux,
archlinux, web, xorg, go, rust, android). Application images live in the separate
`casjaysdevdocker` org and pull FROM these images — see the apps specification
(`CASJAYSDEVDOCKER.md`).

The Docker Hub push org is always `casjaysdev` regardless of where the repo is checked out.

## Non-negotiable rules

1. **`AI.md` is permanent** — never delete it from the repo.
2. **Generated files are owned by the template system** — never hand-tune content that
   `gen-dockerfile` regenerates (see PART 1 ownership table); fix the upstream
   `gen-dockerfile` template instead, then regenerate.
3. **Hand-crafted files are owned by the repo** — `gen-dockerfile` must never overwrite
   app-specific init.d scripts, custom bin scripts, or a `05-custom.sh` with real content.
4. **Removed OCI labels stay removed** (PART 2) — never re-add `base.name`,
   `schema-version`, or duplicate `authors`/`source` entries.
5. **`image.url` is a browsable page** — `https://hub.docker.com/r/casjaysdev/{name}`.
   `docker.io` is only a registry pull host; it is never a label URL.
6. **`image.source` and `image.documentation` are the GitHub repo** —
   `https://github.com/dockersrc/{name}`.
7. **One variant, one file set** — every published version tag has its own
   `Dockerfile.{ver}`, `.env.scripts.{ver}`, and `.gitea/workflows/build.{ver}.yml`.
8. **Only `root/`, `tmp/`, and `usr/` may exist at `rootfs/` top level** (PART 1).
9. **Maintenance runs through the `dockersrc-bootstrap` agent** — do not improvise the
   update procedure from memory.

---

# PART 1: REPOSITORY MODEL & STRUCTURE

## What a base image repo is

A `dockersrc/{name}` repo builds one image family from upstream official distro images
(never from `casjaysdev/*` — base repos ARE the `casjaysdev/*` images). OS repos publish
one variant per supported release; toolchain repos (go, rust, android) publish `latest`
plus whatever the toolchain needs.

## Standard tree

```
{name}/
├── AI.md                          # This specification (permanent)
├── Dockerfile                     # [generated] latest/default variant
├── Dockerfile.{ver}               # [generated] one per version variant (OS repos)
├── .dockerignore                  # [generated]
├── .env.scripts                   # [generated] build config for the default variant
├── .env.scripts.{ver}             # [generated] one per version variant
├── .gitattributes                 # [generated]
├── .gitea/workflows/
│   ├── build.yml                  # [generated] gen-dockerfile actions — default variant
│   └── build.{ver}.yml            # [generated] one per version variant
├── .gitignore                     # [generated]
├── LICENSE.md                     # License (WTFPL)
├── README.md                      # [generated] standard layout (PART 6)
└── rootfs/                        # Container filesystem overlay
    ├── root/docker/setup/         # [generated*] build-time setup scripts 00–07
    ├── tmp/                       # staged files installed at build time (optional)
    └── usr/local/
        ├── bin/                   # [generated*] entrypoint.sh, pkmgr, symlink, copy,
        │                          #   healthcheck + [hand-crafted] repo-specific scripts
        └── etc/docker/
            ├── env/               # [hand-crafted] build/runtime env fragments (optional)
            ├── functions/
            │   └── entrypoint.sh  # [generated] entrypoint function library
            └── init.d/            # [hand-crafted] runtime init scripts (one per service)
```

`[generated]` — safe to regenerate; local edits will be lost.
`[generated*]` — regenerated from the template, EXCEPT files carrying repo-specific
content (`05-custom.sh` with a real body, extra bin scripts) — those follow the
hand-crafted rules in PART 5.
`[hand-crafted]` — never overwritten by the template system.

## rootfs top-level policy

The only valid directories at the `rootfs/` root are `root/`, `tmp/`, and `usr/`.
Anything else is a leftover from old patterns. Migration map:

| Old rootfs path | Correct rootfs path |
|-----------------|---------------------|
| `rootfs/etc/{path}` | `rootfs/tmp/etc/{path}` |
| `rootfs/config/{path}` | `rootfs/tmp/etc/{path}` |
| `rootfs/data/{path}` | `rootfs/tmp/var/{path}` |
| `rootfs/var/{path}` | `rootfs/tmp/var/{path}` |
| `rootfs/opt/{path}` | `rootfs/tmp/opt/{path}` |
| `rootfs/share/{path}` | `rootfs/usr/local/share/{path}` |

`rootfs/usr/local/share/template-files/` is retired — the `DEFAULT_TEMPLATE_DIR`,
`DEFAULT_FILE_DIR`, `DEFAULT_DATA_DIR`, and `DEFAULT_CONF_DIR` variables were removed
from the template system; the entrypoint installs staged files from `rootfs/tmp/etc/`
at container start instead.

## Variant detection

A repo is a **base** repo when `Dockerfile.*` variant files exist:

```bash
if find . -maxdepth 1 -name 'Dockerfile.*' -type f | grep -q -- .; then
  REPO_TYPE="base"
else
  REPO_TYPE="app"
fi
```

---

# PART 2: TEMPLATE SYSTEM REFERENCE

Templates ship with `gen-dockerfile`, installed at
`/usr/local/share/CasjaysDev/scripts/templates/dockerfiles/`
(`$CASJAYSDEVDIR/templates/dockerfiles/` in a dev checkout). To inspect what the current
templates produce, generate a fresh reference tree in a temp dir:

```bash
gen-dockerfile /tmp/gen-dockerfile/{org}/{repo} {distro}
```

See `gen-dockerfile --help` for supported distros/types. Keep this PART in sync whenever
the templates change.

## Template inventory

| Template | Final stage | Init / PID 1 | Base OS |
|----------|-------------|--------------|---------|
| `alpine.template` | `scratch.template` | tini | Alpine |
| `debian.template` | `scratch.template` | tini | Debian |
| `ubuntu.template` | `scratch.template` | tini | Ubuntu |
| `rhel.template` | `scratch.template` | tini | AlmaLinux |
| `archlinux.template` | `scratch.template` | tini | Arch Linux (multi-arch note below) |
| `web.template` | `systemd.template` | `/sbin/init` | Debian |
| `xorg.template` | `systemd.template` | `/sbin/init` | Debian |

## Final-stage templates

`scratch.template` — all non-GUI templates.
- `ENTRYPOINT [ "tini", "-p", "SIGTERM","--", "/usr/local/bin/entrypoint.sh" ]`
- `STOPSIGNAL SIGRTMIN+3`

`systemd.template` — `web` and `xorg` (systemd is PID 1; tini is redundant).
- `ENTRYPOINT [ "/sbin/init" ]`
- `STOPSIGNAL SIGRTMIN+3`
- No `tini_provider` stage, no `COPY --from=tini_provider` line.

Both are identical apart from `ENTRYPOINT`. OCI labels, `ENV HOSTNAME`, and
`VOLUME`/`EXPOSE`/`HEALTHCHECK` are the same in both.

## OCI label standard

Both final-stage templates emit these labels (no others):

```
LABEL maintainer="${GEN_DOCKERFILE_MAINTAINER}"
LABEL org.opencontainers.image.vendor="${GEN_DOCKERFILE_VENDOR:-CasjaysDev}"
LABEL org.opencontainers.image.authors="${GEN_DOCKERFILE_AUTHOR:-CasjaysDev}"
LABEL org.opencontainers.image.licenses="${LICENSE}"
LABEL org.opencontainers.image.title="${IMAGE_NAME}"
LABEL org.opencontainers.image.description="Containerized version of ${IMAGE_NAME}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.version="${BUILD_VERSION}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.url="${GEN_DOCKERFILE_HUB_REPO}"
LABEL org.opencontainers.image.source="${GEN_DOCKERFILE_GIT_REPO}"
LABEL org.opencontainers.image.documentation="${GEN_DOCKERFILE_GIT_REPO}"
LABEL org.opencontainers.image.vcs-type="Git"
LABEL com.github.containers.toolbox="false"
```

Shell-expanded values (no `\`) are evaluated at template-render time by `gen-dockerfile`.
Dollar-escaped values (`\${...}`) become literal Docker `ARG`/`ENV` references in the
generated `Dockerfile`.

Resolved values for a `dockersrc` repo pushing to Docker Hub:

| Label | Value |
|-------|-------|
| `url` | `https://hub.docker.com/r/casjaysdev/{name}` — browsable Hub page; `gen-dockerfile` derives it from the registry host (`docker.io` → `hub.docker.com/r/`) |
| `source` | `https://github.com/dockersrc/{name}` |
| `documentation` | `https://github.com/dockersrc/{name}` |

Removed labels (never re-add):
- `org.opencontainers.image.base.name` — belongs on the base image, not this image
- `org.opencontainers.image.schema-version` — non-spec; redundant with `version`
- Any duplicate `authors` or `source` entries

## HOSTNAME convention

All templates set `ENV HOSTNAME="casjaysdevdocker-${IMAGE_NAME}"` in every stage that
declares it. The prefix is always `casjaysdevdocker-`, never `casjaysdev-`.

## `GEN_DOCKERFILE_APP_DIR` and pull URL logic

`GEN_DOCKERFILE_APP_DIR` is auto-detected by `gen-dockerfile` from the parent directory
of `$PWD` (the org the checkout lives in):

```bash
GEN_DOCKERFILE_APP_DIR="${GEN_DOCKERFILE_APP_DIR:-$(basename -- "$(dirname -- "$PWD")")}"
```

It selects the `GEN_DOCKER_SPECIFY_IMAGE_SOURCE_*` defaults:

- `casjaysdevdocker/*` repos → `FROM casjaysdev/<distro>:latest` (pre-built, multi-arch)
- `dockersrc/*` and all other orgs → `FROM <distro>:latest` (upstream official images)

Base repos always pull upstream — a base image never builds FROM itself. Override by
exporting `GEN_DOCKERFILE_APP_DIR` before calling `gen-dockerfile`.

## Arch Linux multi-arch (`archlinux.template`)

When building the base image (`GEN_DOCKERFILE_APP_DIR != "casjaysdevdocker"`), the
template emits a three-stage FROM for `linux/amd64` + `linux/arm64`:

```dockerfile
ARG TARGETARCH
ARG TARGETPLATFORM
FROM --platform=${TARGETPLATFORM} archlinux:latest AS base-amd64
FROM --platform=${TARGETPLATFORM} lopsided/archlinux-arm64v8:latest AS base-arm64
FROM base-${TARGETARCH} AS build
```

App repos pull `casjaysdev/archlinux`, a multi-arch manifest, so a single
`FROM ${PULL_URL}:${DISTRO_VERSION} AS build` suffices there.

## `web.template` packages

systemd + noVNC stack in the build stage:

```
systemd systemd-sysv dbus dbus-x11 procps
tigervnc-standalone-server novnc openbox xdotool
```

Default ports: `SERVICE_PORT="5800"`, `EXPOSE_PORTS="5800 5900"`.

## `xorg.template` packages

systemd + Xorg stack in the build stage:

```
systemd systemd-sysv dbus dbus-x11 procps
xserver-xorg x11-xserver-utils xinit
```

## `debian.template` / `ubuntu.template` — RUN continuation

The first `RUN` block must have `; \` after the `echo` line so
`export DEBIAN_FRONTEND=noninteractive` executes before `apt-get`:

```dockerfile
RUN set -e; \
  echo "Updating the system"; \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update && apt-get upgrade -yy && apt-get dist-upgrade -yy
```

Without the `; \` the export is a no-op and `apt-get` may prompt interactively.

## Template resolution order

1. `$GEN_DOCKERFILE_CONFIG_DIR/templates/<name>.template` (user override)
2. `/usr/local/share/CasjaysDev/scripts/templates/dockerfiles/<name>.template`
   (installed; `$CASJAYSDEVDIR/templates/dockerfiles/` in a dev checkout)

`template_options.source` is sourced after `__set_variables`, allowing template-specific
variable overrides.

---

# PART 3: TOOLING — gen-dockerfile & gen-script

## `gen-dockerfile`

```
Usage: gen-dockerfile [options] [dir] [template] [repo-name] [git-repo-url]
```

| Flag | Meaning |
|------|---------|
| `--update` | Rewrite `.env.scripts` (add/drop vars against the current template) and update ARG/LABEL lines in every `Dockerfile`/`Dockerfile.*`. Touches no other file. |
| `--nogit` | Do not init or commit a git repo — required inside an existing repo. |
| `--dir PATH` | Operate on / write output to PATH instead of `$PWD`. |
| `--template NAME` | Template to use (`alpine`, `debian`, `ubuntu`, `rhel`, `archlinux`, `scratch`, `web`, `xorg`). Defaults to `alpine`. |
| `--repo NAME` | Registry repo name (image basename). Defaults to the directory name. |
| `--org NAME` | Registry owner / GitHub org (`--user` is an alias). Prefix `git:` or `reg:` to scope to one system; bare value sets both. |
| `--registry URL` | Registry provider URL (e.g. `https://docker.io`). |
| `--tag VERSION` | Image version tag (default `latest`). |
| `--add-tags TAGS` | Comma-separated additional tags (`USE_DATE` = auto date tag). |
| `--distro-name IMG` | Base image pull URL (overrides `ENV_PULL_URL`). |
| `--distro-version T` | Base image tag (overrides `ENV_DISTRO_TAG`). |
| `--startup FILE` | Generate an init.d service script at `rootfs/usr/local/etc/docker/init.d/FILE` via `gen-script other/start-service`. |
| `--dockerfile` | Regenerate the Dockerfile only. |
| `--force` | Overwrite existing files without prompting. |

Resolution order when a value is not given by a flag: flags → git remote → project dirs →
defaults.

Special subcommand — `gen-dockerfile actions` writes `.gitea/workflows/build.yml`
(`build.{ver}.yml` for versioned tags) from the existing `Dockerfile` (PART 7).

Base repos update `Dockerfile` AND every `Dockerfile.*` variant on `--update`; the
matching `.env.scripts.{ver}` files carry per-variant values.

## `gen-script`

```
Usage: gen-script [options] [template] [filename]
```

| Flag / env var | Meaning |
|----------------|---------|
| `--dir PATH` | Write the generated file to `PATH/filename`. |
| `-n` / `--name VALUE` | Service name substituted into the template — fills `REPLACE_SERVICE_NAME` in `other/start-service`, pre-populating `SERVICE_NAME=` without a sed step. |
| `GEN_SCRIPT_OVERWRITE="Y"` | Overwrite the output without prompting (default `"A"` = ask). Required when the target exists, even with `GEN_SCRIPT_EDITFILE="N"`. |
| `GEN_SCRIPT_EDITFILE="N"` | Suppress the interactive editor after generation. `-e`/`--no` sets BOTH this AND `GEN_SCRIPT_OVERWRITE="Y"`; the env var alone does not. |
| `other/start-service` | Template path — positional arg 1, slash-joined words, matching the `@@Template` header. |
| `filename` | Output basename — positional arg 2, combined with `--dir`. |

Other flags: `-k`/`--keep` (never overwrite), `--replace` (new header replaces old),
`-d`/`--desc` (header description), `-p`/`--prev` (copy header metadata from a file).

---

# PART 4: `.env.scripts` REFERENCE

Generated at the repo root; sourced by `gen-dockerfile` and by CI at build time. Base
repos carry one per variant (`.env.scripts` + `.env.scripts.{ver}`). It is a pure
`KEY="value"` file — no logic.

## Variables

| Variable | Purpose |
|----------|---------|
| `ENV_DOCKERFILE` | Dockerfile the variant builds (`Dockerfile` or `Dockerfile.{ver}`) |
| `ENV_REGISTRY_REPO` | Image name in the registry (`{name}`) |
| `ENV_REGISTRY_ORG` | Registry namespace — `casjaysdev` for base repos |
| `ENV_REGISTRY_URL` | Registry base URL (`https://docker.io`) — pull/push host, never a label URL |
| `ENV_REGISTRY_PUSH` | Full push path `org/repo` (`casjaysdev/{name}`) |
| `ENV_ADD_IMAGE_PUSH` | Extra push destinations |
| `ENV_GIT_REPO_URL` | Full Git repo URL — `https://github.com/dockersrc/{name}`; feeds the `source`/`documentation` labels, so a wrong value here regresses labels on regeneration |
| `ENV_USE_TEMPLATE` | Template name (`alpine`, `debian`, …) |
| `ENV_PULL_URL` | Base image to pull FROM |
| `ENV_DISTRO_TAG` | Tag for the pull image |
| `ENV_IMAGE_TAG` | Default image tag (`latest`, or the variant version) |
| `ENV_ADD_TAGS` | Additional comma-separated tags; `USE_DATE` auto-generates a date tag |
| `ENV_PACKAGES` | Space-separated package list |
| `ENV_VENDOR` / `ENV_AUTHOR` / `ENV_MAINTAINER` | Label metadata |
| `SERVICE_PORT` | Primary exposed port (empty for pure base images) |
| `EXPOSE_PORTS` | Additional exposed ports |
| `LANG_VERSION` | Language runtime version (toolchain repos) |
| `PHP_VERSION` / `NODE_VERSION` / `NODE_MANAGER` | Runtime versions (`system` default) |
| `WWW_ROOT_DIR` | Web root (`/usr/local/share/httpd/default`) |
| `DOCKER_ENTYPOINT_PORTS_WEB` / `DOCKER_ENTYPOINT_PORTS_SRV` | Ports passed to the entrypoint |
| `DOCKER_ENTYPOINT_HEALTH_APPS` / `DOCKER_ENTYPOINT_HEALTH_ENDPOINTS` | Healthcheck targets |

## Legacy variable auto-migration

`gen-dockerfile` calls `__migrate_env_script` on every run, renaming old variables:

| Old name | Current name |
|----------|-------------|
| `ENV_IMAGE_NAME` | `ENV_REGISTRY_REPO` |
| `ENV_IMAGE_PUSH` | `ENV_REGISTRY_PUSH` |
| `ENV_HUB_BASE` | `ENV_REGISTRY_URL` |
| `ENV_ORG_NAME` | `ENV_REGISTRY_ORG` |

Never use the old names in new files. Retired variables that must not reappear anywhere:
`DEFAULT_TEMPLATE_DIR`, `DEFAULT_FILE_DIR`, `DEFAULT_DATA_DIR`, `DEFAULT_CONF_DIR`.

---

# PART 5: RUNTIME SYSTEM — SETUP SCRIPTS, ENTRYPOINT, INIT.D

## Build-time setup scripts (`rootfs/root/docker/setup/`)

Run in order inside the build stage:

| Script | Role |
|--------|------|
| `00-init.sh` | Initialize base directory structure and environment |
| `01-system.sh` | Repos, locales, timezone, system settings |
| `02-packages.sh` | App-specific packages, package managers, language runtimes |
| `03-files.sh` | Install staged files (`rootfs/tmp/etc/*` → `/etc/*`), permissions, symlinks |
| `04-users.sh` | Create service users/groups |
| `05-custom.sh` | Application/toolchain-specific install logic |
| `06-post.sh` | Post-install configuration |
| `07-cleanup.sh` | Remove build deps, caches, temp files |

**`05-custom.sh` ownership:** the upstream template ships an empty stub. Any repo whose
`05-custom.sh` has a real body (e.g. a toolchain repo's install logic) owns that content —
it exists only in the repo's git history, never in the template. On regeneration, keep the
existing body and pull forward only boilerplate (version-stamp header, `set` line,
shellcheck-disable line). The same rule applies to any other `0*.sh` found to contain real
logic beyond the stub.

## Entrypoint flow

```
tini → /usr/local/bin/entrypoint.sh
├─ Load /usr/local/etc/docker/functions/entrypoint.sh
├─ Source env: /root/env.sh, /usr/local/etc/docker/env/*.sh, /config/env/*.sh
├─ Seed /config and /data on first run
├─ __start_init_scripts — source every init.d/*.sh in sort order
├─ Handle `healthcheck` command
└─ Execute main application
```

`rootfs/usr/local/bin/` generated set: `entrypoint.sh`, `pkmgr`, `symlink`, `copy`,
`healthcheck`. `pkmgr` wraps the native package manager (`apk`, `apt-get`, `dnf`,
`pacman`) behind `pkmgr update|install|remove|clean`.

## App-specific bin scripts

Extra scripts in `rootfs/usr/local/bin/` that `gen-dockerfile` does not generate are
repo-owned. Their `@@Template` header governs maintenance:

- `@@Template : shell/sh` — boilerplate synced from `$TEMPLATE_DIR/scripts/shell/sh`;
  `#!/usr/bin/env sh`, `set -e` only (`pipefail` is a bashism — must NOT appear)
- `@@Template : shell/bash` — synced from `shell/bash`; `set -eo pipefail` required
- No `@@Template` header — hand-written; never modified by tooling

## init.d scripts — critical rules

**Each service gets its own numbered init.d script. Never merge or remove services.**
`__start_init_scripts` sources every `*.sh` in sort order — multi-process repos have one
script per daemon (`01-named.sh`, `02-nginx.sh`, `03-php-fpm.sh`, …).

init.d scripts are **regenerated, never patched in place** — old copies may call functions
removed from the current `functions/entrypoint.sh`. Generate fresh via
`gen-script other/start-service` (or `gen-dockerfile --startup`), then restore the
app-specific values. They are `#!/usr/bin/env bash` with `set -eo pipefail`.

Required variables in every init.d script:

```bash
SERVICE_NAME="myapp"
EXEC_CMD_BIN='myapp'
EXEC_CMD_ARGS=''
EXEC_PRE_SCRIPT=''
SERVICE_USES_PID=''
IS_WEB_SERVER="no"
IS_DATABASE_SERVICE="no"
USES_DATABASE_SERVICE="no"
DATABASE_SERVICE_TYPE="sqlite"
RUNAS_USER="root"
```

Directory variables:

```bash
DATA_DIR="/data/$SERVICE_NAME"
CONF_DIR="/config/$SERVICE_NAME"
ETC_DIR="/etc/$SERVICE_NAME"
LOG_DIR="/data/logs/$SERVICE_NAME"
TMP_DIR="/tmp/$SERVICE_NAME"
RUN_DIR="/run/$SERVICE_NAME"
ROOT_FILE_PREFIX="/config/secure/auth/root"
USER_FILE_PREFIX="/config/secure/auth/user"
```

## Hook functions

The `start-service` template generates all outer hooks fully implemented — customise via
the matching `*_local()` stub, which each outer hook calls automatically if defined:

| Outer hook (do not redefine) | Customise via |
|------------------------------|---------------|
| `__run_precopy` | `__run_precopy_local` |
| `__execute_prerun` | `__execute_prerun_local` |
| `__run_pre_execute_checks` | `__run_pre_execute_checks_local` |
| `__update_conf_files` | `__update_conf_files_local` |
| `__pre_execute` | `__pre_execute_local` |
| `__post_execute` | `__post_execute_local` |
| `__pre_message` | `__pre_message_local` |
| `__update_ssl_conf` | `__update_ssl_conf_local` |
| `__create_service_env` | — |
| `__run_start_script` | — |
| `__run_secure_function` | — |

## PID sentinel guard

Every init.d script must guard on exactly this sentinel — leading dot, no underscores in
the filename portion; any other form silently skips the guard:

```bash
if [ ! -f "/run/.start_init_scripts.pid" ]; then
  echo "__start_init_scripts function hasn't been Initialized" >&2
  SERVICE_IS_RUNNING="no"
  __script_exit 1
fi
```

## Volumes

- `/config` — persistent configuration
- `/data` — persistent application data

---

# PART 6: README.md STANDARD LAYOUT

Base image layout (`dockersrc/{name}` → `casjaysdev/{name}`). Substitute `{name}`;
this repo family has no `-p` port mappings unless `SERVICE_PORT` is set in
`.env.scripts` — omit all port sections when it is empty.

````markdown
## 👋 Welcome to {name} 🚀

{name} README


## Install my system scripts

```shell
 sudo bash -c "$(curl -q -LSsf "https://github.com/systemmgr/installer/raw/main/install.sh")"
 sudo systemmgr --config && sudo systemmgr install scripts
```

## Automatic install/update

```shell
dockermgr update os {name}
```

## Install and run container

```shell
mkdir -p "/var/lib/srv/root/docker/casjaysdev/{name}/latest"
git clone "https://github.com/dockermgr/{name}" "$HOME/.local/share/CasjaysDev/dockermgr/{name}"
cp -Rfva "$HOME/.local/share/CasjaysDev/dockermgr/{name}/rootfs/." "/var/lib/srv/root/docker/casjaysdev/{name}/latest/"
docker run -d \
--restart always \
--privileged \
--name casjaysdev-{name}-latest \
--hostname {name} \
-e TZ=${TIMEZONE:-America/New_York} \
-v "/var/lib/srv/root/docker/casjaysdev/{name}/latest/data:/data:z" \
-v "/var/lib/srv/root/docker/casjaysdev/{name}/latest/config:/config:z" \
casjaysdev/{name}:latest
```

## via docker-compose

```yaml
version: "2"
services:
  ProjectName:
    image: casjaysdev/{name}
    container_name: casjaysdev-{name}-latest
    environment:
      - TZ=America/New_York
      - HOSTNAME={name}
    volumes:
      - "/var/lib/srv/root/docker/casjaysdev/{name}/latest/data:/data:z"
      - "/var/lib/srv/root/docker/casjaysdev/{name}/latest/config:/config:z"
    restart: always
```

## Get source files

```shell
dockermgr download src os {name}
```

## Build container

```shell
git clone "https://github.com/dockersrc/{name}" "$HOME/Projects/github/dockersrc/{name}"
cd "$HOME/Projects/github/dockersrc/{name}" && buildx all
```

## Authors

🤖 casjay: [Github](https://github.com/casjay) 🤖
⛵ casjaysdev: [Github](https://github.com/dockersrc) [Docker](https://hub.docker.com/u/casjaysdev) ⛵
````

---

# PART 7: CI/CD WORKFLOWS

## Generated workflow (`gen-dockerfile actions`)

`gen-dockerfile actions` writes `.gitea/workflows/build.yml` from the current
`Dockerfile`; versioned variants get `build.{ver}.yml` (named `Build and Push {ver}`, no
schedule trigger, fixed version tag only). All actions are SHA-pinned — never tag-pinned.

- **Triggers:** `push` to `main`, monthly schedule, `workflow_dispatch`
- **Registry strategy:** always logs in to the Gitea registry via the auto-provided
  `GITEA_TOKEN`; conditionally logs in to Docker Hub when `vars.DOCKER_USERNAME` is set
  (`vars.DOCKER_USERNAME` + `secrets.DOCKER_PASSWORD`; `vars.DOCKER_REGISTRY` overrides
  the registry, `vars.DOCKER_ORG` the namespace)
- **Platforms:** `linux/amd64,linux/arm64`
- **build-args:** only `BUILD_DATE`, `GIT_COMMIT`, `BUILD_VERSION`
- **Tags pushed:** date tag (`yymm`) + `latest` (or the fixed variant version) to both
  registries
- **Annotations:** mirror the OCI label standard (PART 2), with `url`/`source`/
  `documentation` set to the workflow's repository URL

## Legacy workflow (`docker.yaml`)

A hand-crafted `.gitea/workflows/docker.yaml` may exist in older repos — reference copy in
the org-level `.github` repo. **Never overwrite it, and never use it as a template for new
work** — it uses tag-pinned actions and retired secret names. All new/updated workflows
come from `gen-dockerfile actions`.

---

# PART 8: VERIFICATION & COMMIT

## Syntax gates

Every touched script must pass before commit:

```bash
for f in rootfs/usr/local/bin/*; do
  [ -f "$f" ] || continue
  case "$(head -1 "$f")" in
    *bash*) bash -n "$f" || exit 1 ;;
    *sh*)   sh -n "$f"   || exit 1 ;;
  esac
done

bash -n rootfs/usr/local/etc/docker/functions/entrypoint.sh

for f in rootfs/root/docker/setup/0*.sh rootfs/usr/local/etc/docker/init.d/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" || exit 1
done
```

## Dead-reference gates

After any regeneration:

1. No script references an env var removed from `.env.scripts` (diff-driven check).
2. No script calls a function absent from both the current
   `functions/entrypoint.sh` and the script itself.
3. No `__copy_templates` calls remain (retired with `DEFAULT_TEMPLATE_DIR`).

## Commit

```bash
git status --porcelain
git diff --stat
```

Write `.git/COMMIT_MESS` from the actual diff — subject ≤64 chars, body as
`- path: change` bullets covering every changed file. Then:

```bash
gitcommit --dir "$(git rev-parse --show-toplevel)" all
```

`git commit` / `git push` directly are forbidden. Never commit with a failing syntax
gate.
