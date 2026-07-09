#!/bin/bash
set -euo pipefail

# Record which version of this project the instance was provisioned from, as
# sourceable KEY="value" pairs in the style of /etc/os-release.
#
# Runs first so the file exists even when a later install script fails and the only
# thing left to debug with is /var/log/cloud-init-output.log.
#
# Unlike the other install scripts there is no already-installed guard: the file must be
# rewritten whenever the commit changes, so re-provisioning refreshes it.

RELEASE_FILE=/etc/wsl-cloud-init-release
REPO=/opt/wsl-cloud-init

# Carry the previous values forward. A manual re-run of install.sh sets no
# WSL_CLOUD_INIT_* variables, and REF/INSTANCE_NAME cannot be recomputed from the
# checkout alone, so without this a re-run would blank them.
if [[ -f "$RELEASE_FILE" ]]; then
  # shellcheck source=/dev/null
  . "$RELEASE_FILE"
fi

# The commit is always authoritative: cloud-init leaves /opt detached at the provisioned
# commit, and its .git survives. --short=8 matches the form provision.ps1 prints.
COMMIT="$(git -C "$REPO" rev-parse HEAD)"
COMMIT_SHORT="$(git -C "$REPO" rev-parse --short=8 HEAD)"

# provision.ps1 resolves the ref Windows-side (tag, else branch, else short SHA) because a
# branch name cannot be recovered from a detached HEAD. The fallbacks below only fire on a
# manual re-run, or on an instance provisioned before this file existed.
REF="${WSL_CLOUD_INIT_REF:-${REF:-}}"
if [[ -z "$REF" ]]; then
  # Same tag rule as provision.ps1: newest tag on the commit, else the short SHA.
  REF="$(git -C "$REPO" tag --points-at HEAD --sort=-v:refname | head -n 1)"
  REF="${REF:-$COMMIT_SHORT}"
fi

INSTANCE_NAME="${WSL_CLOUD_INIT_INSTANCE_NAME:-${INSTANCE_NAME:-}}"

# Stage then install(1), so an interrupted write can never leave a truncated file behind.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
NAME="wsl-cloud-init"
ID=wsl-cloud-init
REF="$REF"
COMMIT="$COMMIT"
COMMIT_SHORT="$COMMIT_SHORT"
INSTANCE_NAME="$INSTANCE_NAME"
PRETTY_NAME="wsl-cloud-init $REF ($COMMIT_SHORT)"
SOURCE_URL="https://github.com/TomBorglum/wsl-cloud-init"
EOF
install -m 644 "$tmp" "$RELEASE_FILE"

echo "recorded $REF @ $COMMIT_SHORT in $RELEASE_FILE"
