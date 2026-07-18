# wsl-cloud-init

An opinionated, cloud-init–driven way to provision a fully configured WSL Ubuntu developer environment from a single command — so you're productive immediately.

## Overview

Setting up a productive WSL environment by hand is slow and easy to get subtly wrong
— installing tools, configuring the shell, wiring up Git credentials, and bridging
Windows apps, repeated for every new instance.

wsl-cloud-init replaces that with one repeatable step. It uses cloud-init to
declaratively build a fresh WSL Ubuntu instance with a curated, opinionated set of
tools and configuration, so every instance you create comes out the same — fully
configured and ready to work in.

Provisioning runs from Windows: a PowerShell script renders a cloud-init template,
installs the distro, and waits for setup to finish. On first boot cloud-init runs a
series of scripts that build the environment and wire Windows tools — VS Code, Git
Credential Manager — into the Linux shell.

## What you get

Every provisioned instance comes ready with the baseline below. Four additions are
opt-in, each behind a provisioning flag: `-InstallClaudeCode`, `-InstallGitConfig`,
`-InstallVsCodeInterop`, and `-InstallZedInterop`.

### Shell

Zsh is the default shell, set up with **[Oh My Zsh](https://ohmyz.sh)** — autosuggestions
plus the git, docker, z, sudo, and pj plugins — and **[direnv](https://direnv.net)** for
per-directory environment loading.

### Language runtimes

**[fnm](https://github.com/Schniz/fnm)** (Node), **[pixi](https://pixi.sh)** (Python), and
**[SDKMAN](https://sdkman.io)** (JVM) are installed and wired into direnv, so the right
versions activate automatically as you enter each project.

### Docker

**[Docker](https://docs.docker.com/engine/)** Engine, the CLI, and the Compose plugin —
ready to run without extra setup — plus **[lazydocker](https://github.com/jesseduffield/lazydocker)**,
a terminal UI for managing containers, images, and volumes.

### Git

Opt-in via `-InstallGitConfig`: your Git identity, the credential helper, `gh` auth, and the
Git shell helpers. Both `git` and `gh` authenticate through Windows
**[Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager)**, reusing
the GitHub sign-in you already have on Windows — one credential serves both, so there is no
second token to create and no `gh auth login` to run.

### Claude Code

Opt-in via `-InstallClaudeCode`: the **Claude Code** CLI, pre-wired to the
**[Context7](https://context7.com)** MCP for up-to-date library docs, plus a bundled
install-script skill.

### WSL interop

- **`open`** — launches a file or URL with its default Windows app. Always installed.
- **`code`** — opens files and folders in your Windows VS Code. Opt-in via `-InstallVsCodeInterop`.
- **`zed`** — opens files and folders in your Windows Zed. Opt-in via `-InstallZedInterop`, which
  also seeds a default `settings.json`/`keymap.json` into your Windows Zed config.

`code` and `zed` locate the Windows editor via a one-time interop lookup and cache the resolved
path under `~/.cache/wsl-cloud-init/`, so only the first launch pays that cost; the cache
re-resolves automatically if the editor is later moved or reinstalled.

### Shell helpers

`pj` jumps between checkouts under `~/projects`. Always installed.

Opt-in via `-InstallGitConfig`: `clone-repo`, `create-repo`, `create-branch`, `rebase-branch`,
and `prune-branches` streamline everyday Git work.

### Base packages

Installed from the cloud-init package list:

- build-essential
- curl
- direnv
- gh
- git
- jq
- unzip
- zip
- zsh

## Prerequisites

The baseline environment needs only two things on the Windows side — the Ubuntu environment
is built for you:

- **An up-to-date WSL 2** — run `wsl --update` to make sure you're current.
- **Git for Windows** — `provision.ps1` runs local `git` to resolve the commit your checkout
  is on, verify that commit exists on origin, and record it in the instance.

Each opt-in flag needs some additional Windows-side setup, described under
[Opt-in features](#opt-in-features).

## Getting started

Both steps run on **Windows**. This is the whole baseline path — no accounts or secrets required.

### 1. Clone this repository

You run the provisioning script from it.

```powershell
git clone https://github.com/TomBorglum/wsl-cloud-init.git
cd wsl-cloud-init
```

### 2. Provision an instance

In **PowerShell**:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\scripts\provision.ps1 `
  -DistroTemplatePath ubuntu `
  -DistroInstallName Ubuntu-26.04 `
  -InstanceName dev
```

`-ExecutionPolicy Bypass` runs the script without changing your machine's PowerShell policy.
Every parameter is described under [Provisioning parameters](#provisioning-parameters).

The script renders the cloud-init config, installs Ubuntu, waits for cloud-init to finish, then
launches you into the new instance — signed in as a Linux user derived from your Windows
username, with passwordless sudo and `zsh` as the shell.

To provision a specific released version rather than the latest, use `checkout-ref.ps1` — see
[Released-version parameters](#released-version-parameters).

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\scripts\checkout-ref.ps1 -Ref v1.0.0
```

## Opt-in features

Four flags add tooling on top of the baseline: `-InstallClaudeCode`, `-InstallGitConfig`,
`-InstallVsCodeInterop`, and `-InstallZedInterop`. Each needs some Windows-side setup first. You
can enable them when provisioning, or add them later to a running instance.

### Windows setup

Do the setup for each flag you intend to use.

#### `-InstallClaudeCode` — a Context7 API key

Store a **[Context7](https://context7.com) API key** as a **generic credential** in Windows
Credential Manager, with username `wsl-cloud-init`.

Using `cmdkey` in PowerShell:

```powershell
cmdkey /generic:wsl-cloud-init:CONTEXT7_API_KEY /user:wsl-cloud-init /pass:<context7-key>
```

Or via the GUI — Control Panel → **Credential Manager** → **Windows Credentials** →
**Add a generic credential**:

| Internet or network address | User name | Password |
| --- | --- | --- |
| `wsl-cloud-init:CONTEXT7_API_KEY` | `wsl-cloud-init` | your Context7 key |

##### Optional: the `use sonarqube_mcp` direnv directive (private repos)

`-InstallClaudeCode` also installs a [direnv](https://direnv.net) directive,
`use sonarqube_mcp`, that enables the [SonarQube Cloud MCP
server](https://github.com/SonarSource/sonarqube-mcp-server) for a project, so Claude can
read and fix Sonar issues — handy for **private** repos whose SonarCloud dashboards aren't
publicly reachable. The server runs via Docker (pulled once on first use), so nothing extra
is installed at provision time.

Add `use sonarqube_mcp` to a project's `.envrc` (like `use pixi` / `use sdk`) and run
`direnv allow`. On first activation the directive scaffolds a **secret-free** `.mcp.json`
that references `${SONARQUBE_TOKEN}` / `${SONARQUBE_ORG}` (not the values), and on every
activation direnv supplies those variables from your Windows Credential Manager. Because no
secret is stored in the project, both `.envrc` and `.mcp.json` are safe to commit and share
with your team — each teammate just keeps their own credentials (below), and the directive
is a no-op in CI.

Store two more generic credentials (a [SonarQube Cloud
token](https://docs.sonarsource.com/sonarqube-cloud/managing-your-account/managing-tokens/)
and your organization key):

```powershell
cmdkey /generic:wsl-cloud-init:SONARQUBE_TOKEN /user:wsl-cloud-init /pass:<sonar-token>
cmdkey /generic:wsl-cloud-init:SONARQUBE_ORG   /user:wsl-cloud-init /pass:<sonar-org-key>
```

| Internet or network address | User name | Password |
| --- | --- | --- |
| `wsl-cloud-init:SONARQUBE_TOKEN` | `wsl-cloud-init` | your SonarQube Cloud token |
| `wsl-cloud-init:SONARQUBE_ORG` | `wsl-cloud-init` | your SonarQube Cloud organization key |

Then, in the project you want it for, add `use sonarqube_mcp` to `.envrc` and run
`direnv allow`.

#### `-InstallGitConfig` — a Git identity and a GitHub sign-in

Set your Git identity on Windows; provisioning copies it into the new instance.

```powershell
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

Then make sure you are signed in to GitHub on Windows. Both `git` and `gh` reuse the
`git:https://github.com` credential that **Git Credential Manager** stores in Windows Credential
Manager. There is **no separate token to create**: a single `git clone` or `git push` against a
private repo on Windows — or `git-credential-manager github login` — signs you in and creates it.

#### `-InstallVsCodeInterop` — VS Code on your PATH

No secret is needed. Install **VS Code** on Windows and make sure the `code` command is on your
Windows `PATH`.

#### `-InstallZedInterop` — Zed on your PATH

No secret is needed. Install **[Zed](https://zed.dev)** on Windows and make sure the `zed` command
is on your Windows `PATH`.

This installs only the `zed` interop wrapper; it does **not** touch your Windows Zed config.

Seeding a default config is a separate, WSL-only opt-in via `INSTALL_ZED_CONFIG` (there is no
provision-time switch for it — see [Enabling on a running instance](#enabling-on-a-running-instance)).
When set alongside `INSTALL_ZED_INTEROP`, it writes a default `settings.json` and `keymap.json` into
your Windows Zed config directory (`%APPDATA%\Zed`). Any existing file is moved aside to `<name>.bak`
first, and the config is re-asserted on every opt-in — so if several WSL instances seed the config,
they converge on the same one (the last run wins). Because config requires interop, opting into the
config without interop does nothing.

### Enabling at provision time

Add the flags to the provisioning command:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\scripts\provision.ps1 `
  -DistroTemplatePath ubuntu `
  -DistroInstallName Ubuntu-26.04 `
  -InstanceName dev `
  -InstallClaudeCode `
  -InstallGitConfig `
  -InstallVsCodeInterop `
  -InstallZedInterop
```

### Enabling on a running instance

Provisioned without one of the flags and want it now? You don't need to re-provision. Re-run the
provisioning loop **inside the WSL instance**, setting only the `INSTALL_*` variable matching the
flag you want to add. The Windows-side setup for that flag must be in place first — `install.sh`
fetches what it needs from Windows at runtime.

```bash
# Claude Code
sudo INSTALL_CLAUDE_CODE=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh

# Git identity, gh auth, and the Git shell helpers
sudo INSTALL_GIT_CONFIG=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh

# the `code` VS Code interop wrapper
sudo INSTALL_VS_CODE_INTEROP=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh

# the `zed` Zed interop wrapper (only)
sudo INSTALL_ZED_INTEROP=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh

# also seed the Windows Zed config (settings.json / keymap.json). WSL-only; requires interop
sudo INSTALL_ZED_INTEROP=true INSTALL_ZED_CONFIG=true \
  bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh
```

## Usage

The following day-to-day commands and per-project setup are included in the provisioned instance.

### direnv

fnm, pixi, and SDKMAN aren't on your global `PATH` — each project activates the versions it needs
through direnv (already hooked into your shell). Add an `.envrc` to the project root with the
directives you need:

```bash
# .envrc
use fnm node 22.14.0     # Node via fnm
use pixi                 # Python environment from pixi.toml (created if missing)
use sdk java 21.0.2-tem  # JVM SDK via SDKMAN
```

then approve it with `direnv allow`. direnv activates these on entry and removes them on exit, and
installs the requested versions automatically on first use. Versions must be fully qualified — an
exact release such as `22.14.0` or `21.0.2-tem`, not a partial like `22` or `lts`.

### pj

Jump straight into a checked-out project under `~/projects` without typing the full path — supports
Tab-completion.

```bash
pj my-project   # cd into ~/projects/my-project
```

### clone-repo

*Requires `-InstallGitConfig`.* Clone one of your GitHub repos into `~/projects/<name>` and drop
you inside it. Tab-completion lists your repos; re-running just `cd`s into an existing checkout.

```bash
clone-repo my-project                 # clones <you>/my-project
clone-repo --owner some-owner service # clones some-owner/service
```

### create-repo

*Requires `-InstallGitConfig`.* Create a new **private** GitHub repo, clone it to
`~/projects/<name>`, seed a README and initial commit, and `cd` in.

```bash
create-repo my-new-project             # creates <you>/my-new-project
create-repo --owner some-owner service # creates some-owner/service
```

### create-branch

*Requires `-InstallGitConfig`.* Create a branch off the repo's default branch and check it out with
tracking, so a plain `git push` just works. If the branch already exists on origin it's just checked
out; it refuses a local-only branch that isn't on origin yet.

```bash
create-branch my-feature   # branch off the default branch, tracking origin/my-feature
```

### rebase-branch

*Requires `-InstallGitConfig`.* Rebase the current branch onto the remote's default branch
(e.g. `main`).

```bash
rebase-branch
```

It refuses on a dirty working tree or detached HEAD, and stops on rebase conflicts so you can
resolve them.

### prune-branches

*Requires `-InstallGitConfig`.* Tidy up local branches whose remote branch is gone — merged and
auto-deleted, or just deleted. Those are the branches that pile up locally once their life at the
remote has ended.

```bash
prune-branches        # ask before deleting each gone branch
prune-branches -y     # delete them all without prompting
```

It asks before each deletion (default keeps; `y` deletes, `a` deletes all remaining, `q` stops) —
pass `-y`/`--yes` to skip the prompts. It keeps branches that were never pushed (no upstream —
purely-local work is always safe) and branches still tracking a live upstream (work in progress),
and never touches the branch you're on. Each deletion prints the tip SHA so the branch is
recoverable with `git branch <name> <sha>` until git eventually garbage-collects it. Stale
`origin/*` refs are pruned automatically by git's `fetch.prune`, which `-InstallGitConfig` sets.

### open

Open a file or URL with its default Windows application.

```bash
open report.pdf
open https://example.com
```

`open` is also your `$BROWSER`, so web links from command-line tools (e.g. `gh repo view --web`)
open in your Windows browser.

### code

*Requires `-InstallVsCodeInterop`.* Open a file or folder in your Windows VS Code (via the WSL
remote).

```bash
code .            # open the current folder
code src/app.ts   # open a file
```

### zed

*Requires `-InstallZedInterop`.* Open a file or folder in your Windows Zed (via the WSL
remote).

```bash
zed .             # open the current folder
zed src/app.ts    # open a file
```

## Configuration

What you can set when provisioning, and how the instance is derived.

### Provisioning parameters

`windows/scripts/provision.ps1` takes:

- `-DistroTemplatePath` (required) — the cloud-init template to render. `ubuntu` is the only
  supported value.
- `-DistroInstallName` (required) — WSL distro passed to `wsl --install`. Only pinned Ubuntu LTS
  versions are supported: `Ubuntu-26.04`, `Ubuntu-24.04`, or `Ubuntu-22.04`.
- `-InstanceName` (optional) — name for the new WSL instance. Defaults to `-DistroInstallName`.
- `-InstallClaudeCode` (optional) — install Claude Code.
- `-InstallGitConfig` (optional) — configure the Git identity, the credential helper, `gh` auth,
  and the Git shell helpers.
- `-InstallVsCodeInterop` (optional) — install the `code` Windows interop wrapper.
- `-InstallZedInterop` (optional) — install the `zed` Windows interop wrapper.
- `-Force` (optional) — unregister an existing instance of the same name first. This destroys it.

`provision.ps1` provisions the commit its own checkout is on, and refuses to run against a dirty
working tree — commit or stash your changes first. That commit must also exist on origin, because
cloud-init reproduces the environment by cloning this repo from GitHub *inside* the instance and
checking that commit out; an unpushed commit cannot be fetched there.

### Released-version parameters

`windows/scripts/checkout-ref.ps1` clones a chosen ref into its own directory, detached, so that
version provisions itself — its `provision.ps1`, cloud-init template, and in-distro setup all come
from the same commit, and your working tree is left untouched. It takes:

- `-Ref` (required) — tag, branch, or commit to check out (e.g. `v1.0.0`). Must exist on origin.
- `-Destination` (optional) — directory to clone into. Defaults to `%TEMP%\wsl-cloud-init-<ref>`,
  shown with a confirmation prompt before cloning; pass it explicitly to skip the prompt. If the
  directory already exists and is non-empty, it prompts to delete and re-clone (defaults to no).

It then prints a `provision.ps1` command you can copy, paste, and run. The path is absolute, so no
`cd` is needed, and the parameters are read from that version's own declaration, so the command
stays correct even for older releases whose entrypoint sits at a different path.

### Credentials

Windows Credential Manager provides:

| Credential | Used for |
| --- | --- |
| `wsl-cloud-init:CONTEXT7_API_KEY` | Claude Code's Context7 MCP — **only required with `-InstallClaudeCode`** |
| `wsl-cloud-init:SONARQUBE_TOKEN` | Read by direnv for the `use sonarqube_mcp` directive (installed with `-InstallClaudeCode`) — **only required if you use that directive** |
| `wsl-cloud-init:SONARQUBE_ORG` | Read by direnv for the `use sonarqube_mcp` directive (installed with `-InstallClaudeCode`) — **only required if you use that directive** |
| `git:https://github.com` | Your Windows GitHub sign-in, stored by Git Credential Manager. Both `git` and [`gh`](https://cli.github.com) reuse it — **only required with `-InstallGitConfig`**. Not created by us; sign in to GitHub on Windows so it exists. |

`git` and `gh` authenticate from that single credential — no second token to create, and no
`gh auth login` to run. When `gh`'s session stops working it re-reads the credential and retries,
so a token rotated in Windows Credential Manager takes effect on the next `gh` call.

### Target user

The Linux user is derived from your Windows username (`$env:USERNAME`), lowercased and stripped to
`[a-z0-9_-]`. The account is created with passwordless `sudo`, membership in the `docker` group,
`zsh` as its shell, and is set as the WSL **default user**.

## Versioning

### The provisioned version

Every instance records the version it was built from in `/etc/wsl-cloud-init-release`:

```bash
cat /etc/wsl-cloud-init-release
```

Two fields identify the build. `COMMIT` is the authoritative identifier — the commit
`/opt/wsl-cloud-init` is checked out at. `REF` is the friendliest name `provision.ps1` could give
that commit, resolved from the checkout it ran out of:

| Provisioned from | `REF` |
| --- | --- |
| a tagged commit | the tag, e.g. `v1.0.0` |
| a branch tip | the branch name, e.g. `main` |
| a detached, untagged commit | the short SHA |

`REF` is a **label captured at provision time, not a live pointer**: an instance built from `main`
keeps `REF="main"` even after `main` moves on.

### In-place upgrades are not supported

`/etc/wsl-cloud-init-release` is written once, by cloud-init, and never updated. An instance is tied
to the commit it was provisioned from for its whole life.

Moving `/opt/wsl-cloud-init` to a newer commit and re-running `install.sh` does **not** upgrade the
instance. Each install script skips whatever it finds already installed, so only the handful that
rewrite their payload unconditionally would apply, leaving an instance that matches no version at
all. To prevent that, the run aborts before anything else executes if `/opt/wsl-cloud-init` is no
longer at the commit `/etc/wsl-cloud-init-release` records.

To move an instance to a new version, re-provision it with `provision.ps1 -Force`, which destroys
and recreates it. Adding an opt-in feature to an existing instance is unaffected: that re-run leaves
`/opt/wsl-cloud-init` where it is, so the check passes and the file is left untouched.

## Troubleshooting

**Provisioning failed** — inspect the logs inside the instance; if the cause was transient (e.g. a
network blip), re-provision with `-Force`.

```bash
less /var/log/cloud-init-output.log   # install-script output
less /var/log/cloud-init.log          # cloud-init's own log
```

**WSL interop stops working** — `code`, `open`, and Git authentication fail, often with an "Exec
format error". WSL's `binfmt_misc` interop handler is shared across the VM and another distro can
flush it. A systemd timer re-registers it every 10 seconds, so wait a moment and try again.

**The systemd user session fails to start** — starting an Ubuntu 26.04 instance while other
instances are already running may show `wsl: Failed to start the systemd user session for '<user>'`.
It's intermittent and the instance still works. To clear it, run `wsl --shutdown` and relaunch the
instance. To check whether an instance is affected, run `systemctl is-active user@1000.service` — it
prints `failed` when the session didn't start, or `active` when it's running normally.
