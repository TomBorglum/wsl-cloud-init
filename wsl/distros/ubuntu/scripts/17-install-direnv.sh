#!/bin/bash
set -euo pipefail

if command -v direnv >/dev/null 2>&1; then
  echo "direnv already installed, skipping"
  exit 3  # already installed; see install.sh
fi

# 2.38.0 or newer is required: use_pixi calls require_allowed, which earlier releases do not
# define. Ubuntu's archive offers 2.37.1-1, which is why direnv is not in the cloud-init
# package list.
#
# direnv publishes bare per-arch binaries and no checksums file, so these sums are computed
# from the downloaded asset rather than copied from the publisher. They still reject an asset
# replaced after the fact. On upgrade, bump VERSION and recompute both with:
#   curl -fsSL https://github.com/direnv/direnv/releases/download/v<VERSION>/direnv.linux-<arch> | sha256sum
VERSION=2.38.2

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) SHA256=148820a187930d36ca6a204504e5cdb30d8396cd1a97e64c3b3f10d793c11247 ;;
  arm64) SHA256=ec2a32dbe2f19dd085bd9315a1b4ea88b55ec288aa7eabe8723490baf466cb23 ;;
  *) echo "Unsupported architecture for direnv: $ARCH" >&2; exit 1 ;;
esac

# The trap is what removes the download: a failed checksum exits before any `rm` would run.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 \
  "https://github.com/direnv/direnv/releases/download/v${VERSION}/direnv.linux-${ARCH}" \
  -o "$tmp"

echo "${SHA256}  ${tmp}" | sha256sum -c -

install -m 0755 "$tmp" /usr/local/bin/direnv
