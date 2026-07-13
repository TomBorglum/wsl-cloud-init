#!/bin/bash
set -euo pipefail

# The SonarQube Cloud MCP server is only useful with Claude Code and only inside specific
# (private) projects, so it is not registered globally like Context7. Instead we install a
# dormant `add-sonarqube-mcp` command that the user runs from within a project to write a
# committed-friendly, secret-free .mcp.json + .envrc (the token/org are supplied at runtime
# by the sonarqube_mcp_env direnv lib, installed at step 14). That command is meaningless
# without Claude, so its install rides on the same INSTALL_CLAUDE_CODE opt-in rather than
# adding a provisioning flag of its own. See add-sonarqube-mcp itself.
if [[ "${INSTALL_CLAUDE_CODE:-}" != "true" ]]; then
  echo "INSTALL_CLAUDE_CODE not set, skipping add-sonarqube-mcp install"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

# The command is a real file under wsl/system (provided by the sparse checkout declared in
# user-data.template), installed (idempotent overwrite) with the executable bit. It writes
# the project files and pulls its Docker image lazily at runtime, so nothing is needed here
# beyond placing the file on PATH. (The direnv lib it relies on ships under wsl/user and is
# installed separately by 14-install-direnv-functions.sh.)
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/add-sonarqube-mcp /usr/local/bin/add-sonarqube-mcp
