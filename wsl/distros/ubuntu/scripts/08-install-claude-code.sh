#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_CLAUDE_CODE:-}" != "true" ]]; then
  echo "INSTALL_CLAUDE_CODE not set, skipping claude-code install"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.local/bin/claude" ]]; then
  echo "claude-code already installed for $TARGET_USER, skipping"
  exit 0
fi

# Resolve the Context7 API key from Windows Credential Manager via wsl_interop_credential
# (all the PowerShell lives in wsl-interop.sh). The secret is fetched inside PowerShell
# and returned on stdout; only the fetch code crosses the boundary, never the value. We are
# committed to installing here, so it is fetched unconditionally.
CONTEXT7_API_KEY="$(wsl_interop_credential "wsl-cloud-init:CONTEXT7_API_KEY")"
: "${CONTEXT7_API_KEY:?CONTEXT7_API_KEY is required}"

curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o /tmp/claude-install.sh
sudo -u "$TARGET_USER" bash /tmp/claude-install.sh
rm -f /tmp/claude-install.sh

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export PATH="$HOME/.local/bin:$PATH"
EOF

sudo -u "$TARGET_USER" /home/"$TARGET_USER"/.local/bin/claude mcp add context7 https://mcp.context7.com/mcp --transport http --scope user --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY"

# Claude settings and skills (per-user), sourced from the sparse checkout declared in
# user-data.template; cp -r for skills since that is a directory tree, not flat files
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude/skills"
sudo -u "$TARGET_USER" cp /opt/wsl-cloud-init/wsl/user/.claude/settings.json "/home/$TARGET_USER/.claude/settings.json"
sudo -u "$TARGET_USER" cp -r /opt/wsl-cloud-init/wsl/user/.claude/skills/. "/home/$TARGET_USER/.claude/skills/"
