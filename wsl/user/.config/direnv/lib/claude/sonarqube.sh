#!/bin/bash
# use_sonarqube_mcp — direnv directive that gives Claude a read-only SonarQube Cloud
# subagent for the current project, so it can collect Sonar issues on demand (handy for
# private repos whose SonarCloud dashboards aren't publicly reachable). Add
# `use sonarqube_mcp` to a project's .envrc; both files it touches are secret-free and meant
# to be committed and shared.
#
# The server is declared *inline in the subagent definition*, not registered with the
# session. That is the whole point: an inline server connects when the subagent starts and
# disconnects when it finishes, so the main session carries only the subagent's one-line
# description instead of the server's whole tool list on every request — and no container
# runs until Sonar data is actually wanted. The subagent is also the narrowest thing that can
# do the job: its tool allowlist is the Sonar server and nothing else (no file reads, no
# shell, no edits), and SONARQUBE_READ_ONLY makes the server itself refuse every write. It
# collects data; the session that delegated to it does the reasoning and the fixing.
#
# On first use it scaffolds a .claude/agents/sonarqube.md whose env references
# ${SONARQUBE_TOKEN:-} / ${SONARQUBE_ORG:-}, and on every load it exports those from Windows
# Credential Manager so the server can authenticate. The secret never touches disk in the
# project; direnv unsets the exports when you leave the directory. Nothing in the scaffolded
# file is specific to this instance, so a teammate who supplies those two variables their own
# way gets the same subagent from the repo.
#
# It runs in the direnv context, so it MUST NOT break the .envrc: every path returns (never
# exits), and unmet prerequisites are reported as warnings rather than failures. A correctly
# configured project is silent.
IMAGE="sonarsource/sonarqube-mcp:1.22.0.3040"

use_sonarqube_mcp() {
  # 1. Scaffold ./.claude/agents/sonarqube.md once. There is no `claude` subcommand that
  #    writes an agent file, so this is a plain heredoc — which also means the directive no
  #    longer depends on `claude` being on PATH at all. Guard on the file's absence and never
  #    rewrite it: this runs on every cd, and reformatting a tracked file each time would
  #    leave every consuming repository permanently dirty.
  #
  #    The heredoc is unquoted so $IMAGE expands; the two \${...} references are escaped so
  #    they reach the file literally, for Claude Code to expand from the environment exported
  #    in step 2. They keep their `:-` defaults deliberately — an unset variable *without* a
  #    default is passed through as the literal "${VAR}" text rather than an empty value,
  #    which the server would then try to authenticate with.
  #
  #    The file pins no model and no effort level: which model runs a subagent is the host's
  #    call, not the project's. On an instance this repo provisions, ~/.claude/settings.json
  #    already runs every subagent on haiku at low effort — and its
  #    CLAUDE_CODE_SUBAGENT_MODEL_FORCE makes Claude Code ignore a `model:` here outright, so
  #    pinning one would be dead config that reads as though it did something. What this file
  #    does pin is capability: the tool allowlist and the server's read-only mode, which is
  #    what the collect-don't-reason contract actually rests on.
  local agent_file=.claude/agents/sonarqube.md
  if [[ ! -f "$agent_file" ]]; then
    if ! mkdir -p "$(dirname "$agent_file")"; then
      echo "direnv: use_sonarqube_mcp: could not create $(dirname "$agent_file") — skipped subagent setup." >&2
    else
      cat > "$agent_file" <<EOF
---
name: sonarqube
description: >-
  Collects SonarQube Cloud data for this project — issues, security hotspots, rule
  descriptions and measures — and returns it verbatim. Use it when Sonar findings are
  needed, especially for a private repo whose dashboard is not publicly reachable. It
  reports data only; it never diagnoses, prioritises or fixes.
tools: mcp__sonarqube__*
omitClaudeMd: true
mcpServers:
  - sonarqube:
      type: stdio
      command: docker
      args: [run, --init, -i, --rm,
             -e, SONARQUBE_TOKEN, -e, SONARQUBE_ORG,
             -e, SONARQUBE_READ_ONLY, -e, SONARQUBE_TOOLSETS,
             "$IMAGE"]
      env:
        SONARQUBE_TOKEN: "\${SONARQUBE_TOKEN:-}"
        SONARQUBE_ORG: "\${SONARQUBE_ORG:-}"
        SONARQUBE_READ_ONLY: "true"
        SONARQUBE_TOOLSETS: projects,issues,rules,measures,security-hotspots
---

You collect SonarQube Cloud data. You do not interpret it.

- Call the Sonar tools to collect exactly what you were asked for, and nothing more. Do not
  guess at a project key: look it up, or report that you could not.
- Return what the tools gave you, one record per issue, keeping every field they report —
  issue key, rule key, type, severity, file path, line, message, status, creation date.
- Do not diagnose, rank, prioritise, explain root causes, or propose fixes. The session that
  delegated to you does all of that, and it cannot do it from a summary.
- Do not summarise away detail. If a result set is large, report the total count and return
  the full records for what was asked.
- On a tool error, return its text verbatim and stop. Do not retry with different arguments.
EOF
      echo "direnv: created $agent_file — remember to commit it to git" >&2
    fi
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
