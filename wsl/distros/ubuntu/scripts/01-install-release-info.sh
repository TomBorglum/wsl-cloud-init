#!/bin/bash
set -euo pipefail

# Record which version of this project the instance was provisioned from, as sourceable
# KEY="value" pairs in the style of /etc/os-release.
#
# The file is written once, by cloud-init, and is immutable thereafter. cloud-init is the
# only caller that exports WSL_CLOUD_INIT_REF (user-data.template's runcmd runs install.sh
# directly as root), so that variable is what distinguishes a provisioning run from a manual
# re-run such as:
#
#   sudo INSTALL_GIT_CONFIG=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh
#
# On a re-run this script does not write: it *verifies* that /opt still sits at the commit
# the file records, and fails if it does not. That is the "already installed" guard other
# scripts spell as an early exit 0, inverted -- because a mismatch is not a no-op, it is an
# attempt to upgrade a running instance in place.
#
# Upgrading in place is not supported. The other install scripts guard on the presence of
# what they install (docker on PATH, ~/.sdkman, ...), so against a newer /opt most of them
# would skip and only the few that rewrite their payload unconditionally would apply,
# leaving an instance matching no commit and nothing to say so. Failing here, first, aborts
# the whole run (install.sh stops on any non-zero script) before that can happen.

RELEASE_FILE=/etc/wsl-cloud-init-release
REPO=/opt/wsl-cloud-init

COMMIT="$(git -C "$REPO" rev-parse HEAD)"
COMMIT_SHORT="$(git -C "$REPO" rev-parse --short=8 HEAD)"

# Provisioning run. /etc is fresh on a new instance, so this is the one place the file is
# ever created. REF cannot be derived here -- cloud-init leaves /opt detached, and a
# detached HEAD cannot name its branch -- so provision.ps1 resolves it and passes it in.
if [[ -n "${WSL_CLOUD_INIT_REF:-}" ]]; then
  : "${WSL_CLOUD_INIT_INSTANCE_NAME:?WSL_CLOUD_INIT_INSTANCE_NAME is required}"

  # Stage then install(1), so an interrupted write can never leave a truncated file behind.
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  cat > "$tmp" <<EOF
NAME="wsl-cloud-init"
ID=wsl-cloud-init
REF="$WSL_CLOUD_INIT_REF"
COMMIT="$COMMIT"
COMMIT_SHORT="$COMMIT_SHORT"
INSTANCE_NAME="$WSL_CLOUD_INIT_INSTANCE_NAME"
PRETTY_NAME="wsl-cloud-init $WSL_CLOUD_INIT_REF ($COMMIT_SHORT)"
SOURCE_URL="https://github.com/TomBorglum/wsl-cloud-init"
EOF
  install -m 644 "$tmp" "$RELEASE_FILE"

  echo "recorded $WSL_CLOUD_INIT_REF @ $COMMIT_SHORT in $RELEASE_FILE"
  exit 0
fi

# Re-run. Reaching here without the file means /opt was moved to a version that ships this
# script onto an instance provisioned before it existed -- an in-place upgrade by another
# name, since the older instance's own scripts/ has no 01-install-release-info.sh to run.
if [[ ! -f "$RELEASE_FILE" ]]; then
  echo "$RELEASE_FILE is missing" >&2
  exit 1
fi

# Read the recorded commit in a subshell, so sourcing the file cannot clobber $COMMIT.
RECORDED_COMMIT="$( . "$RELEASE_FILE" && printf '%s' "${COMMIT:-}" )"
RECORDED_SHORT="${RECORDED_COMMIT:0:8}"

if [[ "$RECORDED_COMMIT" != "$COMMIT" ]]; then
  echo "$RELEASE_FILE records $RECORDED_SHORT, but $REPO is at $COMMIT_SHORT" >&2
  exit 1
fi

echo "$RELEASE_FILE is current ($RECORDED_SHORT), skipping"
