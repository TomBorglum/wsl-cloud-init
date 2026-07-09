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

## Prerequisites

The baseline environment needs only two things on the Windows side — the Ubuntu environment is built for you:

- **An up-to-date WSL 2** — run `wsl --update` to make sure you're current.
- **Git for Windows** — the provisioning script itself runs local `git`.

The opt-in features need a little extra Windows-side setup first — see [Opt-in features](#opt-in-features).

## Getting Started

Both steps run on **Windows**. This is the whole baseline path — no accounts or secrets required.

### 1. Clone this repository

You run the provisioning script from it.

```powershell
git clone https://github.com/TomBorglum/wsl-cloud-init.git
cd wsl-cloud-init
```

Provisioning uses whatever commit your checkout is on (cloud-init clones the repo and
checks out that exact commit) — stay on `main` for the latest changes. The commit just
has to exist on origin.

To provision a reproducible, released version instead, check that version out into its own
directory first with `checkout-ref.ps1`, then provision from there. This keeps each version
self-contained (the script, template, and in-distro setup all match) and leaves this
checkout untouched:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\scripts\checkout-ref.ps1 -Ref v1.0.0
```

It clones the ref into `%TEMP%\wsl-cloud-init-v1.0.0` (pass `-Destination <dir>` to choose
your own path), then prints a copy-paste-ready provision command with an **absolute** path —
so you can run it straight away without changing directory:

```powershell
# printed by checkout-ref.ps1 - copy, paste, then press Enter (append optional flags first if wanted):
powershell -ExecutionPolicy Bypass -File "C:\Users\you\AppData\Local\Temp\wsl-cloud-init-v1.0.0\windows\provision.ps1" `
  -DistroTemplatePath ubuntu `
  -DistroInstallName Ubuntu-26.04 `
  # optional: -InstanceName <value>  -InstallClaudeCode  -InstallGitConfig  -InstallVsCodeInterop
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

- `-DistroInstallName <name>` — only **pinned Ubuntu LTS versions** are supported (`Ubuntu-26.04`, `Ubuntu-24.04`, `Ubuntu-22.04`).
- `-InstallClaudeCode` — install Claude Code. See [Opt-in features](#opt-in-features).
- `-InstallGitConfig` — configure git identity, the credential helper, and `gh` auth. See [Opt-in features](#opt-in-features).
- `-InstallVsCodeInterop` — install the `code` Windows interop wrapper. See [Opt-in features](#opt-in-features).
- `-Force` — replace an existing instance of the same name (destroys it first).

The script renders the cloud-init config, installs Ubuntu, waits for cloud-init to finish, then launches you into the new instance — signed in as a Linux user derived from your Windows username, with passwordless sudo and `zsh` as the shell.

This bare command gives you the full baseline environment described in [What you get](#what-you-get).

## Opt-in features

Three flags add tooling on top of the baseline: `-InstallGitConfig`, `-InstallClaudeCode`, and `-InstallVsCodeInterop`. Each needs a little Windows-side setup first. You can enable them **when provisioning** (add the flag to the Getting Started command) or **add them later** to a running instance — the same setup applies either way.

### Set up Git identity

Only needed for `-InstallGitConfig` — provisioning copies these into the new instance.

```powershell
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

### Sign in to GitHub

Only needed for `-InstallGitConfig`. Both Git **and** `gh` reuse your existing Windows GitHub sign-in — the `git:https://github.com` credential that **Git Credential Manager** stores in Windows Credential Manager. There is **no separate token to create**: a single `git clone`/`git push` against a private repo on Windows (or `git-credential-manager github login`) signs you in and creates it. See [Configuration](#credentials).

`gh` is **not** authenticated at provisioning time — a wrapper on `PATH` reads that credential and authenticates `gh` the first time you invoke it, so rotating the token on GitHub is picked up automatically on the next `gh` call.

### Create and store secrets

Only needed for `-InstallClaudeCode`: a **[Context7](https://context7.com) API key**, stored as a **generic credential** with username `wsl-cloud-init` — see [Configuration](#credentials) for how it's used.

`-InstallVsCodeInterop` needs no secret — only **VS Code** with the `code` command on your `PATH`.

#### Option A — cmdkey (PowerShell)

```powershell
cmdkey /generic:wsl-cloud-init:CONTEXT7_API_KEY /user:wsl-cloud-init /pass:<context7-key> # only for `-InstallClaudeCode`
```

#### Option B — Credential Manager GUI

Control Panel → **Credential Manager** → **Windows Credentials** → **Add a generic credential**:

| Internet or network address | User name | Password |
| --- | --- | --- |
| `wsl-cloud-init:CONTEXT7_API_KEY` | `wsl-cloud-init` | your Context7 key (only for `-InstallClaudeCode`) |

### Enable when provisioning

Once the setup above is in place, add the flags to the Getting Started command:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\scripts\provision.ps1 `
  -DistroTemplatePath ubuntu `
  -DistroInstallName Ubuntu-26.04 `
  -InstanceName dev `
  -InstallGitConfig `
  -InstallClaudeCode `
  -InstallVsCodeInterop
```

### Enable later in a running instance

Provisioned without one of the opt-in flags and want it now? You don't need to re-provision. Re-run the same provisioning loop **inside the WSL instance**, setting only the `INSTALL_*` flags for what you want to add:

```bash
# Git identity, gh auth, and the Git shell helpers
sudo INSTALL_GIT_CONFIG=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh

# Claude Code
sudo INSTALL_CLAUDE_CODE=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh

# the `code` VS Code interop wrapper
sudo INSTALL_VS_CODE_INTEROP=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh
```

Combine flags to add several at once:

```bash
sudo INSTALL_GIT_CONFIG=true INSTALL_CLAUDE_CODE=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh
```

Each flag corresponds to the provisioning parameter of the same name:

| Provisioning parameter | On-demand flag |
| --- | --- |
| `-InstallClaudeCode` | `INSTALL_CLAUDE_CODE=true` |
| `-InstallGitConfig` | `INSTALL_GIT_CONFIG=true` |
| `-InstallVsCodeInterop` | `INSTALL_VS_CODE_INTEROP=true` |

The same prerequisites apply as at provisioning time: `-InstallGitConfig` needs your Git identity set and a GitHub sign-in in Windows Credential Manager (`git:https://github.com`); `-InstallClaudeCode` needs its Context7 key stored there. `install.sh` fetches what it needs from Windows at runtime, so set them up first if you didn't before.

## What you get

Every provisioned instance comes ready with:

### Shell
Zsh is the default shell, set up with **[Oh My Zsh](https://ohmyz.sh)** — autosuggestions plus the git, docker, z, sudo, and pj plugins — and **[direnv](https://direnv.net)** for per-directory environment loading.

### Language runtimes
**[fnm](https://github.com/Schniz/fnm)** (Node), **[pixi](https://pixi.sh)** (Python), and **[SDKMAN](https://sdkman.io)** (JVM) are installed and wired into direnv, so the right versions activate automatically as you enter each project (see [Usage](#direnv)).

### Docker
**[Docker](https://docs.docker.com/engine/)** Engine, the CLI, and the Compose plugin — ready to run without extra setup

**[lazydocker](https://github.com/jesseduffield/lazydocker)**, a terminal UI for managing containers, images, and volumes.

### Claude Code
Opt-in via `-InstallClaudeCode`: the **Claude Code** CLI, pre-wired to the **[Context7](https://context7.com)** MCP for up-to-date library docs, plus a bundled install-script skill.

### WSL interop
These commands reach from the Linux shell back into Windows:

- **`code`** — opens files and folders in your Windows VS Code. Opt-in via `-InstallVsCodeInterop`.
- **`open`** — launches a file or URL with its default Windows app.

Opt-in via `-InstallGitConfig`: your git identity, plus both Git and `gh` authenticating through Windows **[Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager)** (reusing your existing Windows sign-in). `gh` authenticates itself from that credential on first use — nothing is stored at provisioning time, and a rotated token is picked up automatically on the next `gh` call.

### Shell helpers
`pj` jumps between checkouts under `~/projects` — see [Usage](#usage). Opt-in via `-InstallGitConfig`: `clone-repo`, `create-repo`, `create-branch`, `rebase-branch`, and `prune-branches` streamline everyday Git work.

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

## Usage

The following day-to-day commands and per-project setup are included in the provisioned instance.

### direnv
fnm, pixi, and SDKMAN aren't on your global `PATH` — each project activates the versions it needs through direnv (already hooked into your shell). Add an `.envrc` to the project root with the directives you need:

```bash
# .envrc
use fnm node 22.14.0     # Node via fnm
use pixi                 # Python environment from pixi.toml (created if missing)
use sdk java 21.0.2-tem  # JVM SDK via SDKMAN
```

then approve it with `direnv allow`. direnv activates these on entry and removes them on exit, and installs the requested versions automatically on first use. Versions must be fully qualified — an exact release such as `22.14.0` or `21.0.2-tem`, not a partial like `22` or `lts`.

### clone-repo
Clone one of your GitHub repos into `~/projects/<name>` and drop you inside it. Tab-completion lists your repos; re-running just `cd`s into an existing checkout.

```bash
clone-repo my-project                 # clones <you>/my-project
clone-repo --owner some-owner service # clones some-owner/service
```

Cloning a private repo uses the GitHub token's **Contents (read)** permission.

### create-repo
Create a new **private** GitHub repo, clone it to `~/projects/<name>`, seed a README and initial commit, and `cd` in.

```bash
create-repo my-new-project             # creates <you>/my-new-project
create-repo --owner some-owner service # creates some-owner/service
```

Creating and pushing use the token's **Administration (create)** and **Contents (write)** permissions.

### create-branch
Create a branch off the repo's default branch and check it out with tracking, so a plain `git push` just works. If the branch already exists on origin it's just checked out; it refuses a local-only branch that isn't on origin yet.

```bash
create-branch my-feature   # branch off the default branch, tracking origin/my-feature
```

### pj
Jump straight into a checked-out project under `~/projects` without typing the full path — supports Tab-completion.

```bash
pj my-project   # cd into ~/projects/my-project
```

### rebase-branch
Rebase the current branch onto the remote's default branch (e.g. `main`).

```bash
rebase-branch
```

It refuses on a dirty working tree or detached HEAD, and stops on rebase conflicts so you can resolve them.

### prune-branches
Tidy up local branches whose remote branch is gone — merged and auto-deleted, or just deleted. Those are the branches that pile up locally once their life at the remote has ended.

```bash
prune-branches        # ask before deleting each gone branch
prune-branches -y     # delete them all without prompting
```

It asks before each deletion (default keeps; `y` deletes, `a` deletes all remaining, `q` stops) — pass `-y`/`--yes` to skip the prompts. It keeps branches that were never pushed (no upstream — purely-local work is always safe) and branches still tracking a live upstream (work in progress), and never touches the branch you're on. Each deletion prints the tip SHA (`Deleted my-feature (was 1a2b3c4)`) so it's recoverable with `git branch my-feature 1a2b3c4` until git eventually garbage-collects it. Stale `origin/*` refs are pruned automatically by git's `fetch.prune` (set as part of the opt-in git config).

### open
Open a file or URL with its default Windows application.

```bash
open report.pdf
open https://example.com
```

`open` is also your `$BROWSER`, so web links from command-line tools (e.g. `gh repo view --web`) open in your Windows browser.

### code
Open a file or folder in your Windows VS Code (via the WSL remote).

```bash
code .            # open the current folder
code src/app.ts   # open a file
```

## Configuration

What you can set when provisioning, and how the instance is derived.

### Provisioning parameters

`windows/scripts/provision.ps1` takes:

- `-DistroTemplatePath` (required) — template directory under `wsl/distros/` to render (e.g. `ubuntu`).
- `-DistroInstallName` (required) — WSL distro passed to `wsl --install`. Only pinned LTS versions are supported: `Ubuntu-26.04`, `Ubuntu-24.04`, or `Ubuntu-22.04`.
- `-InstanceName` (optional) — name for the new WSL instance. Defaults to `-DistroInstallName`.
- `-InstallClaudeCode` (optional) — install Claude Code.
- `-InstallGitConfig` (optional) — configure git identity, the credential helper, `gh` auth, and the Git shell helpers.
- `-InstallVsCodeInterop` (optional) — install the `code` Windows interop wrapper.
- `-Force` (optional) — unregister an existing instance of the same name first (this destroys it).

`provision.ps1` always provisions the commit its own checkout is on (which must exist on origin).
To provision a specific released version, use `checkout-ref.ps1` to lay that version down first.
Whichever ref it resolves is recorded inside the instance — see
[Checking the provisioned version](#checking-the-provisioned-version).

### Provisioning a released version

`windows/scripts/checkout-ref.ps1` clones a chosen ref into its own directory, detached, so
that version provisions itself — its `provision.ps1`, cloud-init template, and in-distro setup
all come from the same commit, and your working tree is left untouched. It takes:

- `-Ref` (required) — tag, branch, or commit to check out (e.g. `v1.0.0`). Must exist on origin.
- `-Destination` (optional) — directory to clone into. Defaults to `%TEMP%\wsl-cloud-init-<ref>`,
  shown with a confirmation prompt before cloning; pass it explicitly to skip the prompt. If the
  directory already exists and is non-empty, it prompts to delete and re-clone (defaults to no).

It then prints a copy-paste-runnable `provision.ps1` command with an **absolute** path (no `cd`
needed), built from that version's own parameter declaration — so it stays correct even for
older releases whose entrypoint lives at `windows\provision.ps1`.

### Checking the provisioned version

Every instance records the version it was built from in `/etc/wsl-cloud-init-release`,
written in the style of `/etc/os-release` — `KEY="value"` pairs you can read or source.

```bash
cat /etc/wsl-cloud-init-release
```

```sh
NAME="wsl-cloud-init"
ID=wsl-cloud-init
REF="v1.0.0"
COMMIT="9a6addd0c1f2e3b4a5968778695a4f3c2d1e0b9a"
COMMIT_SHORT="9a6addd0"
INSTANCE_NAME="Ubuntu-26.04"
PRETTY_NAME="wsl-cloud-init v1.0.0 (9a6addd0)"
SOURCE_URL="https://github.com/TomBorglum/wsl-cloud-init"
```

Source it to read a single field:

```bash
. /etc/wsl-cloud-init-release && echo "$REF @ $COMMIT_SHORT"
```

`REF` is resolved by `provision.ps1` from the checkout it runs out of, preferring the most
specific name available:

| Provisioned from | `REF` |
| --- | --- |
| a tagged commit (e.g. via `checkout-ref.ps1 -Ref v1.0.0`) | the tag — `v1.0.0` |
| a branch tip | the branch name — `main` |
| a detached, untagged commit | the short SHA — `9a6addd0` |

`REF` is a **label captured at provision time, not a live pointer**: an instance built from
`main` keeps `REF="main"` even after `main` moves on. `COMMIT` is the authoritative
identifier — it is the commit `/opt/wsl-cloud-init` is checked out at.

### Credentials

Windows Credential Manager provides:

| Credential | Used for |
| --- | --- |
| `git:https://github.com` | Your Windows GitHub sign-in (stored by Git Credential Manager). Both Git and [`gh`](https://cli.github.com) reuse it — **only required with `-InstallGitConfig`**. Not created by us; sign in to GitHub on Windows so it exists. |
| `wsl-cloud-init:CONTEXT7_API_KEY` | Claude Code's Context7 MCP — **only required with `-InstallClaudeCode`** |

`gh` is not authenticated during provisioning. A wrapper on `PATH` (`/usr/local/bin/gh`) reads `git:https://github.com` and authenticates `gh` the first time it's invoked — so a rotated token is picked up automatically on the next call.

### Target user

The Linux user is derived from your Windows username (`$env:USERNAME`), lowercased and stripped to `[a-z0-9_-]`. The account is created with passwordless `sudo`, membership in the `docker` group, `zsh` as its shell, and is set as the WSL **default user**.

## Troubleshooting

**Provisioning failed** — inspect the logs inside the instance; if the cause was transient (e.g. a network blip), re-provision with `-Force`.

```bash
less /var/log/cloud-init-output.log   # install-script output
less /var/log/cloud-init.log          # cloud-init's own log
```

**WSL interop stops working** — `code`, `open`, and Git authentication fail, often with an "Exec format error". The instance will self-heal within ~10 seconds; wait and try again.

**The systemd user session fails to start** — starting an Ubuntu 26.04 instance while other instances are already running may show `wsl: Failed to start the systemd user session for '<user>'`. It's intermittent and the instance still works. To clear it, run `wsl --shutdown` and relaunch the instance. To check whether an instance is affected, run `systemctl is-active user@1000.service` — it prints `failed` when the session didn't start, or `active` when it's running normally.
