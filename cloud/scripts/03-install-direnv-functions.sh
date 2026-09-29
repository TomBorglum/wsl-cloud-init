#!/bin/bash
set -euo pipefail
shopt -s nullglob

# The direnv directives, the pixi templates they scaffold from, and direnv's own config.
#
# This is the cloud counterpart of wsl/distros/ubuntu/scripts/13-install-direnv-functions.sh
# and installs the same terminal copy of the directives, wsl/user/.config/direnv/lib -
# not the actions/setup-direnv/lib copy. CONTRIBUTING.md keeps those two deliberately
# different, and a cloud session is on the terminal side of that split: real direnv
# evaluates the .envrc and owns PATH through PATH_add, with nothing like $GITHUB_PATH in
# the picture.
#
# No already-installed guard, matching its WSL counterpart: this is configuration to keep
# in sync rather than a payload to install once, and install(1) overwrites cleanly, so
# re-running is how a directive change reaches an environment that already has the old one.

: "${CLOUD_HOME:?CLOUD_HOME is required}"

REPO=/opt/wsl-cloud-init
LIB_SRC="$REPO/wsl/user/.config/direnv/lib"
LIB_DST="$CLOUD_HOME/.config/direnv/lib"

# Both the runtime directives and the claude/ subdir, flat - direnv globs its lib
# directory non-recursively. Unlike WSL there is no INSTALL_CLAUDE_CODE gate: a cloud
# session is Claude Code by definition. use_sonarqube_mcp in particular must be defined
# even though a container can never reach Windows Credential Manager, because a
# repository whose .envrc calls it would otherwise fail to load; the directive is written
# to warn and return 0 when its prerequisites are missing.
install -d "$LIB_DST"
for dir in "$LIB_SRC" "$LIB_SRC/claude"; do
  files=("$dir"/*.sh)
  if [[ ${#files[@]} -gt 0 ]]; then
    install -m 644 "${files[@]}" "$LIB_DST/"
  fi
done

# use_pixi scaffolds a missing pixi.toml from these. A repository that commits its own
# never reaches that path, but `use pixi python` in one that does not would fail on a
# missing template rather than falling back.
TPL_SRC="$REPO/wsl/user/.config/pixi/templates"
TPL_DST="$CLOUD_HOME/.config/pixi/templates"
templates=("$TPL_SRC"/*.toml)
if [[ ${#templates[@]} -gt 0 ]]; then
  install -d "$TPL_DST"
  install -m 644 "${templates[@]}" "$TPL_DST/"
fi

# ~/.config/claude/templates is deliberately NOT installed here, though its WSL
# counterpart 16-install-claude-templates.sh does install it. use_claude_env consumes a
# cloud session's .claude/settings.json and never writes one - the hooks are read before
# direnv runs, so a file written here could not take effect until the next session, and
# would show up as an untracked change in the session's diff. The directive itself is
# installed by the claude/ glob above, which is what a committed `use claude_env` needs
# in order to evaluate; without the template it can only warn, which is the intended
# behaviour on the one path that reaches it (a bootstrap where 04 failed and left no
# cloud-bootstrap-refresh for the directive to detect).

# direnv's own configuration. Written only here, for cloud sessions - a workstation gets
# no direnv.toml, and the trust decision below would be wrong on one.
#
# [whitelist] prefix makes every .envrc under these roots load without `direnv allow`.
# That is deliberate, and it is the whole reason a repository needs no per-repo setup: a
# fresh clone is trusted the moment it lands, for this repository and any other. The
# security trade is real - direnv's man page warns that anyone able to write into the
# directory can then execute arbitrary code - but it buys nothing in a cloud session,
# where Claude already has an unrestricted Bash tool on a disposable single-tenant VM
# holding the user's own repository. `direnv allow` there is friction, not a boundary.
#
# The roots are broad on purpose, and overridable with CLOUD_DIRENV_PREFIXES (a
# colon-separated list), because the path a cloud session clones into is not documented.
# A prefix that misses it produces no error at all - just an .envrc that never loads and
# a PATH with nothing on it - so this is the one value worth being able to correct
# without editing the script.
PREFIXES="${CLOUD_DIRENV_PREFIXES:-$CLOUD_HOME:/workspace:/repo:/src}"
prefix_toml=""
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  prefix_toml+="${prefix_toml:+, }\"$p\""
done <<< "${PREFIXES//:/$'\n'}"

install -d "$CLOUD_HOME/.config/direnv"
cat > "$CLOUD_HOME/.config/direnv/direnv.toml" <<EOF
[whitelist]
prefix = [ $prefix_toml ]

[global]
# use_pixi runs \`pixi install\` inside the .envrc, which on a cold cache takes far longer
# than direnv's 5s default and would otherwise warn on every load.
warn_timeout = "60s"
# direnv's man page recommends pinning bash when PATH is being mutated, which PATH_add
# does twice per pixi load.
bash_path = "/bin/bash"
EOF

echo "installed direnv directives to $LIB_DST"
ls -1 "$LIB_DST"

echo "direnv whitelist prefixes: $PREFIXES"
