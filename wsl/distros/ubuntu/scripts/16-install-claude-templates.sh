#!/bin/bash
set -euo pipefail
shopt -s nullglob

: "${TARGET_USER:?TARGET_USER is required}"

# Claude Code config templates (per-user), sourced from the sparse checkout declared in
# user-data.template. The `use claude_env` direnv directive merges
# ~/.config/claude/templates/settings.json into a repository's .claude/settings.json.
#
# Gated on INSTALL_CLAUDE_CODE to match 13-install-direnv-functions.sh, which installs the
# claude/ directives behind the same flag: the template is useless without use_claude_env,
# and use_claude_env errors without the template.
#
# Separate from 07-install-claude-code.sh on purpose. That script exits 3 as soon as it
# finds claude already installed, so an existing instance re-running install.sh would
# never pick up a template change. This one re-installs the current set every run
# (install overwrites), which is how an updated template reaches a provisioned instance.
if [[ "${INSTALL_CLAUDE_CODE:-}" != "true" ]]; then
  echo "INSTALL_CLAUDE_CODE not set, skipping claude template install"
  exit 4  # not selected; see install.sh
fi

sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/claude/templates"

src=/opt/wsl-cloud-init/wsl/user/.config/claude/templates
files=("$src"/*.json)
if [[ ${#files[@]} -gt 0 ]]; then
  install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "${files[@]}" "/home/$TARGET_USER/.config/claude/templates/"
fi
