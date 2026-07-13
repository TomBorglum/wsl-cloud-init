---
layout: default
title: "wsl-cloud-init — one-command WSL Ubuntu developer environment"
description: >-
  Provision a fully configured WSL Ubuntu developer environment with one command,
  using cloud-init — zsh, Docker, language runtimes, Git, and Windows interop,
  ready to work in.
---

# wsl-cloud-init

<p class="tagline">A fully configured WSL Ubuntu developer environment from a single command — so you're productive immediately.</p>

Setting up a productive **WSL** environment by hand is slow and easy to get subtly
wrong — installing tools, configuring the shell, wiring up Git credentials, and
bridging Windows apps, repeated for every new instance.

**wsl-cloud-init** replaces that with one repeatable step. It uses
[**cloud-init**](https://cloud-init.io) to declaratively build a fresh **Ubuntu**
instance with a curated, opinionated set of tools — so every instance you create
comes out the same, fully configured and ready to work in.

<a class="btn" href="https://github.com/TomBorglum/wsl-cloud-init">View on GitHub</a>
<a class="btn" href="https://github.com/TomBorglum/wsl-cloud-init#getting-started">Get started</a>

## What you get

Every provisioned instance comes ready with:

- **Zsh + Oh My Zsh** — autosuggestions and the git, docker, z, sudo, and pj plugins, plus **direnv** for per-directory environment loading.
- **Language runtimes** — fnm (Node), pixi (Python), and SDKMAN (JVM), wired into direnv so the right versions activate per project.
- **Docker** — Engine, CLI, and Compose, plus the lazydocker terminal UI — ready with no extra setup.
- **Windows interop** — `open` launches files and URLs with their default Windows app.
- **Claude Code** *(opt-in: `-InstallClaudeCode`)* — the CLI pre-wired to the Context7 MCP for up-to-date library docs, plus an `add-sonarqube-mcp` helper that enables the SonarQube Cloud MCP per project via a secret-free, committable `.mcp.json` (great for private repos).
- **Git, the easy way** *(opt-in: `-InstallGitConfig`)* — your Git identity, `gh` auth, and Git Credential Manager reusing your existing Windows sign-in, plus `clone-repo` / `create-repo` / `create-branch` / `rebase-branch` / `prune-branches` helpers.
- **VS Code** *(opt-in: `-InstallVsCodeInterop`)* — `code` opens files and folders in your Windows VS Code.

## Provision in one command

You need only an up-to-date **WSL 2** and **Git for Windows**. Then, in
**PowerShell**:

```powershell
git clone https://github.com/TomBorglum/wsl-cloud-init.git
cd wsl-cloud-init
powershell -ExecutionPolicy Bypass -File .\windows\scripts\provision.ps1 `
  -DistroTemplatePath ubuntu `
  -DistroInstallName Ubuntu-26.04 `
  -InstanceName dev
```

The script renders the cloud-init config, installs Ubuntu, waits for setup to
finish, and launches you into the new instance — signed in with passwordless sudo
and `zsh` as your shell. Pinned Ubuntu LTS versions are supported: `Ubuntu-26.04`,
`Ubuntu-24.04`, and `Ubuntu-22.04`. To provision a released version instead of the
latest, run `windows\scripts\checkout-ref.ps1 -Ref v<version>`; it checks that version
out and prints a copy-paste-ready provision command.

See the [full documentation and opt-in features](https://github.com/TomBorglum/wsl-cloud-init#readme)
on GitHub.
