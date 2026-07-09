#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_GIT_CONFIG:-}" != "true" ]]; then
  echo "INSTALL_GIT_CONFIG not set, skipping git config"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

# Install the gh wrapper ahead of the apt-provided /usr/bin/gh on PATH. The wrapper
# authenticates gh on demand from the Windows "git:https://github.com" credential — on
# first use and after a token rotation — via the shared wsl_interop_credential helper,
# so no gh token is provisioned here. No eager sign-in: the wrapper handles it lazily on
# first use (mirroring 09, which likewise only installs its wrapper). The credential is
# the Git Credential Manager one, hence the INSTALL_GIT_CONFIG gate above.
#
# The wrapper is a real file under wsl/system (provided by the sparse checkout declared in
# user-data.template), installed (idempotent overwrite) with the executable bit. This runs
# before the git-config early-exit below so that on-demand re-runs of an already-configured
# instance still (re)install the wrapper.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/gh /usr/local/bin/gh

sudo -u "$TARGET_USER" git config --global fetch.prune true

if sudo -u "$TARGET_USER" git config --global user.email >/dev/null 2>&1; then
  echo "git already configured for $TARGET_USER, skipping"
  exit 0
fi

# Resolve the git config from Windows over interop via wsl_interop_git_config (all the
# PowerShell lives in wsl-interop.sh). We are committed to installing and none of
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
