#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

if sudo -u "$LINUX_USERNAME" git config --global user.email >/dev/null 2>&1; then
  echo "git already configured for $LINUX_USERNAME, skipping"
  exit 0
fi

: "${GIT_CREDENTIAL_MANAGER:?GIT_CREDENTIAL_MANAGER is required}"
: "${GIT_NAME:?GIT_NAME is required}"
: "${GIT_EMAIL:?GIT_EMAIL is required}"

sudo -u "$LINUX_USERNAME" git config --global credential.helper "$GIT_CREDENTIAL_MANAGER"
sudo -u "$LINUX_USERNAME" git config --global user.name "$GIT_NAME"
sudo -u "$LINUX_USERNAME" git config --global user.email "$GIT_EMAIL"
sudo -u "$LINUX_USERNAME" git config --global init.defaultBranch main
