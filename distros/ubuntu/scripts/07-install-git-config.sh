#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if sudo -u "$TARGET_USER" git config --global user.email >/dev/null 2>&1; then
  echo "git already configured for $TARGET_USER, skipping"
  exit 0
fi

: "${GIT_CREDENTIAL_MANAGER:?GIT_CREDENTIAL_MANAGER is required}"
: "${GIT_NAME:?GIT_NAME is required}"
: "${GIT_EMAIL:?GIT_EMAIL is required}"

sudo -u "$TARGET_USER" git config --global credential.helper "$GIT_CREDENTIAL_MANAGER"
sudo -u "$TARGET_USER" git config --global user.name "$GIT_NAME"
sudo -u "$TARGET_USER" git config --global user.email "$GIT_EMAIL"
sudo -u "$TARGET_USER" git config --global init.defaultBranch main
