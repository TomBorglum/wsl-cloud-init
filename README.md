# wsl-cloud-init

An opinionated, cloud-init–driven way to provision a fully configured WSL Ubuntu developer environment from a single command — so you're productive immediately.

## Overview

Setting up a productive WSL environment by hand is slow and easy to get subtly wrong
— installing tools, configuring the shell, wiring up Git credentials, and bridging
Windows apps, repeated for every new instance.

wsl-cloud-init replaces that with one repeatable step. It uses cloud-init to
declaratively build a fresh WSL Ubuntu instance with a curated, opinionated set of
tools and configuration, so every instance you create comes out the same — fully
configured and ready to work in immediately.

Provisioning runs from Windows: a PowerShell script reads your Git identity and
secrets from Windows Credential Manager, renders a cloud-init template, installs the
distro, and waits for setup to finish. On first boot cloud-init runs a series of
scripts that build the environment and wire Windows tools — VS Code, Git
Credential Manager — into the Linux shell.

## Prerequisites

Everything is on the Windows side — the Ubuntu environment is built for you.

- **An up-to-date WSL 2** — run `wsl --update` to make sure you're current.
- **Git for Windows** — includes Git Credential Manager, which the provisioned instance reuses for authentication.
- **Visual Studio Code** with the `code` command on your `PATH`.

Accounts, tokens, and Git identity are set up in [Getting Started](#getting-started).

## Getting Started

<!-- Step-by-step: store credentials -> set Windows git identity -> run provision.ps1 -> first launch. -->

## What you get

<!-- The provisioned environment: Docker, fnm / pixi / sdkman, Oh My Zsh, Claude Code + Context7 MCP,
     Windows interop (code, open, Git Credential Manager), shell helpers (clone-repo, create-repo, update-branch). -->

## Usage

<!-- Running provision.ps1 (parameters, -Force, -Branch) and day-to-day commands after provisioning. -->

## Configuration

<!-- Credential keys, template substitutions, environment variables passed to install scripts. -->

## Troubleshooting

<!-- Common issues: instance already exists, cloud-init didn't finish, WSL binfmt interop fix, credential retrieval failures. -->
