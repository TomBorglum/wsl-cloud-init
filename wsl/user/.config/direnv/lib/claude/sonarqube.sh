#!/bin/bash
# use_sonarqube_mcp — direnv directive that enables the SonarQube Cloud MCP server for the
# current project, so Claude can read and fix Sonar issues (handy for private repos whose
# SonarCloud dashboards aren't publicly reachable). Add `use sonarqube_mcp` to a project's
# .envrc; both files it touches are secret-free and meant to be committed and shared.
#
# On first use it scaffolds a .mcp.json (like use_pixi scaffolds pixi.toml) whose env
# references ${SONARQUBE_TOKEN:-} / ${SONARQUBE_ORG:-}, and on every load it exports those
# from Windows Credential Manager so Claude can authenticate. The secret never touches disk in
# the project; direnv unsets the exports when you leave the directory.
#
# It runs in the direnv context, so it MUST NOT break the .envrc: every path returns (never
# exits), and unmet prerequisites are reported as warnings rather than failures. A correctly
# configured project is silent.
IMAGE="sonarsource/sonarqube-mcp:1.22.0.3040"

use_sonarqube_mcp() {
  # 1. Scaffold ./.mcp.json once. Ask the CLI whether the server is already registered via
  #    `claude mcp get`'s EXIT CODE only (0 = present, even when "Pending approval"; 1 = absent)
  #    rather than reaching into the .mcp.json schema — and never parse its human-readable
  #    output, which would be more brittle than the JSON. Warn (don't fail) if claude isn't
  #    available. claude mcp add's output goes to stderr because direnv captures the .envrc's
  #    stdout as the environment diff.
  if ! command -v claude >/dev/null 2>&1; then
    echo "direnv: use_sonarqube_mcp: 'claude' not on PATH — skipped .mcp.json setup." >&2
  elif claude mcp get sonarqube >/dev/null 2>&1; then
    :  # already registered — nothing to do
  elif claude mcp add sonarqube --scope project \
         --env 'SONARQUBE_TOKEN=${SONARQUBE_TOKEN:-}' \
         --env 'SONARQUBE_ORG=${SONARQUBE_ORG:-}' \
         -- docker run --init -i --rm -e SONARQUBE_TOKEN -e SONARQUBE_ORG "$IMAGE" >&2; then
    echo "direnv: use_sonarqube_mcp: added the sonarqube MCP server to .mcp.json." >&2
  else
    echo "direnv: use_sonarqube_mcp: 'claude mcp add' failed — .mcp.json not updated." >&2
  fi

  # 2. Export SONARQUBE_TOKEN / SONARQUBE_ORG from Windows Credential Manager. Warn (don't
  #    fail) if the interop bundle is unavailable or a credential isn't set; leave a value
  #    that's already in the environment untouched. direnv unsets these on leaving the dir.
  if [[ ! -x "${POWERSHELL:-}" || ! -f /usr/local/lib/wsl-cloud-init/wsl-interop.sh ]]; then
    echo "direnv: use_sonarqube_mcp: WSL interop unavailable — SONARQUBE_TOKEN/SONARQUBE_ORG not set." >&2
    return 0
  fi
  source /usr/local/lib/wsl-cloud-init/wsl-interop.sh
  local name val
  for name in SONARQUBE_TOKEN SONARQUBE_ORG; do
    [[ -n "${!name:-}" ]] && continue
    val="$(wsl_interop_credential "wsl-cloud-init:$name" 2>/dev/null || true)"
    if [[ -n "$val" ]]; then
      export "$name=$val"
    else
      echo "direnv: use_sonarqube_mcp: 'wsl-cloud-init:$name' not in Windows Credential Manager." >&2
      echo "        Add it (Windows PowerShell): cmdkey /generic:wsl-cloud-init:$name /user:wsl-cloud-init /pass:<value>" >&2
    fi
  done
  return 0
}
