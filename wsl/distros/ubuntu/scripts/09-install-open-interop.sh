#!/bin/bash
set -euo pipefail

if command -v open >/dev/null 2>&1; then
  echo "open already installed, skipping"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

# The wrapper reads $POWERSHELL from the environment at runtime (exported from ~/.zshenv,
# derived once in install.sh) rather than baking the path in. The quoted heredoc keeps
# $POWERSHELL and $1 literal so they resolve when `open` runs.
tee /usr/local/bin/open > /dev/null << 'EOF'
#!/bin/bash
"$POWERSHELL" -NoProfile -c "Start-Process '$1'"
EOF
chmod 755 /usr/local/bin/open

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export BROWSER=open
EOF
