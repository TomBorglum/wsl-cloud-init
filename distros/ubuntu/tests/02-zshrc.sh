#!/bin/zsh
set -euo pipefail

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "$2"
  exit 1
}

if zsh -i -c 'whence -v repo-clone' 2>/dev/null | grep -q function; then
  pass "repo-clone function is available"
else
  fail "repo-clone function is not available"
fi

if zsh -i -c 'whence -v repo-create' 2>/dev/null | grep -q function; then
  pass "repo-create function is available"
else
  fail "repo-create function is not available"
fi

if zsh -i -c 'whence -v _repo-clone_complete' 2>/dev/null | grep -q function; then
  pass "_repo-clone_complete function is available"
else
  fail "_repo-clone_complete function is not available"
fi
