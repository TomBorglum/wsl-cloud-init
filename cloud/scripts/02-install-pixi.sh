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
# apt-get update is not allowed to be fatal. The Anthropic-hosted image ships third-party
# PPAs (deadsnakes, ondrej/php) whose hosts are not on the Trusted allowlist, so they
# answer 403 and apt-get exits 100 even when archive.ubuntu.com - the only source these
# packages come from - refreshed correctly. Under set -e that aborts before anything is
# installed. The install below is the real gate: it fails loudly if the package genuinely
# is not available.
export DEBIAN_FRONTEND=noninteractive
# Said before apt runs, not after: apt prints its 403s as `E:` lines followed by "is no
# longer signed", which reads as a hard failure in a log someone is scanning for one.
echo "cloud-bootstrap: apt-get update may report 403s for the third-party PPAs this image ships (deadsnakes, ondrej/php); they are not on the Trusted allowlist and nothing here needs them" >&2
apt-get update -qq || echo "apt-get update reported errors (blocked third-party sources); continuing" >&2
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

# Installed by root, but read and run by the session account - so hand it over, the way
# the WSL scripts do with `install -o "$TARGET_USER"`. Read access would be enough for
# most of this, but pixi writes into its own home at runtime, and a root-owned tree there
# fails in a way that looks like a pixi bug rather than a provisioning one.
owner="$(stat -c '%u:%g' "$CLOUD_HOME" 2>/dev/null || true)"
if [[ -n "$owner" ]]; then
  chown -R "$owner" "$CLOUD_HOME/.pixi"
fi

# Also on PATH system-wide, so `pixi` resolves in a shell that has not loaded the .envrc
# yet - which is every shell before the SessionStart hook has run.
ln -sf "$PIXI_BIN" /usr/local/bin/pixi

"$PIXI_BIN" --version
