#!/bin/bash
set -euo pipefail

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  [[ -n "${2:-}" ]] && echo "$2"
  exit 1
}

# --- Docker run ---
if output=$(docker run --rm hello-world 2>&1); then
  pass "docker run hello-world"
else
  fail "docker run hello-world" "$output"
fi

# --- Docker Compose ---
COMPOSE_DIR=$(mktemp -d)
cat > "$COMPOSE_DIR/compose.yaml" <<'EOF'
services:
  hello:
    image: hello-world
EOF

if output=$(docker compose -f "$COMPOSE_DIR/compose.yaml" run --rm hello 2>&1); then
  pass "docker compose run hello-world"
else
  fail "docker compose run hello-world" "$output"
fi

rm -rf "$COMPOSE_DIR"

# --- Log driver ---
if output=$(docker info --format '{{.LoggingDriver}}' 2>&1); then
  if [[ "$output" == "local" ]]; then
    pass "docker log driver is 'local'"
  else
    fail "docker log driver is '$output', expected 'local'"
  fi
else
  fail "docker info failed" "$output"
fi

