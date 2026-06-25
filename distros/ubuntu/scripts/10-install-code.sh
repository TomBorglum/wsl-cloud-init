#!/bin/bash
set -euo pipefail

if command -v code >/dev/null 2>&1; then
  echo "code already installed, skipping"
  exit 0
fi

: "${VSCODE:?VSCODE is required}"

tee /usr/local/bin/code > /dev/null << EOF
#!/bin/bash
$VSCODE "\$@"
EOF
chmod 755 /usr/local/bin/code
