#!/bin/zsh
set -euo pipefail

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "$2"
  exit 1
}

if zsh -i -c 'whence -v clone-repo' 2>/dev/null | grep -q function; then
  pass "clone-repo function is available"
else
  fail "clone-repo function is not available"
fi

if zsh -i -c 'whence -v create-repo' 2>/dev/null | grep -q function; then
  pass "create-repo function is available"
else
  fail "create-repo function is not available"
fi

if zsh -i -c 'whence -v _clone-repo_complete' 2>/dev/null | grep -q function; then
  pass "_clone-repo_complete function is available"
else
  fail "_clone-repo_complete function is not available"
fi
