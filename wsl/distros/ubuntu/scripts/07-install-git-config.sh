#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/wsl-interop.sh"

if [[ "${INSTALL_GIT_CONFIG:-}" != "true" ]]; then
  echo "INSTALL_GIT_CONFIG not set, skipping git config"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

if sudo -u "$TARGET_USER" git config --global user.email >/dev/null 2>&1; then
  echo "git already configured for $TARGET_USER, skipping"
  exit 0
fi

# Resolve the git config from Windows over interop via wsl_interop_git_config (all the
# PowerShell lives in lib/wsl-interop.sh). We are committed to installing and none of
# the values are set yet, so each KEY=VALUE line is assigned directly; the assertions
# below prove the trio came back filled.
while IFS= read -r line; do
  case "$line" in
    GIT_CREDENTIAL_MANAGER=*) GIT_CREDENTIAL_MANAGER="${line#*=}" ;;
    GIT_NAME=*)               GIT_NAME="${line#*=}" ;;
    GIT_EMAIL=*)              GIT_EMAIL="${line#*=}" ;;
  esac
done < <(wsl_interop_git_config)

: "${GIT_CREDENTIAL_MANAGER:?GIT_CREDENTIAL_MANAGER is required}"
: "${GIT_NAME:?GIT_NAME is required}"
: "${GIT_EMAIL:?GIT_EMAIL is required}"

sudo -u "$TARGET_USER" git config --global credential.helper "$GIT_CREDENTIAL_MANAGER"
sudo -u "$TARGET_USER" git config --global user.name "$GIT_NAME"
sudo -u "$TARGET_USER" git config --global user.email "$GIT_EMAIL"
sudo -u "$TARGET_USER" git config --global init.defaultBranch main
