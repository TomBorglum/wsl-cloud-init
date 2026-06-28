#!/bin/bash
set -euo pipefail

if command -v lazydocker >/dev/null 2>&1; then
  echo "lazydocker already installed, skipping"
  exit 0
fi

VERSION=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest \
  | jq -r .tag_name | sed 's/^v//')
if [[ -z "$VERSION" ]] || [[ "$VERSION" = "null" ]]; then
  echo "Could not determine latest lazydocker version" >&2
  exit 1
fi

case "$(dpkg --print-architecture)" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=arm64 ;;
  *) echo "Unsupported architecture for lazydocker: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac

curl -fsSL \
  "https://github.com/jesseduffield/lazydocker/releases/download/v${VERSION}/lazydocker_${VERSION}_Linux_${ARCH}.tar.gz" \
  -o /tmp/lazydocker.tar.gz
tar -xzf /tmp/lazydocker.tar.gz -C /tmp lazydocker
install -m 0755 /tmp/lazydocker /usr/local/bin/lazydocker
rm -f /tmp/lazydocker.tar.gz /tmp/lazydocker
