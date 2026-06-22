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

# --- clone-repo ---

clone-repo TomBorglum/wsl-test-fixture

if [[ -d ~/projects/wsl-test-fixture ]]; then
  pass "clone-repo: ~/projects/wsl-test-fixture was created"
else
  fail "clone-repo: ~/projects/wsl-test-fixture was not created"
fi

if [[ -d ~/projects/wsl-test-fixture/.git ]]; then
  pass "clone-repo: cloned directory is a git repo"
else
  fail "clone-repo: cloned directory is not a git repo"
fi

if [[ "$PWD" == "$HOME/projects/wsl-test-fixture" ]]; then
  pass "clone-repo: cd'd into the cloned directory"
else
  fail "clone-repo: did not cd into the cloned directory (PWD=$PWD)"
fi

# Cleanup
rm -rf ~/projects/wsl-test-fixture
