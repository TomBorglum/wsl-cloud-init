#!/bin/bash
# use_claude_env — direnv directive that makes Claude Code load this project's .envrc.
#
# Claude Code never evaluates an .envrc itself. On a workstation it works by inheritance:
# ~/.zshrc runs `eval "$(direnv hook zsh)"`, so a `claude` started from inside the project
# inherits an environment direnv has already applied. Start it from anywhere else — or
# start a cloud session, which has no parent shell at all — and none of the .envrc is in
# effect, so the runtimes it declares are simply absent.
#
# The fix is a committed .claude/settings.json whose SessionStart and CwdChanged hooks
# write `direnv export bash` into $CLAUDE_ENV_FILE, which Claude Code sources before each
# Bash command. That file is identical in every repository, so this directive writes it
# rather than leaving it to be transcribed out of the README into each new clone.
#
# Scaffold-and-commit, like use_pixi's pixi.toml and use_sonarqube_mcp's .mcp.json: the
# generated file belongs to the repository, and only a committed copy reaches a cloud
# session. CONTRIBUTING.md's optional-directive rule applies throughout — every failure
# warns and returns 0, so a problem here never takes down the runtime the same .envrc
# declares.
CLAUDE_ENV_TEMPLATE="$HOME/.config/claude/templates/settings.json"

use_claude_env() {
  # Validated rather than trusted, per the terminal/CI split in CONTRIBUTING.md. The
  # write location is derived, never passed: rejecting an argument now keeps the door
  # open to giving one a meaning later.
  if (( $# > 0 )); then
    log_error "use_claude_env: takes no arguments (got: $*)"
    return 0
  fi

  # The repository root, because that is the only directory Claude Code reads
  # .claude/settings.json from. A copy written beside an .envrc in a monorepo
  # subdirectory would look installed and do nothing at all. With no git repository
  # there is no root to find, so the .envrc's own directory is the best answer available.
  local root settings
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  [[ -n "$root" ]] || root="$PWD"
  settings="$root/.claude/settings.json"

  # Reload when the file changes, so deleting it re-scaffolds on the next cd instead of
  # staying gone until the .envrc itself is touched.
  watch_file "$settings"

  # A cloud session consumes this file and must never write it. Claude Code reads the
  # hooks when the session starts, before direnv has run, so anything written here cannot
  # take effect until the next session — and would surface as an untracked change in the
  # session's diff. cloud-bootstrap-refresh exists only where cloud/bootstrap.sh installed
  # it, which identifies a cloud session without needing an environment variable.
  if [[ -x /usr/local/bin/cloud-bootstrap-refresh ]]; then
    [[ -f "$settings" ]] && return 0
    log_error "use_claude_env: no $settings in this clone — Claude Code ran no direnv hook, so this .envrc is not on its PATH. Commit the file from a workstation."
    return 0
  fi

  if ! has jq; then
    log_error "use_claude_env: jq is not installed — $settings not updated"
    return 0
  fi
  if [[ ! -f "$CLAUDE_ENV_TEMPLATE" ]]; then
    log_error "use_claude_env: no template at $CLAUDE_ENV_TEMPLATE — $settings not updated"
    return 0
  fi

  # Nothing there yet: the template is exactly what a merge would produce, so copy it
  # verbatim and keep its formatting rather than reproducing it through jq.
  if [[ ! -f "$settings" ]]; then
    if mkdir -p "$root/.claude" && cp "$CLAUDE_ENV_TEMPLATE" "$settings"; then
      log_status "use_claude_env: created $settings — remember to commit it to git"
    else
      log_error "use_claude_env: could not create $settings"
    fi
    return 0
  fi

  # An existing file belongs to the repository — permissions, env, hooks of its own — so
  # add only the entries that are absent, keyed on the command string, and leave every
  # other key alone. Counting before merging is what keeps an already-correct repository
  # untouched: this runs on every cd, and rewriting a tracked file each time (jq reprints
  # the whole document) would put the working tree in permanent flux.
  local count_missing='
    . as $cur
    | [ $tpl[0].hooks
        | to_entries[]
        | . as $e
        | $e.value[].hooks[]
        | . as $h
        | select( ( ($cur.hooks[$e.key]) // [] )
                  | any( (.hooks // []) | any(.command == $h.command) )
                  | not )
      ] | length'
  local missing
  missing="$(jq --slurpfile tpl "$CLAUDE_ENV_TEMPLATE" "$count_missing" "$settings" 2>/dev/null)"
  if [[ -z "$missing" ]]; then
    log_error "use_claude_env: $settings is not valid JSON — left unchanged, Claude Code hooks not installed"
    return 0
  fi
  (( missing > 0 )) || return 0

  # Each missing entry is appended as its own group rather than folded into an existing
  # one: groups run in array order, so the result behaves identically while never
  # rewriting a group the repository already had.
  local merge='
    reduce ( $tpl[0].hooks | to_entries[] ) as $e (
      .;
      reduce ( $e.value[].hooks[] ) as $h (
        .;
        if ( (.hooks[$e.key] // []) | any( (.hooks // []) | any(.command == $h.command) ) )
        then .
        else .hooks[$e.key] = ( (.hooks[$e.key] // []) + [ { "hooks": [ $h ] } ] )
        end
      )
    )'
  local tmp
  tmp="$(mktemp "$settings.XXXXXX")" || {
    log_error "use_claude_env: could not write next to $settings"
    return 0
  }
  chmod --reference="$settings" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  if jq --slurpfile tpl "$CLAUDE_ENV_TEMPLATE" "$merge" "$settings" > "$tmp" && mv "$tmp" "$settings"; then
    log_status "use_claude_env: added $missing Claude Code direnv hook(s) to $settings — remember to commit it to git"
  else
    rm -f "$tmp"
    log_error "use_claude_env: could not update $settings"
  fi
  return 0
}
