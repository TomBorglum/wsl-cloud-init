#!/bin/bash
# use_sonarqube_mcp
#
# CI-only (GitHub Actions) direnv directive for the SonarQube Cloud MCP server. The action
# installs this file onto the runner's ~/.config/direnv/lib; it is never run outside GitHub
# Actions. Self-contained by design: it sources no other file in this repository.
#
# The MCP server is a developer convenience that feeds Claude; it has no role in CI, which
# runs the Sonar scanner directly. So this is a deliberate no-op — it exists only so a
# committed .envrc containing `use sonarqube_mcp` evaluates cleanly on the runner instead of
# failing with an undefined directive. It exports nothing.
use_sonarqube_mcp() {
  return 0
}
