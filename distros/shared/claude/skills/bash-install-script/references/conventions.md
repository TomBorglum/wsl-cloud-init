# Install script conventions

These conventions make a tool-install script robust: strict-mode, fail-fast on a
bad environment, idempotent on re-runs, and self-contained. Follow them so a new
script behaves predictably wherever it runs.

## Output location and naming

- The target **directory is supplied by the user** — there is no fixed location.
- Filename: `NN-install-<tool-name>.sh`.
- `NN` — the next free two-digit, zero-padded prefix. Scripts in a directory are
  conventionally run in numeric order, so pick the next unused number by listing the
  existing `NN-*.sh` files there.
- `<tool-name>` — **lowercase kebab-case**: ASCII `[a-z0-9-]` only, words joined by
  single hyphens, no spaces, no underscores, no uppercase, no leading/trailing or
  doubled hyphens, and no version suffix. Pick the tool's canonical short name.
- **Normalization examples** (input → `<tool-name>`):
  - `Claude Code` → `claude-code`
  - `WSL interop fix` → `wsl-interop-fix`
  - `oh-my-zsh` → `omz` (a chosen short name)
  - `Node.js` → name the script after the actual installer, not the runtime, when a
    tool merely needs a runtime.
- Keep the `.sh` extension on the end only; never embed `.sh` mid-name.

## File permissions

New scripts are created with mode **`644`** (`rw-r--r--`) — non-executable. These
scripts are run with `bash <script>` (typically a `for script ... bash "$script"`
loop), not invoked directly, so the executable bit is unnecessary; `644` also
matches every existing script in the repo. After writing the file, ensure its mode
is `644` (`chmod 644 <file>`); never add `+x`.

## Header

Every script begins with:

```bash
#!/bin/bash
set -euo pipefail
```

`set -euo pipefail` fails fast: exit on any command error (`-e`), on an unset
variable (`-u`), and on a failure anywhere in a pipeline (`-o pipefail`). Plain
`set -e` alone would let a typo'd or missing env var expand to empty and do partial
work against the wrong path.

## Preconditions (fail fast)

Assert the env vars a script depends on are set and non-empty **before any work that
uses them**, so a bad environment fails immediately with a clear message instead of
part-way through. "Work that uses them" includes an already-installed guard whose
detection method references the var (see the next section for the exact ordering
rule):

```bash
: "${TARGET_USER:?TARGET_USER is required}"
```

Under `set -u`:

- **Required** vars get the `:?` guard — it documents the dependency and gives a
  readable error.
- **Optional** vars must be referenced with a default, e.g. `"${SOME_FLAG:-}"`,
  otherwise `set -u` aborts the moment they're read when unset.

Assert whatever variables your script actually needs — there is no fixed list.

## Already-installed guard (idempotency)

Scripts may be re-run (re-provisioning, or by hand). Before doing any install work,
check whether the tool is already present and bail out early.

Place the guard **as early as possible**, which depends on its detection method:

- **Env-independent** (system `command -v`, apt `dpkg -s`) — put the guard
  **before** the env asserts. An already-installed tool then skips immediately
  without first demanding an environment it won't use.
- **Env-dependent** (a per-user path test referencing `$TARGET_USER`) — assert that
  var first, then run the guard, since the guard reads it.

The bail-out itself is the same in either case:

```bash
echo "<tool> already installed, skipping"
exit 0
```

Use `exit 0`, not a non-zero code, so a re-run is a clean no-op and avoids re-piping
installers or re-appending to dotfiles. (If the script is one of several run in a
`for script ... bash "$script"` loop, a non-zero exit would also abort the rest.)

Pick the detection method that matches how the tool was installed. The first two are
env-independent (place them before the asserts); the third reads `$TARGET_USER`
(place it after that var's assert):

```bash
# System tool on PATH (binary in /usr/local/bin, /usr/bin, ...) — env-independent, goes first.
if command -v <tool> >/dev/null 2>&1; then
  echo "<tool> already installed, skipping"
  exit 0
fi
```

```bash
# apt package — env-independent, goes first.
if dpkg -s <pkg> >/dev/null 2>&1; then
  echo "<pkg> already installed, skipping"
  exit 0
fi
```

```bash
# Per-user install — when running as root, root's PATH can't see the user's tool
# dirs, so command -v gives false negatives. Test a concrete path under the user's
# home instead. This reads $TARGET_USER, so it must come *after* the
# : "${TARGET_USER:?}" assert.
if [[ -x "/home/$TARGET_USER/.local/bin/<tool>" ]]; then
  echo "<tool> already installed for $TARGET_USER, skipping"
  exit 0
fi
```

For per-user installs a path or directory test (`-x <binary>`, `-d <install-dir>`)
is more robust than `sudo -u "$TARGET_USER" command -v <tool>`, since it doesn't
depend on the user's login PATH being set up.

### Multiple tools in one script (the exception)

One tool per script is the strong default. In the odd case a script installs more
than one tool, **each tool gets its own guard** — and that guard must skip only
that tool, never `exit 0`. An early `exit 0` would abort the rest of the script,
so any later tool would silently never install once the first one is present (the
same reasoning as the `for script ... bash "$script"` loop above, but within a
single file).

Use an `if/else` per tool instead: guard hit → echo and skip just this tool; guard
miss → install it; then fall through to the next tool's block.

```bash
# Tool A — skip only this block when already present, then continue to Tool B.
if command -v <tool-a> >/dev/null 2>&1; then
  echo "<tool-a> already installed, skipping"
else
  # ... install tool A ...
fi

# Tool B — independently guarded; runs regardless of tool A's outcome.
if [[ -x "/home/$TARGET_USER/.local/bin/<tool-b>" ]]; then
  echo "<tool-b> already installed for $TARGET_USER, skipping"
else
  # ... install tool B ...
fi
```

Every other convention still applies to each tool independently: self-contained
install (no transient runtime), correct execution context, and a detection method
matching how that tool was installed.

## Execution context

A root-run install script does two kinds of work:

- System-level work runs directly: `apt-get`, writing to `/etc`, `systemctl
  enable/start`.
- User-level work must run as the target user and live under their home:

```bash
sudo -u "$TARGET_USER" <command>
# user home is /home/$TARGET_USER
```

If the whole script is intended to run as a normal user, skip the `sudo -u` wrapper
and just operate under `$HOME`.

## Download pattern

Fetch to `/tmp`, run, then clean up:

```bash
curl -fsSL <url> -o /tmp/<name>
# ... use it ...
rm -f /tmp/<name>
```

`curl` flags: `-fsSL` (fail on error, silent, show errors, follow redirects).

## apt pattern

```bash
apt-get update -qq
apt-get install -y -qq <packages>
```

For a third-party apt repo, add the keyring and source list, then update. Create
`/etc/apt/keyrings` first — it is not guaranteed to exist:

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL <repo>/gpg -o /etc/apt/keyrings/<name>.asc
chmod a+r /etc/apt/keyrings/<name>.asc
echo "deb [signed-by=/etc/apt/keyrings/<name>.asc] <repo> <suite> <component>" \
  > /etc/apt/sources.list.d/<name>.list
apt-get update -qq
apt-get install -y -qq <packages>
```

## Self-contained installs (no transient dependencies)

A script installs **exactly one tool** by default — prefer that. The *binding*
constraint is that an install must **not** pull in a shared language runtime (node,
python, java, ruby, …) or any other broad dependency as a side effect of installing
the tool. Doing so pollutes the system with a transient dependency and creates
hidden coupling between scripts.

In the odd case a script bundles more than one tool (see "Multiple tools in one
script" above), this rule applies **per tool**: each install must still be
self-contained — no transient runtime — and independently guarded.

Reject the anti-pattern of pulling a runtime in just to install a tool:

```bash
# WRONG: drags a system-wide Node runtime in as a transient dependency
apt-get install -y nodejs
npm install -g some-tool
```

Prefer an install method that is self-contained, in this order:

1. A native installer that **bundles its own runtime** (e.g. a vendor `install.sh`
   that ships a standalone binary instead of requiring a system-wide Node).
2. A standalone / statically-linked binary download (the `/tmp` download pattern
   above).
3. A plain apt package that has no runtime dependency of this kind.

If the tool genuinely needs a runtime, that runtime is a **separate concern**,
provided by its own dedicated install script, not by this one. The tool script
assumes the runtime is already available (or uses a bundled/native install) and
never installs the runtime itself.

---

## Example: per-user installer (minimal)

A curl installer run as the target user. The guard is env-dependent (it reads
`$TARGET_USER`), so the assert comes first, then the guard:

```bash
#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.tool/bin/tool" ]]; then
  echo "tool already installed for $TARGET_USER, skipping"
  exit 0
fi

curl -fsSL https://example.sh/install.sh -o /tmp/tool-install.sh
sudo -u "$TARGET_USER" bash /tmp/tool-install.sh
rm -f /tmp/tool-install.sh
```

## Example: system-wide installer (apt repo)

Its guard is env-independent (`command -v docker`), so it goes first — there are no
env asserts to precede:

```bash
#!/bin/bash
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  echo "docker already installed, skipping"
  exit 0
fi

CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
# ... daemon config, systemctl enable/start ...
```

Notes worth reusing:

- Derive the Ubuntu codename by sourcing `/etc/os-release`
  (`$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")`) rather than
  hardcoding it or relying on `lsb_release -cs` — `lsb_release` is not installed on newer
  minimal Ubuntu images (e.g. 26.04), but `/etc/os-release` is always present.
- Derive the architecture with `dpkg --print-architecture` rather than hardcoding
  it (e.g. `amd64`), so the source line is correct on non-x86 hosts too.
- Create `/etc/apt/keyrings` with `install -m 0755 -d` before writing a keyring
  into it — the directory is not guaranteed to exist.
- When apt would auto-start a service that can't run yet, temporarily drop a
  `policy-rc.d` that exits `101` to suppress the start, then remove it. Reuse that
  trick only if a package tries to start a daemon during install.
- Write daemon config with a heredoc to a file under `/etc`, then `systemctl enable`
  and `systemctl start`.

## Example: multiple tools in one script (the exception)

Prefer one tool per script — reach for this shape only when several closely related
assets genuinely belong together. Each block is guarded independently and skips only
itself (no `exit 0`), so one item already being present never blocks the others. The
required var is asserted once, up front:

```bash
#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

# Shared functions (system-wide)
if ls /usr/local/share/zsh/site-functions/*.zsh >/dev/null 2>&1; then
  echo "shared zsh functions already installed, skipping"
else
  mkdir -p /usr/local/share/zsh/site-functions
  cp /opt/example/zsh/*.zsh /usr/local/share/zsh/site-functions/
fi

# direnv libs (per-user)
if ls "/home/$TARGET_USER/.config/direnv/lib/"*.sh >/dev/null 2>&1; then
  echo "direnv libs already installed for $TARGET_USER, skipping"
else
  sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/direnv/lib"
  install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 \
    /opt/example/direnv/lib/*.sh "/home/$TARGET_USER/.config/direnv/lib/"
fi

# Claude skills (per-user)
if [[ -n "$(ls -A "/home/$TARGET_USER/.claude/skills" 2>/dev/null)" ]]; then
  echo "claude skills already installed for $TARGET_USER, skipping"
else
  sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude/skills"
  sudo -u "$TARGET_USER" cp -r /opt/example/claude/skills/. \
    "/home/$TARGET_USER/.claude/skills/"
fi
```

Note how each block picks the detection method matching its install (a glob for the
copied `*.zsh` / `*.sh`, a non-empty-dir test for the recursively copied skills),
and how per-user work runs via `sudo -u "$TARGET_USER"` under that user's home while
system-wide work runs directly — every single-tool convention, applied per tool.
