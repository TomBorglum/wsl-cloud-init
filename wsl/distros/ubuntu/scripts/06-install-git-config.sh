#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_GIT_CONFIG:-}" != "true" ]]; then
  echo "INSTALL_GIT_CONFIG not set, skipping git config"
  exit 4  # not selected; see install.sh
fi

: "${TARGET_USER:?TARGET_USER is required}"

# Installed ahead of the apt-provided /usr/bin/gh on PATH. The wrapper authenticates itself on
# demand, so no gh token is provisioned here. The credential it reads is the Git Credential
# Manager one, hence the INSTALL_GIT_CONFIG gate above.
#
# This runs before the git-config early exit below, so an on-demand re-run on an
# already-configured instance still reinstalls the wrapper.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/gh /usr/local/bin/gh

sudo -u "$TARGET_USER" git config --global fetch.prune true

if sudo -u "$TARGET_USER" git config --global user.email >/dev/null 2>&1; then
  echo "git already configured for $TARGET_USER, skipping"
  exit 3  # already installed; see install.sh
fi

# None of the three values is set at this point, so each KEY=VALUE line is assigned directly and
# the assertions below prove the trio came back filled.
while IFS= read -r line; do
  case "$line" in
    GIT_CREDENTIAL_MANAGER=*) GIT_CREDENTIAL_MANAGER="${line#*=}" ;;
    GIT_NAME=*)               GIT_NAME="${line#*=}" ;;
    GIT_EMAIL=*)              GIT_EMAIL="${line#*=}" ;;
    # Anything else is a blank line or output that leaked onto stdout. Dropping it is safe: a
    # key that failed to arrive surfaces in the assertions below.
    *)                        ;;
  esac
done < <(wsl_interop_git_config)

: "${GIT_CREDENTIAL_MANAGER:?GIT_CREDENTIAL_MANAGER is required}"
: "${GIT_NAME:?GIT_NAME is required}"
: "${GIT_EMAIL:?GIT_EMAIL is required}"

sudo -u "$TARGET_USER" git config --global credential.helper "$GIT_CREDENTIAL_MANAGER"
sudo -u "$TARGET_USER" git config --global user.name "$GIT_NAME"
sudo -u "$TARGET_USER" git config --global user.email "$GIT_EMAIL"
sudo -u "$TARGET_USER" git config --global init.defaultBranch main
