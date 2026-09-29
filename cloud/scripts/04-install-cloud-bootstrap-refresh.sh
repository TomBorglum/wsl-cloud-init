#!/bin/bash
set -euo pipefail

# cloud-bootstrap-refresh: what makes tracking `main` actually reach a session.
#
# A cloud environment runs its setup script once, then snapshots the filesystem and
# replays that snapshot for every later session, skipping the setup script entirely. It
# re-runs only when the setup script's text changes, when the allowed hosts change, or
# when the snapshot expires after roughly seven days. Nothing in that list involves this
# repository, so a merge to main would otherwise sit unused for up to a week.
#
# A repository's SessionStart hook calls this if it exists; the command exists only where
# this script installed it, which is what scopes it to cloud sessions without the hook
# needing a CLAUDE_CODE_REMOTE check.
#
# No already-installed guard: overwriting is how a change to the refresh logic itself
# propagates.

REF="${CLOUD_BOOTSTRAP_REF:-main}"

cat > /usr/local/bin/cloud-bootstrap-refresh <<OUTER_EOF
#!/bin/bash
# Installed by wsl-cloud-init cloud/scripts/04-install-cloud-bootstrap-refresh.sh.
# Re-runs cloud/bootstrap.sh when the repository has moved since this VM was provisioned.
#
# Never \`set -e\`, and every step falls through on failure. This runs from a SessionStart
# hook before Claude does any work; a network blip here must cost nothing more than a
# stale toolchain.
set -uo pipefail

REF="${REF}"
TARBALL="https://codeload.github.com/TomBorglum/wsl-cloud-init/tar.gz/refs/heads/\$REF"
BOOTSTRAP="https://raw.githubusercontent.com/TomBorglum/wsl-cloud-init/\$REF/cloud/bootstrap.sh"
STATE=/var/lib/cloud-bootstrap

# /run is tmpfs, so it is empty on a fresh VM and cannot be captured in the environment
# snapshot. That is what makes this once per session rather than once per Bash command.
marker=/run/cloud-bootstrap.checked
[[ -e "\$marker" ]] && exit 0
: > "\$marker" 2>/dev/null || exit 0

# A failed bootstrap is snapshotted like any other filesystem state, and it writes no
# installed.sha256 - so the comparison below would have nothing to work from and the VM
# would stay broken until the cache expires, up to a week later. Retry instead. It is
# once per session (the marker above), and the usual causes are transient: a blocked
# mirror, a package index that was briefly unreachable.
if [[ -e "\$STATE/failed" ]]; then
  echo "cloud-bootstrap-refresh: the last bootstrap left failures, retrying" >&2
  curl -fsSL --proto '=https' --tlsv1.2 --max-time 60 "\$BOOTSTRAP" 2>/dev/null \\
    | CLOUD_BOOTSTRAP_REF="\$REF" bash || true
  exit 0
fi

installed="\$(cat "\$STATE/installed.sha256" 2>/dev/null || true)"
[[ -n "\$installed" ]] || exit 0

tmp="\$(mktemp)" || exit 0
# The tarball's checksum, so a change to any directive or install script counts - not
# just a change to bootstrap.sh. Deliberately not the GitHub API, which the session's
# proxy scopes to repositories attached to the session and would answer with a 403.
if ! curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 "\$TARBALL" -o "\$tmp" 2>/dev/null; then
  rm -f "\$tmp"
  exit 0
fi
current="\$(sha256sum "\$tmp" 2>/dev/null | cut -d' ' -f1)"
rm -f "\$tmp"

[[ -n "\$current" && "\$current" != "\$installed" ]] || exit 0

echo "cloud-bootstrap-refresh: wsl-cloud-init/\$REF has moved, re-running the bootstrap" >&2
# CLOUD_BOOTSTRAP_REF is passed through, not left to default: \$BOOTSTRAP already
# points at this ref, but the script re-reads the variable to pick the tarball, and
# without it a non-default ref would fetch bootstrap.sh from one place and its
# scripts from another.
curl -fsSL --proto '=https' --tlsv1.2 --max-time 60 "\$BOOTSTRAP" 2>/dev/null \\
  | CLOUD_BOOTSTRAP_REF="\$REF" bash || true
exit 0
OUTER_EOF

chmod 0755 /usr/local/bin/cloud-bootstrap-refresh
bash -n /usr/local/bin/cloud-bootstrap-refresh
echo "installed /usr/local/bin/cloud-bootstrap-refresh (ref=$REF)"
