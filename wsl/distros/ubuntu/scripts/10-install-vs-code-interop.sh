#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/wsl-interop.sh"

if [[ "${INSTALL_VS_CODE_INTEROP:-}" != "true" ]]; then
  echo "INSTALL_VS_CODE_INTEROP not set, skipping VS Code interop install"
  exit 0
fi

if command -v code >/dev/null 2>&1; then
  echo "code already installed, skipping"
  exit 0
fi

# Resolve the Windows VS Code path over interop via wsl_interop_vscode_path (all the
# PowerShell lives in lib/wsl-interop.sh), mapping it to its /mnt form. We are committed
# to installing here (the code-already-installed case exits above), so it is resolved
# unconditionally.
VSCODE="$(wsl_interop_vscode_path)"
: "${VSCODE:?VSCODE is required}"

tee /usr/local/bin/code > /dev/null << EOF
#!/bin/bash
$VSCODE "\$@"
EOF
chmod 755 /usr/local/bin/code
