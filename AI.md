# AI.md — Docker Template Update Runbook

Run this whenever upstream templates in `casjay-dotfiles/scripts` are updated.
This file is **permanent** — do not delete it. It is the maintenance runbook for this repo.

---

## What This Runbook Does

The upstream Docker templates in `casjay-dotfiles/scripts` change over time. Generated files that
are left in place may call removed functions, source removed templates, or reference removed env
vars — causing runtime failures. This runbook brings every generated file in the repo up to date.

Files updated:

- `.env.scripts` — vars synced to current template (added/removed)
- `Dockerfile` / `Dockerfile.*` — removed ARG lines dropped, new ones added
- `rootfs/usr/local/bin/*` — all template-generated bin scripts replaced from temp dir
- `rootfs/usr/local/etc/docker/functions/entrypoint.sh` — replaced from temp dir
- `rootfs/usr/local/etc/docker/init.d/*.sh` — regenerated; app-specific values restored
- `rootfs/root/docker/setup/00-*.sh` through `07-*.sh` — replaced from temp dir
- `README.md` — rewritten to current standard layout
- Non-standard rootfs root-level directories — files migrated; stale dirs removed

---

## Tool Reference

### `gen-dockerfile`

```
Usage: gen-dockerfile [options] [dir] [template] [repo-name] [git-repo-url]
```

Flags used in this runbook:

| Flag | Meaning |
|------|---------|
| `--update` | Rewrite `.env.scripts` (add/drop vars against current template) and update ARG/LABEL lines in every `Dockerfile`/`Dockerfile.*`. Does not touch any other file. |
| `--nogit` | Do not init or commit a git repo — required when running inside an existing repo. |
| `--dir PATH` | Operate on / write output to PATH instead of `$PWD`. |
| `--template NAME` | Template to use (`alpine`, `debian`, `rhel`, `scratch`, `web`, `xorg`). Defaults to `alpine` if omitted. |
| `--repo NAME` | Registry repo name (image basename). Defaults to the directory name if omitted. |
| `--org NAME` | Alias for `--user`. Sets the registry owner / GitHub org. |

Resolution order when a value is not given by a flag: flags → git remote → project dirs → defaults.

### `gen-script`

```
Usage: gen-script [options] [template] [filename]
```

Flags and env vars used in this runbook:

| Flag / env var | Meaning |
|----------------|---------|
| `--dir PATH` | Write the generated file to PATH instead of `$PWD`. The output file is `PATH/filename`. |
| `-n` / `--name VALUE` | Sets the service name substituted into the generated file. In the `other/start-service` template this fills `REPLACE_SERVICE_NAME` — e.g. `--name nginx` pre-populates `SERVICE_NAME=nginx` in the output without a separate `sed` step. |
| `GEN_SCRIPT_OVERWRITE="Y"` | Overwrite the output file without prompting. Default is `"A"` (ask). Must be set when the target file already exists or gen-script will prompt even with `GEN_SCRIPT_EDITFILE="N"`. |
| `GEN_SCRIPT_EDITFILE="N"` | Suppress the interactive editor prompt after generation. Note: `-e`/`--no` sets BOTH this AND `GEN_SCRIPT_OVERWRITE="Y"` in one flag; setting this env var alone does NOT set OVERWRITE. |
| `other/start-service` | Template path — words joined by `/`, matching the `@@Template` header in the existing script. This arg is positional (first non-flag arg). |
| `filename` | Output file basename — second positional arg. Combined with `--dir` to form the full output path. |

Other available flags (for reference, not used in this runbook):

| Flag | Meaning |
|------|---------|
| `-k` / `--keep` | Do not overwrite an existing file. |
| `--replace` | Import and create a new header to replace an older one. |
| `-d` / `--desc` | Set the description in the generated file header. |
| `-p` / `--prev` | Set the header based on an existing file (copies its metadata). |

---

## Session Start

```bash
git status --porcelain
# If dirty:
git stash push -m "session-start auto-stash"
git pull
# If stashed:
git stash pop
# If stash pop conflicts: report the conflicting files and stop — never auto-resolve
```

If `git pull` fails (no remote, offline, diverged): report it and stop.

---

## Variables

```bash
name="$(basename "$PWD")"
SCRIPTS_DIR="${CASJAYSDEVDIR:-/usr/local/share/CasjaysDev/scripts}"
TEMPLATE_DIR="$SCRIPTS_DIR/templates"

# Detect repo type: base repos (dockersrc) have Dockerfile.* variant files
if find . -maxdepth 1 -name 'Dockerfile.*' -type f | grep -q -- .; then
  REPO_TYPE="base"
  org="dockersrc"
else
  REPO_TYPE="app"
  org="casjaysdevdocker"
fi
```

---

## Step 1 — Sync `.env.scripts` and Dockerfile ARG lines

Run for **all** repos (both app and base):

```bash
gen-dockerfile --update --nogit --dir .
```

This rewrites `.env.scripts` against the current dotenv template: adds vars the template now
includes, drops vars it no longer includes (e.g. `DEFAULT_TEMPLATE_DIR`, `DEFAULT_FILE_DIR`,
`DEFAULT_DATA_DIR`, `DEFAULT_CONF_DIR`), and preserves all project-specific values
(`ENV_REGISTRY_REPO`, `ENV_USE_TEMPLATE`, `ENV_PACKAGES`, etc.).

It also updates ARG lines in every Dockerfile:
- App repos (`REPO_TYPE=app`): updates `Dockerfile` only — `ARG IMAGE_NAME=`, `ARG IMAGE_REPO=`,
  `LABEL org.opencontainers.*`, and any removed ARG lines.
- Base repos (`REPO_TYPE=base`): same changes applied to `Dockerfile` AND all `Dockerfile.*`
  variant files.

All other file content is untouched.

After running, capture the list of removed vars for use in Step 5:

```bash
removed_vars="$(git diff .env.scripts | grep -- '^-[A-Z_][A-Z0-9_]*=' | sed 's/^-//' | cut -d= -f1)"
printf 'Removed vars: %s\n' "$removed_vars"
```

---

## Step 2 — Regenerate all rootfs files from temp dir

Generate a complete fresh tree into a temp dir. Every file produced here is the authoritative
replacement for its counterpart in this repo — old copies may reference removed functions or
templates and will cause runtime failures if left in place.

```bash
tmpdir="$(mktemp -d "/tmp/gen-${name}-XXXXXX")"

if [ "$REPO_TYPE" = "app" ]; then
  template="$(grep -- '^ENV_USE_TEMPLATE=' .env.scripts | cut -d= -f2 | tr -d '"')"
else
  template="$(grep -- 'using the' Dockerfile | head -1 | sed 's/.*using the \([^ ]*\) template.*/\1/')"
fi

gen-dockerfile --dir "$tmpdir" --nogit --template "$template" --repo "$name" --org "$org"
```

Copy every file the temp dir produced that already exists in this repo — skip nothing:

```bash
find "$tmpdir/rootfs" -type f | while read -r src; do
  rel="${src#"$tmpdir/rootfs/"}"
  dest="rootfs/$rel"
  if [ -f "$dest" ]; then
    cp -f "$src" "$dest"
  fi
done

rm -rf "$tmpdir"
```

This covers: `rootfs/usr/local/bin/entrypoint.sh`, `rootfs/usr/local/bin/pkmgr`,
`rootfs/usr/local/bin/symlink`, `rootfs/usr/local/bin/copy`, `rootfs/usr/local/bin/healthcheck`,
`rootfs/usr/local/etc/docker/functions/entrypoint.sh`,
`rootfs/root/docker/setup/00-*.sh` through `07-*.sh`, and every other file gen-dockerfile
generates. The copy condition (`-f "$dest"`) means files not already in this repo are not
added — only existing files are updated.

---

## Step 3 — Update app-specific bin scripts

Some repos have extra scripts in `rootfs/usr/local/bin/` that gen-dockerfile does not generate —
they are app-specific (e.g. `check-record`, `get_dns_record`). These were not touched in Step 2.

For each such script, read its `@@Template` header (line beginning `# @@Template`):

**Has `@@Template : shell/sh`**
Update boilerplate in-place from `$TEMPLATE_DIR/scripts/shell/sh`. Read the template, diff
against the existing script, apply only the boilerplate changes (version stamp, shellcheck
disable line, set line, trap lines). These are `#!/usr/bin/env sh` scripts — `set -e` is correct;
`-o pipefail` is a bashism and must NOT appear. The app-specific logic body is untouched.

**Has `@@Template : shell/bash`** (or another template path)
Same process, using the matching template file. These are `#!/usr/bin/env bash` scripts —
`set -eo pipefail` is required.

**No `@@Template` header**
Hand-written app logic. Do not modify it.

After each edit run the appropriate syntax check:

```bash
# sh scripts
sh -n "$script"
# bash scripts
bash -n "$script"
```

---

## Step 4 — Regenerate `init.d/*.sh`

`init.d/*.sh` scripts must be regenerated from the current template — never updated in-place.
Old copies may call functions that have since been removed from `entrypoint.sh`, causing failures.
Each script also contains app-specific content that must be preserved; extract it before
regenerating and restore it into the new file.

For each `*.sh` in `rootfs/usr/local/etc/docker/init.d/` with `@@Template : other/start-service`
in its header:

**1. Read the existing script AND `$TEMPLATE_DIR/scripts/other/start-service`.**

Diff the two. Every line or block present in the existing script but absent from the template is
app-specific content. Record all of it. It typically includes:

- `SERVICE_NAME=` value
- `EXEC_CMD_BIN=` value
- `EXEC_CMD_ARGS=` value
- `DATA_DIR=`, `CONF_DIR=`, `ETC_DIR=`, `TMP_DIR=`, `RUN_DIR=`, `LOG_DIR=` values
- `SERVICE_USER=` and `SERVICE_GROUP=` values
- Extra `export` or variable declarations for this service
- Service-specific env file sourcing (e.g. `. "/config/env/nginx.sh"`)
- Custom code inside function bodies (pre-start checks, post-start waits, etc.)
- App-specific functions defined at the top of the file (e.g. `__rndc_key`, `__tsig_key`)

**2. Regenerate from the template:**

```bash
init_d_dir="rootfs/usr/local/etc/docker/init.d"
filename="$(basename "$init_script")"
svcname="$(grep -- '^SERVICE_NAME=' "$init_script" | cut -d= -f2 | tr -d '"')"
# GEN_SCRIPT_OVERWRITE="Y"  — overwrite the existing file without prompting (default is "A"/ask)
# GEN_SCRIPT_EDITFILE="N"   — suppress the interactive editor after generation
# --dir                     — write the output file to init_d_dir/filename
# --name                    — pre-fills REPLACE_SERVICE_NAME in the template with the service name,
#                             so SERVICE_NAME= is correct in the generated file without a separate sed step
# other/start-service       — template path (positional arg 1, slash-joined words)
# "$filename"               — output file basename (positional arg 2); combined with --dir for full path
GEN_SCRIPT_OVERWRITE="Y" GEN_SCRIPT_EDITFILE="N" gen-script --dir "$init_d_dir" --name "$svcname" other/start-service "$filename"
```

The regenerated file is `#!/usr/bin/env bash` — it must use `set -eo pipefail`. If gen-script
emits `set -e` only, fix it:

```bash
sed -i 's/^set -e$/set -eo pipefail/' "$init_d_dir/$filename"
```

**3. Restore all app-specific content.**

`SERVICE_NAME` is already correct — `--name "$svcname"` pre-filled it during generation.
For all other app-specific `KEY=value` lines recorded in step 1:

```bash
sed -i "s|^EXEC_CMD_BIN=.*|EXEC_CMD_BIN=\"/usr/sbin/named\"|" "$init_d_dir/$filename"
sed -i "s|^EXEC_CMD_ARGS=.*|EXEC_CMD_ARGS=\"-f -u named\"|"   "$init_d_dir/$filename"
```

For multi-line function bodies and custom functions, use Edit to splice them into the correct
location (same function or section they occupied before).

The final script must:
- Only call functions defined in the current `rootfs/usr/local/etc/docker/functions/entrypoint.sh`
  or defined within the script itself
- Contain all app-specific variable values and custom logic from the old version
- Pass `bash -n "$init_d_dir/$filename"` with no errors

---

## Step 5 — Audit for dead variable and function references

After regeneration, app-specific code preserved in Steps 3 and 4 may still reference env vars
removed in Step 1 or functions no longer present in the current `entrypoint.sh`. Find and fix
every such reference before committing.

### 5a — Dead env var references

Use `$removed_vars` captured in Step 1. For each removed var, search all scripts:

```bash
for var in $removed_vars; do
  grep -rn -- "\$$var\|\${$var" rootfs/ 2>/dev/null | grep -v -- '\.git'
done
```

Fix every hit based on context:

| Removed var | Replacement |
|-------------|-------------|
| `DEFAULT_TEMPLATE_DIR` | Remove the code that used it. The `template-files` directory no longer exists. If the code was copying default configs into `/config` or `/etc`, the entrypoint now handles that from `rootfs/tmp/etc/` at container start. |
| `DEFAULT_FILE_DIR` | Same as above — remove usages. |
| `DEFAULT_CONF_DIR` | Replace with `${CONF_DIR:-/etc/$SERVICE_NAME}` or the service-specific hardcoded path. |
| `DEFAULT_DATA_DIR` | Replace with `${DATA_DIR:-/var/$SERVICE_NAME}` or the service-specific path. |
| Any other removed var | Determine from context whether to remove the block or substitute the correct current var. |

Also search for `__copy_templates` calls — that function copied from `$DEFAULT_TEMPLATE_DIR`
and is now a no-op since the directory is gone. Remove any call to it in app-specific code:

```bash
grep -rn -- '__copy_templates' rootfs/usr/local/etc/docker/init.d/ rootfs/usr/local/bin/
```

### 5b — Dead function calls

The fresh `rootfs/usr/local/etc/docker/functions/entrypoint.sh` from Step 2 is the ground truth
for what functions are available at container runtime. Extract all defined names:

```bash
defined_fns="$(grep -oE -- '^__[a-zA-Z_]+' \
  rootfs/usr/local/etc/docker/functions/entrypoint.sh | sort -u)"
```

For each script NOT fully replaced from the temp dir (init.d scripts, custom bin scripts), find
calls to functions that are neither in `$defined_fns` nor defined within the script itself:

```bash
for script in rootfs/usr/local/etc/docker/init.d/*.sh rootfs/usr/local/bin/*; do
  [ -f "$script" ] || continue
  local_fns="$(grep -oE -- '^__[a-zA-Z_]+' "$script" | sort -u)"
  grep -oE -- '__[a-zA-Z_]+' "$script" | sort -u | while read -r fn; do
    if ! printf '%s\n' $defined_fns $local_fns | grep -qx -- "$fn"; then
      printf 'DEAD: %s in %s\n' "$fn" "$script"
    fi
  done
done
```

For each dead call found:

- Check whether the function was renamed in the current template (e.g. `__get_ip` → `__get_ip4`
  or `__get_ip6`) and update the call.
- If the function was removed with no replacement, remove the call and any surrounding block
  that only makes sense with it.
- When unsure, check `$TEMPLATE_DIR/scripts/` for the current equivalent.

Fix every dead reference before proceeding.

---

## Step 6 — Update README.md

Rewrite `README.md` to match the current state. Use the existing file as a base; update any stale
values (wrong image name, wrong org, wrong ports).

Read `SERVICE_PORT` from `.env.scripts` for the port value (app repos). Omit all `-p` and
`ports:` sections when `SERVICE_PORT` is empty or unset.

### App container layout (`casjaysdevdocker/{name}`)

```markdown
## 👋 Welcome to {name} 🚀

{name} README


## Install my system scripts

```shell
 sudo bash -c "$(curl -q -LSsf "https://github.com/systemmgr/installer/raw/main/install.sh")"
 sudo systemmgr --config && sudo systemmgr install scripts
```

## Automatic install/update

```shell
dockermgr update {name}
```

## Install and run container

```shell
dockerHome="/var/lib/srv/$USER/docker/casjaysdevdocker/{name}/{name}/latest/rootfs"
mkdir -p "/var/lib/srv/$USER/docker/{name}/rootfs"
git clone "https://github.com/dockermgr/{name}" "$HOME/.local/share/CasjaysDev/dockermgr/{name}"
cp -Rfva "$HOME/.local/share/CasjaysDev/dockermgr/{name}/rootfs/." "$dockerHome/"
docker run -d \
--restart always \
--privileged \
--name casjaysdevdocker-{name}-latest \
--hostname {name} \
-e TZ=${TIMEZONE:-America/New_York} \
-v "$dockerHome/data:/data:z" \
-v "$dockerHome/config:/config:z" \
-p {port}:{port} \
casjaysdevdocker/{name}:latest
```

## via docker-compose

```yaml
version: "2"
services:
  ProjectName:
    image: casjaysdevdocker/{name}
    container_name: casjaysdevdocker-{name}
    environment:
      - TZ=America/New_York
      - HOSTNAME={name}
    volumes:
      - "/var/lib/srv/$USER/docker/casjaysdevdocker/{name}/{name}/latest/rootfs/data:/data:z"
      - "/var/lib/srv/$USER/docker/casjaysdevdocker/{name}/{name}/latest/rootfs/config:/config:z"
    ports:
      - {port}:{port}
    restart: always
```

## Get source files

```shell
dockermgr download src casjaysdevdocker/{name}
```

OR

```shell
git clone "https://github.com/casjaysdevdocker/{name}" "$HOME/Projects/github/casjaysdevdocker/{name}"
```

## Build container

```shell
cd "$HOME/Projects/github/casjaysdevdocker/{name}"
buildx
```

## Authors

🤖 casjay: [Github](https://github.com/casjay) 🤖
⛵ casjaysdevdocker: [Github](https://github.com/casjaysdevdocker) [Docker](https://hub.docker.com/u/casjaysdevdocker) ⛵
```

### Base image layout (`dockersrc/{name}`)

```markdown
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
```

---

## Step 7 — Clean up non-standard rootfs directories

The only valid directories at the `rootfs/` root level are `root/`, `tmp/`, and `usr/`. Any other
directory is a leftover from old patterns and must be cleaned up.

Find non-standard dirs:

```bash
find rootfs -maxdepth 1 -mindepth 1 -type d | grep -vE -- 'rootfs/(root|tmp|usr)$'
```

**If the directory contains only `.gitkeep` (empty placeholder):** remove it directly.

```bash
rm -rf "rootfs/{dir}"
```

**If the directory contains actual files:** migrate them to the correct location first, then remove.

Migration path map:

| Old rootfs path | Correct rootfs path |
|-----------------|---------------------|
| `rootfs/etc/{path}` | `rootfs/tmp/etc/{path}` |
| `rootfs/config/{path}` | `rootfs/tmp/etc/{path}` |
| `rootfs/data/{path}` | `rootfs/tmp/var/{path}` |
| `rootfs/var/{path}` | `rootfs/tmp/var/{path}` |
| `rootfs/opt/{path}` | `rootfs/tmp/opt/{path}` |
| `rootfs/share/{path}` | `rootfs/usr/local/share/{path}` |

Migration pattern (adapt `src_dir` and `dest_dir` per the table above):

```bash
src_dir="rootfs/etc"
dest_dir="rootfs/tmp/etc"
find "$src_dir" -type f | while read -r src; do
  rel="${src#"$src_dir/"}"
  dest="$dest_dir/$rel"
  mkdir -p "$(dirname -- "$dest")"
  mv "$src" "$dest"
done
rm -rf "$src_dir"
```

Also remove `rootfs/usr/local/share/template-files/` if it exists — the `DEFAULT_TEMPLATE_DIR`,
`DEFAULT_FILE_DIR`, `DEFAULT_DATA_DIR`, and `DEFAULT_CONF_DIR` variables were removed from the
template and this directory is no longer used at build time:

```bash
rm -rf rootfs/usr/local/share/template-files
```

---

## Step 8 — Verify

Run syntax checks on every script that was touched. Fix all failures before committing.

```bash
# bin scripts (check shebang to pick the right interpreter)
for f in rootfs/usr/local/bin/*; do
  [ -f "$f" ] || continue
  case "$(head -1 "$f")" in
    *bash*) bash -n "$f" && printf 'OK: %s\n' "$f" || printf 'FAIL: %s\n' "$f" ;;
    *sh*)   sh -n "$f"   && printf 'OK: %s\n' "$f" || printf 'FAIL: %s\n' "$f" ;;
  esac
done

# entrypoint.sh and setup scripts are bash
bash -n rootfs/usr/local/etc/docker/functions/entrypoint.sh

for f in rootfs/root/docker/setup/0*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" && printf 'OK: %s\n' "$f" || printf 'FAIL: %s\n' "$f"
done

# init.d scripts are bash
for f in rootfs/usr/local/etc/docker/init.d/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" && printf 'OK: %s\n' "$f" || printf 'FAIL: %s\n' "$f"
done
```

---

## Step 9 — Commit

Check what actually changed:

```bash
git status --porcelain
git diff --stat
```

Write `.git/COMMIT_MESS` listing only the files that actually changed per `git diff --stat`.
Subject line ≤64 chars. Body as `- path: change` bullets. Include only what changed in this run.

Example template (adjust bullets to match actual diff):

```
✨ Update to latest docker template revision ✨

- .env.scripts: synced vars to current template
- Dockerfile: removed stale ARG lines, updated IMAGE_NAME/REPO/LABEL
- rootfs/usr/local/bin/*: regenerated from current template via gen-dockerfile
- rootfs/usr/local/etc/docker/functions/entrypoint.sh: replaced from template
- rootfs/usr/local/etc/docker/init.d/*.sh: regenerated; app-specific values restored
- rootfs/root/docker/setup/: regenerated from current template
- README.md: updated to current standard layout
- rootfs/{old-dirs}: files migrated to rootfs/tmp/; stale directories removed
```

Then commit:

```bash
gitcommit --dir "$(git rev-parse --show-toplevel)" all
```
