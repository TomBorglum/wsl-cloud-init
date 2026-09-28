#!/bin/bash
set -euo pipefail

# pixi, pre-seeded to the path use_pixi looks for.
#
# use_pixi installs pixi itself when it is missing, from https://pixi.sh/install.sh. That
# is right for a workstation and wrong here twice over: pixi.sh is not on a cloud
# session's default Trusted allowlist, and the installer's payload is a GitHub release
# asset, which the session's GitHub proxy scopes to repositories attached to the session.
# The directive would fail and take the whole .envrc load with it.
#
# So install the binary here instead. use_pixi guards on `[[ ! -x "$pixi_bin" ]]`, so a
# pixi already at that exact path makes it skip its own download entirely - the directive
# needs no change and keeps working unmodified on a workstation.
#
# The source is the conda-forge package on conda.anaconda.org, which *is* allowlisted,
# pinned by version, build and sha256 in the same spirit as install-direnv.sh. A .conda
# archive is a zip of zstd-compressed tars; bin/pixi is a standalone binary inside the
# pkg- member, so nothing but the binary is extracted and no conda tooling is involved.

: "${CLOUD_HOME:?CLOUD_HOME is required}"

PIXI_BIN="$CLOUD_HOME/.pixi/bin/pixi"

if [[ -x "$PIXI_BIN" ]]; then
  echo "pixi already installed at $PIXI_BIN, skipping"
  exit 3  # already installed; see cloud/bootstrap.sh
fi

VERSION=0.81.0
BUILD=hf01adef_0
SHA256=691c4f465b27b9ed0aeee0849c5a1f8b234f1ef02d4c7d7572855bcca84d3e10

# unzip and zstd are archive utilities for the payload above, not a language runtime -
# the no-transient-dependency rule is about not dragging in node/python/java to install
# a tool, and neither of these is that.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq unzip zstd

pkg="/tmp/pixi-$VERSION.conda"
curl -fsSL --proto '=https' --tlsv1.2 \
  "https://conda.anaconda.org/conda-forge/linux-64/pixi-$VERSION-$BUILD.conda" -o "$pkg"
echo "$SHA256  $pkg" | sha256sum -c -

install -d "$CLOUD_HOME/.pixi/bin"
# -O to stdout rather than extracting in place: the member is a full package tree and
# only bin/pixi is wanted.
unzip -p "$pkg" "pkg-pixi-$VERSION-$BUILD.tar.zst" \
  | zstd -dc \
  | tar -xf - -O bin/pixi > "$PIXI_BIN"
chmod 0755 "$PIXI_BIN"
rm -f "$pkg"

# Also on PATH system-wide, so `pixi` resolves in a shell that has not loaded the .envrc
# yet - which is every shell before the SessionStart hook has run.
ln -sf "$PIXI_BIN" /usr/local/bin/pixi

"$PIXI_BIN" --version
