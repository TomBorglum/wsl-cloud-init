#!/bin/bash
# Populate SONARQUBE_TOKEN / SONARQUBE_ORG from Windows Credential Manager for the
# SonarQube Cloud MCP server, so a project's committed, secret-free .mcp.json (which
# references ${SONARQUBE_TOKEN:-} / ${SONARQUBE_ORG:-}) resolves at Claude launch time.
#
# Called from a project .envrc via a guard so the .envrc stays portable:
#   if declare -f sonarqube_mcp_env >/dev/null 2>&1; then sonarqube_mcp_env; fi
#
# CI-safe by construction: it respects any value already in the environment (e.g. a
# CI-injected secret) and is a no-op wherever the WSL interop bundle is absent (CI, or any
# non-WSL machine). The secret is read inside PowerShell by the shared wsl_interop_credential
# helper — only the fetch code crosses the boundary, never the value on argv.
sonarqube_mcp_env() {
  [[ -x "${POWERSHELL:-}" && -f /usr/local/lib/wsl-cloud-init/wsl-interop.sh ]] || return 0
  source /usr/local/lib/wsl-cloud-init/wsl-interop.sh
  local v
  if [[ -z "${SONARQUBE_TOKEN:-}" ]]; then
    v="$(wsl_interop_credential wsl-cloud-init:SONARQUBE_TOKEN 2>/dev/null || true)"
    [[ -n "$v" ]] && export SONARQUBE_TOKEN="$v"
  fi
  if [[ -z "${SONARQUBE_ORG:-}" ]]; then
    v="$(wsl_interop_credential wsl-cloud-init:SONARQUBE_ORG 2>/dev/null || true)"
    [[ -n "$v" ]] && export SONARQUBE_ORG="$v"
  fi
}
