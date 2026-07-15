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

# Resolve the Windows Zed path over interop via wsl_interop_zed_path (all the
# PowerShell lives in wsl-interop.sh), mapping it to its /mnt form. We are committed
# to installing here (the zed-already-installed case exits above), so it is resolved
# unconditionally.
ZED="$(wsl_interop_zed_path)"
: "${ZED:?ZED is required}"

tee /usr/local/bin/zed > /dev/null << EOF
#!/bin/bash
$ZED "\$@"
EOF
chmod 755 /usr/local/bin/zed
