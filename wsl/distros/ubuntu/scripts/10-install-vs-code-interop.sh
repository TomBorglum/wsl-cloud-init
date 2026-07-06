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

# Resolve the Windows VS Code path over interop the same way 08 reaches into Windows:
# read $POWERSHELL (derived + exported by install.sh, persisted to ~/.zshenv) and
# dot-source the shared path helper (windows/lib/Wsl.ps1) to map the Windows path to its
# /mnt form. The derivation mirrors what install.sh previously emitted. An explicit
# VSCODE wins.
if [[ -z "${VSCODE:-}" ]]; then
  : "${POWERSHELL:?POWERSHELL is required}"
  git -C /opt/wsl-cloud-init sparse-checkout add windows/lib >/dev/null
  ps_program='$ProgressPreference = "SilentlyContinue"'$'\n'
  ps_program+="$(cat /opt/wsl-cloud-init/windows/lib/Wsl.ps1)"$'\n'
  ps_program+='$vsc = (Get-Command code).Source -replace "\.cmd$",""'$'\n'
  ps_program+='Write-Output (ConvertTo-WslPath $vsc)'
  encoded="$(printf '%s' "$ps_program" | iconv -t UTF-16LE | base64 | tr -d '\n')"
  VSCODE="$("$POWERSHELL" -NoProfile -NonInteractive -EncodedCommand "$encoded")"
  VSCODE="${VSCODE%$'\r'}"
fi
: "${VSCODE:?VSCODE is required}"

tee /usr/local/bin/code > /dev/null << EOF
#!/bin/bash
$VSCODE "\$@"
EOF
chmod 755 /usr/local/bin/code
