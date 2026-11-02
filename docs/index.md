---
layout: default
title: "wsl-cloud-init — one-command WSL Ubuntu developer environment"
description: >-
  Provision a configured WSL Ubuntu developer environment with one command,
  using cloud-init: zsh, Docker, language runtimes, Git, and Windows interop.
---

# wsl-cloud-init

<p class="tagline">A configured WSL Ubuntu developer environment from a single command.</p>

Setting up a WSL environment by hand means installing tools, configuring the
shell, wiring up Git credentials, and bridging Windows apps, repeated for every
new instance.

**wsl-cloud-init** replaces that with one repeatable step. It uses
[**cloud-init**](https://cloud-init.io) to build a fresh **Ubuntu** instance
from a declarative config, so every instance comes out the same.

<a class="btn" href="https://github.com/TomBorglum/wsl-cloud-init">View on GitHub</a>
<a class="btn" href="https://github.com/TomBorglum/wsl-cloud-init#getting-started">Get started</a>

## What you get

Every provisioned instance includes:

- **Zsh + Oh My Zsh** — autosuggestions and the git, docker, z, sudo, and pj plugins, plus **direnv** for per-directory environment loading.
- **Language runtimes** — fnm (Node), pixi (Python), and SDKMAN (JVM), wired into direnv so the right versions activate per project.
- **Docker** — Engine, CLI, and Compose, plus the lazydocker terminal UI.
- **Windows interop** — `open` launches files and URLs with their default Windows app.
- **Claude Code** *(opt-in: `-InstallClaudeCode`)* — the CLI pre-wired to the Context7 MCP for current library docs, with a writing style and bundled skills. A `use sonarqube_mcp` direnv directive gives a project a read-only SonarQube Cloud subagent through a secret-free, committable agent file, with no MCP server in the main session.
- **Git** *(opt-in: `-InstallGitConfig`)* — your Git identity, `gh` auth, and Git Credential Manager reusing your existing Windows sign-in, plus `clone-repo` / `create-repo` / `create-branch` / `rebase-branch` / `prune-branches` helpers.
- **VS Code** *(opt-in: `-InstallVsCodeInterop`)* — `code` opens files and folders in your Windows VS Code.
- **Zed** *(opt-in: `-InstallZedInterop`)* — `zed` opens files and folders in your Windows Zed.

## Provision in one command

Requires an up-to-date **WSL 2** and **Git for Windows**. In **PowerShell**:

```powershell
git clone https://github.com/TomBorglum/wsl-cloud-init.git
cd wsl-cloud-init
powershell -ExecutionPolicy Bypass -File .\windows\scripts\provision.ps1 `
  -DistroTemplatePath ubuntu `
  -DistroInstallName Ubuntu-26.04 `
  -InstanceName dev
```

The script renders the cloud-init config, installs Ubuntu, waits for setup to
finish, and launches the new instance, signed in with passwordless sudo and
`zsh` as the shell. Supported pinned Ubuntu LTS versions are `Ubuntu-26.04`,
`Ubuntu-24.04`, and `Ubuntu-22.04`. To provision a released version instead of
the latest, run `windows\scripts\checkout-ref.ps1 -Ref v<version>`; it checks
that version out and prints a copy-paste-ready provision command.

See the [full documentation and opt-in features](https://github.com/TomBorglum/wsl-cloud-init#readme)
on GitHub.
