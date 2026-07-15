#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_ZED_INTEROP:-}" != "true" ]]; then
  echo "INSTALL_ZED_INTEROP not set, skipping Zed interop install"
  exit 0
fi

if command -v zed >/dev/null 2>&1; then
  echo "zed already installed, skipping"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

# The wrapper is a real file under wsl/system (provided by the sparse checkout declared in
# user-data.template), installed (idempotent overwrite) with the executable bit. It reads
# $ZED from the environment at runtime rather than baking the path in.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/zed /usr/local/bin/zed

# Resolve the Windows Zed shell launcher over interop via wsl_interop_zed_path (all the
# PowerShell lives in wsl-interop.sh) and persist it for the wrapper to read at runtime,
# mirroring how install.sh persists POWERSHELL. The `command -v zed` guard above returns
# early once the wrapper is on PATH, so this append runs only on the first install.
# Written unquoted so its backslash-escaped spaces resolve when zsh sources .zshenv.
ZED="$(wsl_interop_zed_path)"
: "${ZED:?ZED is required}"
sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << EOF
export ZED=$ZED
EOF
