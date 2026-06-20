#!/bin/bash
set -euo pipefail

if command -v open >/dev/null 2>&1; then
  echo "open already installed, skipping"
  exit 0
fi

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"
: "${POWERSHELL:?POWERSHELL is required}"

tee /usr/local/bin/open > /dev/null << EOF
#!/bin/bash
$POWERSHELL -NoProfile -c "Start-Process '\$1'"
EOF
chmod 755 /usr/local/bin/open

sudo -u "$LINUX_USERNAME" tee -a "/home/$LINUX_USERNAME/.zshenv" > /dev/null << 'EOF'
export BROWSER=open
EOF
