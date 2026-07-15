#!/bin/bash
set -euo pipefail

if [[ "${INSTALL_ZED_INTEROP:-}" != "true" ]]; then
  echo "INSTALL_ZED_INTEROP not set, skipping Zed interop install"
  exit 0
fi

if command -v zed >/dev/null 2>&1; then
  echo "zed already installed, skipping"
  exit 0
fi

# The wrapper is a real file under wsl/system (sparse-checked-out per
# user-data.template), installed idempotently with the executable bit. It resolves
# Zed's WSL-aware launcher itself at runtime via wsl_interop_zed_path (using
# $POWERSHELL from the env), so there is no per-editor value to persist here.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/zed /usr/local/bin/zed
