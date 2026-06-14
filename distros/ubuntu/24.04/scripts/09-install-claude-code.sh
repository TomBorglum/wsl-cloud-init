#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
sudo -u "$LINUX_USERNAME" bash /tmp/claude-install.sh
rm -f /tmp/claude-install.sh

export ENABLE_CLAUDEAI_MCP_SERVERS=false
sudo -u "$LINUX_USERNAME" claude mcp add --transport http --scope user --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY" context7 https://mcp.context7.com/mcp
