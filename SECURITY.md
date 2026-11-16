# Security Policy

## Supported Versions

Fixes land only on `main`. Reproduce against the latest commit on `main` before
reporting. Tagged releases can be provisioned but are not patched; a fix ships in
the next release.

## Reporting a Vulnerability

Do **not** open a public issue for a security vulnerability.

Report privately through
[private vulnerability reporting](https://github.com/TomBorglum/wsl-cloud-init/security/advisories/new),
the **Security → Report a vulnerability** button on the repository. The report
stays confidential until a fix is available.

Include:

- A description of the vulnerability and its impact.
- Steps to reproduce, or a proof of concept.
- The affected script(s) or component(s) and the commit you observed it on.

Acknowledgement follows within a few days. A confirmed report gets a fix and a
GitHub Security Advisory crediting the reporter, unless you prefer to remain
anonymous.

## Scope & Notes

The installer scripts fetch tooling from upstream sources (Docker, oh-my-zsh,
fnm, SDKMAN, pixi, Claude Code, lazydocker) over HTTPS. Compromise of an upstream
source is outside this project's control. How this project fetches or executes
them is in scope.
