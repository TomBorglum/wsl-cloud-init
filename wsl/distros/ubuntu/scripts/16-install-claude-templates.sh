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
# Separate from 07-install-claude-code.sh, which exits 3 as soon as it finds claude
# installed and so cannot be relied on to reach this payload. This script is the only
# installer of the templates and re-installs the current set every run (install
# overwrites), independent of that guard.
#
# What the re-install is for is repair: restoring the template after it has been deleted
# or edited in $HOME, which an opt-in re-run does without re-provisioning. That is the one
# thing the split buys, and it is worth buying -- use_claude_env errors without a template.
#
# What it does NOT do is carry a template change onto a provisioned instance. Moving /opt
# to a newer commit aborts the whole run at 01-install-release-info.sh, because in-place
# upgrades are not supported (README.md, "In-place upgrades are not supported"), so every
# run that reaches this script copies from the commit the instance was provisioned from.
# A changed template arrives by re-provisioning, like every other change. Do not reason
# from the old claim that a split script delivers updates - it cannot, here or for any
# other per-user payload.
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
