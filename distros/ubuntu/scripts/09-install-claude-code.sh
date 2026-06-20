#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

if [[ -x "/home/$LINUX_USERNAME/.local/bin/claude" ]]; then
  echo "claude-code already installed for $LINUX_USERNAME, skipping"
  exit 0
fi

: "${CONTEXT7_API_KEY:?CONTEXT7_API_KEY is required}"

curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
sudo -u "$LINUX_USERNAME" bash /tmp/claude-install.sh
rm -f /tmp/claude-install.sh

sudo -u "$LINUX_USERNAME" tee -a "/home/$LINUX_USERNAME/.zshenv" > /dev/null << 'EOF'
export ENABLE_CLAUDEAI_MCP_SERVERS=false
export PATH="$HOME/.local/bin:$PATH"
EOF

sudo -u "$LINUX_USERNAME" /home/"$LINUX_USERNAME"/.local/bin/claude mcp add context7 https://mcp.context7.com/mcp --transport http --scope user --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY"

sudo -u "$LINUX_USERNAME" mkdir -p "/home/$LINUX_USERNAME/.claude"
sudo -u "$LINUX_USERNAME" tee "/home/$LINUX_USERNAME/.claude/settings.json" > /dev/null << 'EOF'
{
  "permissions": {
    "deny": ["WebSearch"]
  },
  "spinnerTipsEnabled": false,
  "effortLevel": "low"
}
EOF
