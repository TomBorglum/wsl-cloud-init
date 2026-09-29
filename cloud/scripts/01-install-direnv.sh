#!/bin/bash
set -euo pipefail

# direnv for a Claude Code cloud session. The session's .claude/settings.json hooks run
# `direnv export bash` into $CLAUDE_ENV_FILE, so direnv is what turns the repository's
# committed .envrc into the PATH every later Bash command sees.
#
# From apt, not from actions/setup-direnv/install-direnv.sh, even though that one is
# pinned and checksummed. It fetches a GitHub *release asset*, and a cloud session's
# GitHub proxy scopes release-asset requests to repositories attached to the session -
# direnv/direnv is not one of them. apt's archive.ubuntu.com is on the default Trusted
# allowlist and needs no network configuration.
#
# The version therefore floats with the distro rather than being pinned. On 24.04 that
# is 2.32.1, which is the same version the provisioned WSL terminal runs; a newer distro
# would give something newer. Both use_pixi and use_sonarqube_mcp touch only long-stable
# direnv stdlib (watch_file, PATH_add), so the float is tolerable here in a way it is not
# in CI, where a pinned version is what makes a green run mean something.

if command -v direnv >/dev/null 2>&1; then
  echo "direnv already installed, skipping"
  exit 3  # already installed; see cloud/bootstrap.sh
fi

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
apt-get install -y -qq direnv

direnv version
