#!/bin/bash
set -euo pipefail

if [[ "${INSTALL_VS_CODE_INTEROP:-}" != "true" ]]; then
  echo "INSTALL_VS_CODE_INTEROP not set, skipping VS Code interop install"
  exit 0
fi

if command -v code >/dev/null 2>&1; then
  echo "code already installed, skipping"
  exit 0
fi

# The wrapper is a real file under wsl/system (sparse-checked-out per
# user-data.template), installed idempotently with the executable bit. It resolves
# VS Code's WSL-aware launcher itself at runtime via wsl_interop_vscode_path (using
# $POWERSHELL from the env), so there is no per-editor value to persist here.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/code /usr/local/bin/code
