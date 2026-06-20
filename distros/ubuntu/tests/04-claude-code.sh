#!/bin/bash
set -euo pipefail

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "$2"
  exit 1
}

if output=$(claude --version 2>&1); then
  pass "claude runs"
else
  fail "claude runs" "$output"
fi
