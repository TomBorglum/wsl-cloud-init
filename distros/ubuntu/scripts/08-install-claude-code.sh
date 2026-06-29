#!/bin/bash
set -euo pipefail

if [[ "${INSTALL_CLAUDE_CODE:-}" != "true" ]]; then
  echo "INSTALL_CLAUDE_CODE not set, skipping claude-code install"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.local/bin/claude" ]]; then
  echo "claude-code already installed for $TARGET_USER, skipping"
  exit 0
fi

: "${CONTEXT7_API_KEY:?CONTEXT7_API_KEY is required}"

curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o /tmp/claude-install.sh
sudo -u "$TARGET_USER" bash /tmp/claude-install.sh
rm -f /tmp/claude-install.sh

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export ENABLE_CLAUDEAI_MCP_SERVERS=false
export PATH="$HOME/.local/bin:$PATH"
EOF

sudo -u "$TARGET_USER" /home/"$TARGET_USER"/.local/bin/claude mcp add context7 https://mcp.context7.com/mcp --transport http --scope user --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY"

sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude"
sudo -u "$TARGET_USER" tee "/home/$TARGET_USER/.claude/settings.json" > /dev/null << 'EOF'
{
  "permissions": {
    "deny": ["WebSearch"]
  },
  "spinnerTipsEnabled": false,
  "effortLevel": "low"
}
EOF

# Claude skills (per-user); cp -r since this is a directory tree, not flat files
git -C /opt/wsl-cloud-init sparse-checkout add distros/shared/claude/skills
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude/skills"
sudo -u "$TARGET_USER" cp -r /opt/wsl-cloud-init/distros/shared/claude/skills/. "/home/$TARGET_USER/.claude/skills/"
