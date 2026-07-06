#!/bin/bash
set -euo pipefail

if [[ "${INSTALL_GIT_CONFIG:-}" != "true" ]]; then
  echo "INSTALL_GIT_CONFIG not set, skipping git config"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

if sudo -u "$TARGET_USER" git config --global user.email >/dev/null 2>&1; then
  echo "git already configured for $TARGET_USER, skipping"
  exit 0
fi

# Resolve the git identity from Windows over interop the same way 08/10 reach into
# Windows: read $POWERSHELL (derived + exported by install.sh, persisted to ~/.zshenv)
# and dot-source the shared path helper (windows/lib/Wsl.ps1). The derivations mirror
# what install.sh previously emitted. Explicit values win; the trio is resolved only
# when one is missing, and each KEY=VALUE line fills in just the unset ones.
if [[ -z "${GIT_CREDENTIAL_MANAGER:-}" ]] || [[ -z "${GIT_NAME:-}" ]] ||
   [[ -z "${GIT_EMAIL:-}" ]]; then
  : "${POWERSHELL:?POWERSHELL is required}"
  git -C /opt/wsl-cloud-init sparse-checkout add windows/lib >/dev/null
  ps_program='$ProgressPreference = "SilentlyContinue"'$'\n'
  ps_program+="$(cat /opt/wsl-cloud-init/windows/lib/Wsl.ps1)"$'\n'
  ps_program+='$gitExe = (Get-Command git).Source'$'\n'
  ps_program+='$credMgr = (Split-Path (Split-Path $gitExe -Parent) -Parent) + "\mingw64\bin\git-credential-manager.exe"'$'\n'
  ps_program+='Write-Output ("GIT_CREDENTIAL_MANAGER=" + (ConvertTo-WslPath $credMgr))'$'\n'
  ps_program+='Write-Output ("GIT_NAME=" + (git config --global user.name))'$'\n'
  ps_program+='Write-Output ("GIT_EMAIL=" + (git config --global user.email))'
  encoded="$(printf '%s' "$ps_program" | iconv -t UTF-16LE | base64 | tr -d '\n')"
  interop_output="$("$POWERSHELL" -NoProfile -NonInteractive -EncodedCommand "$encoded")"
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      GIT_CREDENTIAL_MANAGER=*) GIT_CREDENTIAL_MANAGER="${GIT_CREDENTIAL_MANAGER:-${line#*=}}" ;;
      GIT_NAME=*)               GIT_NAME="${GIT_NAME:-${line#*=}}" ;;
      GIT_EMAIL=*)              GIT_EMAIL="${GIT_EMAIL:-${line#*=}}" ;;
    esac
  done <<< "$interop_output"
fi

: "${GIT_CREDENTIAL_MANAGER:?GIT_CREDENTIAL_MANAGER is required}"
: "${GIT_NAME:?GIT_NAME is required}"
: "${GIT_EMAIL:?GIT_EMAIL is required}"

sudo -u "$TARGET_USER" git config --global credential.helper "$GIT_CREDENTIAL_MANAGER"
sudo -u "$TARGET_USER" git config --global user.name "$GIT_NAME"
sudo -u "$TARGET_USER" git config --global user.email "$GIT_EMAIL"
sudo -u "$TARGET_USER" git config --global init.defaultBranch main

# gh is not authenticated here. The gh wrapper (/usr/local/bin/gh, installed by
# 15-install-gh-auth.sh) authenticates on first use from the Windows
# "git:https://github.com" credential, so a rotated token is picked up automatically.
