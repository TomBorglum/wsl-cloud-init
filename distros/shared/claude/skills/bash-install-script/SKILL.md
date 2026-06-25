---
name: bash-install-script
description: Scaffold a self-contained, idempotent bash script that installs a tool/CLI/language/package. Use whenever the user wants an install or setup script written for some tool — phrasings like "write a bash installer for X", "add an install script for X", "scaffold a setup script for X", or "create an NN-install-*.sh script". Reach for this whenever the deliverable is a shell script whose job is to install something.
---

# bash-install-script

Scaffold a new install script that installs one tool, following the conventions a
robust install script shares: a strict header, fail-fast preconditions, an
already-installed guard for idempotency, a clear root-vs-per-user execution context,
and a self-contained install method.

**One tool per script — always.** A bash install script installs exactly one tool;
multi-tool scripts are not used. If you need to install another tool, give it its own
`NN-install-<tool-name>.sh` script rather than bundling it here.

The full convention list with annotated examples lives in
`references/conventions.md` — read it before writing the script.

## Workflow

1. **Gather intent.** Confirm:
   - The tool name.
   - Its official install method: a curl-piped installer, an apt repository + key, a
     plain apt package, or a downloaded binary. Prefer the upstream-recommended
     method; when you need to confirm how a tool is installed, look it up via the
     Context7 MCP server (`resolve-library-id` → `query-docs`) rather than guessing.
   - That the method is **self-contained**: it installs only this tool, never a
     shared runtime (node/python/java) as a transient dependency. Prefer a native
     installer that bundles its runtime, or a standalone binary, over an `npm -g` /
     `pip` / `apt nodejs` style method. If the tool needs a runtime, that runtime is
     a separate concern (its own install script) — do not install it here. See
     `references/conventions.md`.
   - Whether it installs **system-wide** (as root) or **per-user** (under a user's
     home).

2. **Determine the output path and name.** The target **directory is not
   predefined — ask the user for it.** Within that directory, name the file
   `NN-install-<tool-name>.sh`:
   - `NN` — the next free two-digit, zero-padded prefix. List the existing
     `NN-*.sh` files in the chosen directory and pick the next unused number.
   - `<tool-name>` — a **lowercase, kebab-case** slug: ASCII `[a-z0-9-]`, words
     joined by single hyphens, no spaces, no underscores, no uppercase, no version
     suffix, and no `.sh` mid-name. Multi-word names are fine (e.g. `claude-code`).
   The exact naming/normalization rules are in the "Output location and naming"
   section of `references/conventions.md`.

3. **Choose the execution context.** Decide whether the script runs as root or as a
   regular user:
   - System work (apt, `/etc`, `systemctl`) runs directly and assumes root.
   - When a root-run script must install something that belongs to a specific user,
     run that work via `sudo -u "$TARGET_USER"` and write under
     `/home/$TARGET_USER` — where `$TARGET_USER` is a variable the script asserts.
     Installing user tools as root would leave root-owned files in the user's home.

4. **Add an already-installed guard.** Before any install work, check whether the
   tool is already present and, if so, `echo "<tool> already installed, skipping"`
   and `exit 0`. This keeps re-runs idempotent and avoids re-piping installers or
   re-appending to dotfiles. Place the guard **as early as possible** — before the
   required-env asserts when its detection method needs no required var, and only
   after the assert for any required var it references. Pick the detection method
   that matches the install context — system `command -v`, apt `dpkg -s`, or a
   per-user path/dir test under the user's home. The exact snippets are in
   `references/conventions.md`. The guard ends with `exit 0`.

5. **Write the script.** Start with `#!/bin/bash` and `set -euo pipefail`. The order
   of the already-installed guard and the env asserts depends on whether the guard
   needs a required var:
   - **Env-independent guard** (system `command -v` / apt `dpkg -s`): guard first,
     then any env asserts (`: "${TARGET_USER:?}"`), then the install body — an
     already-installed tool skips immediately without first demanding an environment
     it won't use.
   - **Env-dependent guard** (per-user path test using `$TARGET_USER`): assert the
     var it needs first, then the guard, then the install body.

   Apply the download/apt patterns and `/tmp` cleanup documented in
   `references/conventions.md`. Read that file now if you're not already sure of the
   exact patterns — it has annotated examples for both root and per-user installs.
   Apply its **"Self-contained installs (no transient dependencies)"** rule: never
   pull a shared runtime in as a side effect.

   After writing the file, set its mode to `644` (non-executable) — these scripts
   are run with `bash <script>`, not invoked directly, so the executable bit is
   unnecessary. See the "File permissions" section of `references/conventions.md`.

6. **Verify.** Run `bash -n` on the new script to catch syntax errors, and confirm
   its mode is `644`. Note to the user that full runtime verification requires the
   real target environment — these scripts assume their intended user/root context
   and a fresh system.

## Reference

- `references/conventions.md` — the full convention list with annotated root and
  per-user examples, and the self-contained / no-transient-dependency rule. Read it
  before writing the script.
