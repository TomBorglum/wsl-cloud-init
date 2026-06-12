#!/bin/zsh
set -euo pipefail

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "$2"
  exit 1
}

if zsh -i -c 'whence -v gclone' 2>/dev/null | grep -q function; then
  pass "gclone function is available"
else
  fail "gclone function is not available"
fi

if zsh -i -c 'whence -v gcreate' 2>/dev/null | grep -q function; then
  pass "gcreate function is available"
else
  fail "gcreate function is not available"
fi

if zsh -i -c 'whence -v _gclone_complete' 2>/dev/null | grep -q function; then
  pass "_gclone_complete function is available"
else
  fail "_gclone_complete function is not available"
fi
