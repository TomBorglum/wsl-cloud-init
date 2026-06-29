# Security Policy

## Supported Versions

This project provisions WSL development environments and is maintained on a
rolling basis. Only the latest commit on the `main` branch is supported; please
make sure you are on `main` before reporting an issue.

## Reporting a Vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report privately via GitHub's
[private vulnerability reporting](https://github.com/TomBorglum/wsl-cloud-init/security/advisories/new)
(the **Security → Report a vulnerability** button on the repository). This keeps
the report confidential until a fix is available.

When reporting, please include:

- A description of the vulnerability and its impact.
- Steps to reproduce, or a proof of concept.
- The affected script(s) or component(s) and the commit you observed it on.

You can expect an acknowledgement within a few days. Once confirmed, a fix will
be prepared and a GitHub Security Advisory published crediting the reporter
(unless you prefer to remain anonymous).

## Scope & Notes

This repository runs installer scripts that fetch tooling from upstream sources
(e.g. Docker, oh-my-zsh, fnm, SDKMAN, pixi, Claude Code, lazydocker) over HTTPS.
Compromise of those upstream sources is outside the control of this project;
issues specific to *how this project fetches or executes* them are in scope.
