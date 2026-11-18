#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_CLAUDE_CODE:-}" != "true" ]]; then
  echo "INSTALL_CLAUDE_CODE not set, skipping claude-code install"
  exit 4  # not selected; see install.sh
fi

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.local/bin/claude" ]]; then
  echo "claude-code already installed for $TARGET_USER, skipping"
  exit 3  # already installed; see install.sh
fi

# The secret is fetched inside PowerShell: only the fetch code crosses the interop boundary,
# never the value. Fetched unconditionally, since the install is already committed to here.
CONTEXT7_API_KEY="$(wsl_interop_credential "wsl-cloud-init:CONTEXT7_API_KEY")"
: "${CONTEXT7_API_KEY:?CONTEXT7_API_KEY is required}"

# The trap is what removes the download: a failure in the install exits before any `rm` would run.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o "$tmp"
# mktemp creates the file 0600 owned by root, and the installer below runs as $TARGET_USER.
chown "$TARGET_USER" "$tmp"
sudo -u "$TARGET_USER" bash "$tmp"

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export PATH="$HOME/.local/bin:$PATH"
EOF

sudo -u "$TARGET_USER" /home/"$TARGET_USER"/.local/bin/claude mcp add context7 https://mcp.context7.com/mcp --transport http --scope user --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY"

# Copied as $TARGET_USER so the files land user-owned rather than root-owned.
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude/skills"
sudo -u "$TARGET_USER" cp /opt/wsl-cloud-init/wsl/user/.claude/settings.json "/home/$TARGET_USER/.claude/settings.json"
sudo -u "$TARGET_USER" cp /opt/wsl-cloud-init/wsl/user/.claude/CLAUDE.md "/home/$TARGET_USER/.claude/CLAUDE.md"
sudo -u "$TARGET_USER" cp -r /opt/wsl-cloud-init/wsl/user/.claude/skills/. "/home/$TARGET_USER/.claude/skills/"
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude/agents"
sudo -u "$TARGET_USER" cp -r /opt/wsl-cloud-init/wsl/user/.claude/agents/. "/home/$TARGET_USER/.claude/agents/"
