#!/bin/zsh
set -euo pipefail

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "$2"
  exit 1
}

compdef() { }
for f in /usr/local/share/zsh/site-functions/*.zsh(N); do source "$f"; done

# --- gclone ---

gclone TomBorglum/wsl-cloud-init

if [[ -d ~/projects/wsl-cloud-init ]]; then
  pass "gclone: ~/projects/wsl-cloud-init was created"
else
  fail "gclone: ~/projects/wsl-cloud-init was not created"
fi

if [[ -d ~/projects/wsl-cloud-init/.git ]]; then
  pass "gclone: cloned directory is a git repo"
else
  fail "gclone: cloned directory is not a git repo"
fi

if [[ "$PWD" == "$HOME/projects/wsl-cloud-init" ]]; then
  pass "gclone: cd'd into the cloned directory"
else
  fail "gclone: did not cd into the cloned directory (PWD=$PWD)"
fi
