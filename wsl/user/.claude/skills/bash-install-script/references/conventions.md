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

## Exit-code contract

A script reports **what it did** through its exit code. Without this a script that
skipped is indistinguishable from one that installed something, and a runner can only
say "ok" for both:

| Code | Meaning | Shown by the runner as |
| --- | --- | --- |
| `0` | did the work | `-> ok (2.4s)` |
| `3` | already installed — the guard found its payload in place | `-> already installed (0.0s)` |
| `4` | not selected — the `INSTALL_*` flag for an opt-in feature is not set | `-> not selected (0.0s)` |
| anything else | failed; the run stops and names the script | — |

`3` and `4` keep clear of `1` (generic error), `2` (misuse), and the `126+` range the
shell reserves for "not executable" / "not found" / signals.

One consequence worth stating in the script's own output: running a numbered script by
hand can now exit non-zero without anything being wrong.

**This assumes a runner that reads those codes.** `wsl-cloud-init`'s
`wsl/distros/ubuntu/install.sh` does — it captures each status with
`rc=0; bash "$script" || rc=$?` and maps `3`/`4` rather than letting `set -e` make a
failure of them. A plain `for f in *.sh; do bash "$f"; done` under `set -e` does not:
there a non-zero guard aborts the rest of the run. When the target directory's runner
is of that second kind, use `exit 0` for both guards instead and note why in a comment.

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
exit 3  # already installed; see install.sh
```

The `echo` still matters even though the code carries the status: it is what the log
holds when the run is not on a terminal, and it names which payload was found.

Pick the detection method that matches how the tool was installed. The first two are
env-independent (place them before the asserts); the third reads `$TARGET_USER`
(place it after that var's assert):

```bash
# System tool on PATH (binary in /usr/local/bin, /usr/bin, ...) — env-independent, goes first.
if command -v <tool> >/dev/null 2>&1; then
  echo "<tool> already installed, skipping"
  exit 3  # already installed; see install.sh
fi
```

```bash
# apt package — env-independent, goes first.
if dpkg -s <pkg> >/dev/null 2>&1; then
  echo "<pkg> already installed, skipping"
  exit 3  # already installed; see install.sh
fi
```

```bash
# Per-user install — when running as root, root's PATH can't see the user's tool
# dirs, so command -v gives false negatives. Test a concrete path under the user's
# home instead. This reads $TARGET_USER, so it must come *after* the
# : "${TARGET_USER:?}" assert.
if [[ -x "/home/$TARGET_USER/.local/bin/<tool>" ]]; then
  echo "<tool> already installed for $TARGET_USER, skipping"
  exit 3  # already installed; see install.sh
fi
```

For per-user installs a path or directory test (`-x <binary>`, `-d <install-dir>`)
is more robust than `sudo -u "$TARGET_USER" command -v <tool>`, since it doesn't
depend on the user's login PATH being set up.

## Opt-in flag guard (not selected)

A tool that is only installed on request is gated on an `INSTALL_<FEATURE>` flag. That
guard goes at the **very top** — ahead of the env asserts and the already-installed
guard — because a script that was not selected has no business demanding an
environment or probing the filesystem at all:

```bash
if [[ "${INSTALL_<FEATURE>:-}" != "true" ]]; then
  echo "INSTALL_<FEATURE> not set, skipping <tool> install"
  exit 4  # not selected; see install.sh
fi
```

Note the `:-` default: the flag is an **optional** var, so under `set -u` it must be
referenced with one or reading it aborts the script when it is unset. Test for the
literal `"true"` rather than for non-emptiness, so a stray `false` or `0` does not read
as opting in.

A script can carry both guards. The flag guard decides *whether* to run; the
already-installed guard decides whether there is anything left to do:

```bash
if [[ "${INSTALL_CLAUDE_CODE:-}" != "true" ]]; then
  echo "INSTALL_CLAUDE_CODE not set, skipping claude-code install"
  exit 4  # not selected; see install.sh
fi

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.local/bin/claude" ]]; then
  echo "claude-code already installed for $TARGET_USER, skipping"
  exit 3  # already installed; see install.sh
fi
```

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

## Non-interactive execution

An install script must never wait for input. It runs unattended (cloud-init, CI), and on a
terminal a runner that captures a step's output hides the prompt, so the run looks hung
rather than stuck on a question — worse if the waiting program switched the terminal to raw
mode, which takes `Ctrl-C` with it and leaves the terminal apparently locked up.

Your own script is easy to keep quiet; the risk is the **third-party installers and CLIs** it
invokes, which decide whether they are interactive by looking at stdin. Give each one an
unattended flag where it has one, and detach stdin regardless:

```bash
# a flag where the installer offers one (this one would otherwise exec a shell at the end)
sudo -u "$TARGET_USER" sh -c "$(curl -fsSL --proto '=https' --tlsv1.2 <url>)" "" --unattended

# and/or stdin on /dev/null, which is what makes a program report "not a tty" and behave
sudo -u "$TARGET_USER" bash /tmp/<installer>.sh </dev/null
sudo -u "$TARGET_USER" <tool> <subcommand> </dev/null
```

`</dev/null` is belt and braces: `wsl-cloud-init`'s `install.sh` already runs every step with
stdin detached, so this is what holds when the script is run on its own. Prefer it to a
timeout — a hung step and a slow download are indistinguishable from the outside, and a
download is allowed to take minutes.

## Download pattern

Fetch to `/tmp`, run, then clean up:

```bash
curl -fsSL --proto '=https' --tlsv1.2 <url> -o /tmp/<name>
# ... use it ...
rm -f /tmp/<name>
```

`curl` flags: `-fsSL` (fail on error, silent, show errors, follow redirects) plus
`--proto '=https' --tlsv1.2`. **Always include `--proto '=https'`** on any `curl`
that downloads: with `-L`, a redirect from the `https://` URL to a plaintext
`http://` one would otherwise be followed silently, downloading code over an
insecure channel. `--proto '=https'` restricts the transfer — including redirects —
to HTTPS, so such a downgrade fails loudly instead. `--tlsv1.2` floors the TLS
version. This applies to **every** download `curl` in the script, including the
keyring fetch in the apt pattern below. Static analyzers (e.g. SonarCloud) flag a
bare `curl ... https://...` as a vulnerability for exactly this reason.

## apt pattern

```bash
apt-get update -qq
apt-get install -y -qq <packages>
```

For a third-party apt repo, add the keyring and source list, then update. Create
`/etc/apt/keyrings` first — it is not guaranteed to exist:

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL --proto '=https' --tlsv1.2 <repo>/gpg -o /etc/apt/keyrings/<name>.asc
chmod a+r /etc/apt/keyrings/<name>.asc
echo "deb [signed-by=/etc/apt/keyrings/<name>.asc] <repo> <suite> <component>" \
  > /etc/apt/sources.list.d/<name>.list
apt-get update -qq
apt-get install -y -qq <packages>
```

## Self-contained installs (no transient dependencies)

A script installs **exactly one tool**. The *binding* constraint is that an install
must **not** pull in a shared language runtime (node, python, java, ruby, …) or any
other broad dependency as a side effect of installing the tool. Doing so pollutes the
system with a transient dependency and creates hidden coupling between scripts.

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
  exit 3  # already installed; see install.sh
fi

curl -fsSL --proto '=https' --tlsv1.2 https://example.sh/install.sh -o /tmp/tool-install.sh
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
  exit 3  # already installed; see install.sh
fi

CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
install -m 0755 -d /etc/apt/keyrings
curl -fsSL --proto '=https' --tlsv1.2 https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
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
- `systemctl start` returning only means systemd considers the unit started. When later
  steps (or the very next script in the run) depend on that daemon actually working, poll
  `systemctl show <unit> -p ActiveState -p SubState` until it reports `active`/`running`,
  bounded by a poll count rather than a wall clock, and fail with the last observed state
  and a `journalctl` tail if it never gets there. For a daemon with a client socket, follow
  that with a cheap client call (`docker info`) so the script returns only once the socket
  is answering.
