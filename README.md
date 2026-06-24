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

Provisioning runs from Windows: a PowerShell script reads your Git identity, pulls
your secrets from Windows Credential Manager, renders a cloud-init template, installs
the distro, and waits for setup to finish. On first boot cloud-init runs a series of
scripts that build the environment and wire Windows tools — VS Code, Git
Credential Manager — into the Linux shell.

## Prerequisites

Everything is on the Windows side — the Ubuntu environment is built for you.

- **An up-to-date WSL 2** — run `wsl --update` to make sure you're current.
- **Git for Windows** — includes [Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager), which the provisioned instance reuses for authentication.
- **VS Code** with the `code` command on your `PATH`.

Accounts, tokens, and Git identity are set up in [Getting Started](#getting-started).

## Getting Started

All steps run on **Windows**.

### 1. Clone this repository

You run the provisioning script from it.

```powershell
git clone https://github.com/TomBorglum/wsl-cloud-init.git
cd wsl-cloud-init
```

### 2. Set your Git identity

Provisioning copies these into the new instance.

```powershell
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

### 3. Create two tokens

- **GitHub token** — used by the installed [`gh`](https://cli.github.com) CLI. A **fine-grained token** needs these repository permissions:
  - **Administration** — read and write (create repositories)
  - **Contents** — read and write (clone and push)
  - **Metadata** — read (required)
- **Context7 API key** — from your [Context7](https://context7.com) account; used by Claude Code's Context7 MCP.

### 4. Store the tokens in Windows Credential Manager

Both are stored as **generic credentials** with username `wsl-cloud-init`. Use either option.

#### Option A — cmdkey (PowerShell)

```powershell
cmdkey /generic:wsl-cloud-init:GH_TOKEN         /user:wsl-cloud-init /pass:<github-token>
cmdkey /generic:wsl-cloud-init:CONTEXT7_API_KEY /user:wsl-cloud-init /pass:<context7-key>
```

#### Option B — Credential Manager GUI

Control Panel → **Credential Manager** → **Windows Credentials** → **Add a generic credential**, once per secret:

| Internet or network address | User name | Password |
| --- | --- | --- |
| `wsl-cloud-init:GH_TOKEN` | `wsl-cloud-init` | your GitHub token |
| `wsl-cloud-init:CONTEXT7_API_KEY` | `wsl-cloud-init` | your Context7 key |

### 5. Provision an instance

```powershell
.\windows\provision.ps1 -DistroTemplatePath ubuntu -DistroInstallName Ubuntu -InstanceName dev
```

- `-Branch <name>` — provision from a branch other than `main`.
- `-Force` — replace an existing instance of the same name (destroys it first).

The script renders the cloud-init config, installs Ubuntu, waits for cloud-init to finish, then launches you into the new instance — signed in as a Linux user derived from your Windows username, with passwordless sudo and `zsh` as the shell.

## What you get

Every provisioned instance comes ready with:

### Shell
Zsh is the default shell, set up with **[Oh My Zsh](https://ohmyz.sh)** — autosuggestions plus the git, docker, z, sudo, and pj plugins — and **[direnv](https://direnv.net)** for per-directory environment loading.

### Language runtimes
**[fnm](https://github.com/Schniz/fnm)** (Node), **[pixi](https://pixi.sh)** (Python), and **[SDKMAN](https://sdkman.io)** (JVM) are installed and wired into direnv, so the right versions activate automatically as you enter each project (see [Usage](#direnv)).

### Docker
**[Docker](https://docs.docker.com/engine/)** Engine, the CLI, and the Compose plugin — ready to run without extra setup.

### Claude Code
The **Claude Code** CLI, pre-wired to the **[Context7](https://context7.com)** MCP for up-to-date library docs, plus a bundled install-script skill.

### Windows interop
These commands reach from the Linux shell back into Windows:

- **`code`** — opens files and folders in your Windows VS Code.
- **`open`** — launches a file or URL with its default Windows app.

Git itself authenticates through Windows **[Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager)**, reusing your existing Windows sign-in.

### Shell helpers
`clone-repo`, `create-repo`, and `update-branch` streamline everyday Git work, and `pj` jumps between checkouts under `~/projects` — see [Usage](#usage).

### Base packages
Installed from the cloud-init package list:

- build-essential
- curl
- direnv
- gh (GitHub CLI)
- git
- jq
- unzip
- zip
- zsh

## Usage

Day-to-day commands and per-project setup the provisioned environment adds. The underlying tools (Docker, Node, Python, Java) keep their own docs; provisioning lives in [Getting Started](#getting-started).

### direnv
fnm, pixi, and SDKMAN aren't on your global `PATH` — each project activates the versions it needs through direnv (already hooked into your shell). Add an `.envrc` to the project root with the directives you need:

```bash
# .envrc
use fnm node 22.14.0     # Node via fnm
use pixi                 # Python environment from pixi.toml (created if missing)
use sdk java 21.0.2-tem  # JVM SDK via SDKMAN
```

then approve it with `direnv allow`. direnv activates these on entry and removes them on exit, and installs the requested versions automatically on first use. Versions must be fully qualified — an exact release such as `22.14.0` or `21.0.2-tem`, not a partial like `22` or `lts`.

#### Auto-update on branch switch
The `use update-branch` directive runs [update-branch](#update-branch) automatically, rebasing the current branch onto the remote default whenever you switch branches in the project:

```bash
# .envrc
use update-branch
```

### clone-repo
Clone one of your GitHub repos into `~/projects/<name>` and drop you inside it. Tab-completion lists your repos; re-running just `cd`s into an existing checkout.

```bash
clone-repo my-project                 # clones <you>/my-project
clone-repo --owner some-owner service # clones some-owner/service
```

Cloning a private repo uses the GitHub token's **Contents (read)** permission — see [Getting Started](#3-create-two-tokens).

### create-repo
Create a new **private** GitHub repo, clone it to `~/projects/<name>`, seed a README and initial commit, and `cd` in.

```bash
create-repo my-new-project             # creates <you>/my-new-project
create-repo --owner some-owner service # creates some-owner/service
```

Creating and pushing use the token's **Administration (create)** and **Contents (write)** permissions.

### pj
Jump straight into a checked-out repository under `~/projects` without typing the full path — supports Tab-completion.

```bash
pj my-project   # cd into ~/projects/my-project
```

### update-branch
Rebase the current branch onto the remote's default branch (e.g. `main`). Run it manually, or let direnv run it automatically whenever you switch branches inside a project.

```bash
update-branch
```

It refuses on a dirty working tree or detached HEAD, and stops on rebase conflicts so you can resolve them.

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

<!-- Credential keys, template substitutions, environment variables passed to install scripts, and the
     derived target user ($env:USERNAME lowercased/stripped to [a-z0-9_-]; passwordless sudo, docker group,
     zsh shell, set as the WSL default user). -->

## Troubleshooting

<!-- Common issues: instance already exists, cloud-init didn't finish, WSL binfmt interop fix, credential retrieval failures. -->
