#!/bin/bash
set -euo pipefail

if command -v open >/dev/null 2>&1; then
  echo "open already installed, skipping"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"
: "${POWERSHELL:?POWERSHELL is required}"

tee /usr/local/bin/open > /dev/null << EOF
#!/bin/bash
$POWERSHELL -NoProfile -c "Start-Process '\$1'"
EOF
chmod 755 /usr/local/bin/open

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export BROWSER=open
EOF
