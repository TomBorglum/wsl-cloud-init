#!/bin/bash
# Entry point for a Claude Code cloud session's setup script, which is a field in the
# environment dialog at claude.ai/code and therefore the one piece of this that cannot
# live in a repository. Keep that field to the three lines that fetch and run this:
#
#   #!/bin/bash
#   curl -fsSL --proto '=https' --tlsv1.2 \
#     https://raw.githubusercontent.com/TomBorglum/wsl-cloud-init/main/cloud/bootstrap.sh | bash
#
# Everything else is here, so the cloud session is a third consumer of the same .envrc
# contract the terminal (wsl/) and CI (actions/setup-direnv/) already honour, rather
# than a second setup to keep in step.
#
# Deliberately NOT `set -e`. A setup script that exits non-zero blocks the session from
# starting outright, which is a worse outcome than a session whose environment is
# incomplete - there you can at least ask Claude what went wrong. So every failure is
# recorded and reported, and the exit status is always 0.
set -uo pipefail
# Without this an empty cloud/scripts/ leaves the glob as a literal path, which the
# loop below then reports as a script that failed with status 127.
shopt -s nullglob

REF="${CLOUD_BOOTSTRAP_REF:-main}"
# codeload serves a public repo's tarball without touching the GitHub API or a release
# asset, both of which the session's GitHub proxy scopes to repositories attached to the
# session. It is on the default Trusted allowlist, so this needs no custom network config.
TARBALL="https://codeload.github.com/TomBorglum/wsl-cloud-init/tar.gz/refs/heads/$REF"
REPO=/opt/wsl-cloud-init
STATE=/var/lib/cloud-bootstrap
LOG=/var/log/cloud-bootstrap.log

# The setup script's output is not surfaced anywhere a session can read, so keep a log
# on disk. The environment cache snapshots the filesystem, so it survives to later
# sessions and is the first thing to look at when the environment is wrong.
exec > >(tee -a "$LOG") 2>&1
echo "cloud-bootstrap: starting at $(date -u +%FT%TZ), ref=$REF"

mkdir -p "$STATE"
rm -f "$STATE/failed"

fail() {
  echo "cloud-bootstrap: $*" >&2
  echo "$*" >> "$STATE/failed"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL --proto '=https' --tlsv1.2 "$TARBALL" -o "$tmp/repo.tar.gz"; then
  fail "could not fetch $TARBALL"
  exit 0
fi

# The tarball's checksum, not bootstrap.sh's, is what cloud-bootstrap-refresh compares
# against: a change to lib/pixi.sh or to a numbered script has to count as a change, and
# hashing this file alone would miss every one of them.
sha="$(sha256sum "$tmp/repo.tar.gz" | cut -d' ' -f1)"

if ! tar -xzf "$tmp/repo.tar.gz" -C "$tmp"; then
  fail "could not extract the repository tarball"
  exit 0
fi
src="$(find "$tmp" -maxdepth 1 -type d -name 'wsl-cloud-init-*' | head -n1)"
if [[ -z "$src" ]]; then
  fail "the tarball did not contain a wsl-cloud-init-* directory"
  exit 0
fi
rm -rf "$REPO"
mkdir -p "$(dirname "$REPO")"
mv "$src" "$REPO"

# The install scripts read these. CLOUD_HOME is where the per-user payload lands: the
# session runs as the same account the setup script does, so $HOME is right - but it is
# named and overridable here so a single variable moves it if that ever stops being true.
export CLOUD_HOME="${CLOUD_HOME:-$HOME}"
export CLOUD_BOOTSTRAP_REF="$REF"

# Same exit-code contract as wsl/distros/ubuntu/install.sh, so a script that skipped is
# distinguishable from one that did work:
#   0 did the work   3 already installed   4 not selected   * failed
STATUS_ALREADY_INSTALLED=3
STATUS_NOT_SELECTED=4

failed=0
scripts=("$REPO"/cloud/scripts/*.sh)
if (( ${#scripts[@]} == 0 )); then
  fail "no install scripts found in $REPO/cloud/scripts"
  exit 0
fi
for script in "${scripts[@]}"; do
  name="$(basename "$script")"
  rc=0
  bash "$script" </dev/null || rc=$?
  case $rc in
    0)                         echo "cloud-bootstrap: $name -> ok" ;;
    $STATUS_ALREADY_INSTALLED) echo "cloud-bootstrap: $name -> already installed" ;;
    $STATUS_NOT_SELECTED)      echo "cloud-bootstrap: $name -> not selected" ;;
    # Keep going rather than aborting. The scripts are independent, and a session with
    # direnv but no pixi is more useful - and easier to diagnose - than one with neither.
    *)                         fail "$name failed with status $rc"; failed=1 ;;
  esac
done

if (( failed )); then
  echo "cloud-bootstrap: finished with failures; see $LOG and $STATE/failed"
else
  # Recorded only on a clean run, so a partial install re-runs next session instead of
  # being mistaken for current by cloud-bootstrap-refresh.
  printf '%s\n' "$sha" > "$STATE/installed.sha256"
  echo "cloud-bootstrap: finished cleanly, tarball sha256=$sha"
fi

exit 0
