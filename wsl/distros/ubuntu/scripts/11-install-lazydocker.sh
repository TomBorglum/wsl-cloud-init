#!/bin/bash
set -euo pipefail

if command -v lazydocker >/dev/null 2>&1; then
  echo "lazydocker already installed, skipping"
  exit 3  # already installed; see install.sh
fi

# The embedded sums come from the release's checksums.txt and reject a release artifact
# replaced after the fact, even when the download itself succeeds. On upgrade, bump VERSION
# and refresh both from:
#   https://github.com/jesseduffield/lazydocker/releases/download/v<VERSION>/checksums.txt
VERSION=0.25.2

case "$(dpkg --print-architecture)" in
  amd64) ARCH=x86_64; SHA256=0d9dbfc26068b218e7ed84b104748cadc6e3cf733c0afd35465306fb39b9523c ;;
  arm64) ARCH=arm64;  SHA256=005c38b685aaa557e7d646d83a3dadb5024340eeed8c6a2e1949eee6f530de23 ;;
  *) echo "Unsupported architecture for lazydocker: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac

# The trap is what removes the download and the unpacked binary: a failed checksum exits
# before any `rm` would run.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --proto '=https' keeps the transfer HTTPS end to end, refusing a redirect that would
# downgrade to a clear-text protocol.
curl -fsSL --proto '=https' \
  "https://github.com/jesseduffield/lazydocker/releases/download/v${VERSION}/lazydocker_${VERSION}_Linux_${ARCH}.tar.gz" \
  -o "$tmp/lazydocker.tar.gz"

echo "${SHA256}  ${tmp}/lazydocker.tar.gz" | sha256sum -c -

tar -xzf "$tmp/lazydocker.tar.gz" -C "$tmp" lazydocker
install -m 0755 "$tmp/lazydocker" /usr/local/bin/lazydocker
