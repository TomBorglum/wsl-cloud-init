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

# --- repo-clone ---

repo-clone TomBorglum/wsl-test-fixture

if [[ -d ~/projects/wsl-test-fixture ]]; then
  pass "repo-clone: ~/projects/wsl-test-fixture was created"
else
  fail "repo-clone: ~/projects/wsl-test-fixture was not created"
fi

if [[ -d ~/projects/wsl-test-fixture/.git ]]; then
  pass "repo-clone: cloned directory is a git repo"
else
  fail "repo-clone: cloned directory is not a git repo"
fi

if [[ "$PWD" == "$HOME/projects/wsl-test-fixture" ]]; then
  pass "repo-clone: cd'd into the cloned directory"
else
  fail "repo-clone: did not cd into the cloned directory (PWD=$PWD)"
fi

# Cleanup
rm -rf ~/projects/wsl-test-fixture
