# Security Policy

## Supported Versions

This project provisions WSL development environments and is maintained on a
rolling basis. Fixes land only on `main`, so reproduce against the latest commit
on `main` before reporting an issue. Tagged releases can be provisioned but are
not patched; a fix ships in the next release.

## Reporting a Vulnerability

Do **not** open a public issue for a security vulnerability.

Report privately through GitHub's
[private vulnerability reporting](https://github.com/TomBorglum/wsl-cloud-init/security/advisories/new),
the **Security → Report a vulnerability** button on the repository. The report
stays confidential until a fix is available.

Include:

- A description of the vulnerability and its impact.
- Steps to reproduce, or a proof of concept.
- The affected script(s) or component(s) and the commit you observed it on.

Acknowledgement follows within a few days. Once the report is confirmed, a fix is
prepared and a GitHub Security Advisory published crediting the reporter, unless
you prefer to remain anonymous.

## Scope & Notes

This repository runs installer scripts that fetch tooling from upstream sources
(e.g. Docker, oh-my-zsh, fnm, SDKMAN, pixi, Claude Code, lazydocker) over HTTPS.
Compromise of those upstream sources is outside the control of this project.
Issues specific to *how this project fetches or executes* them are in scope.
