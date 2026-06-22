use_branch-update() {
  # Reuse the installed branch-update implementation (portable shell, so it
  # sources fine in bash even though it lives among the zsh site-functions).
  local fn=/usr/local/share/zsh/site-functions/branch-update.zsh
  if [ ! -r "$fn" ]; then
    echo "use_branch-update: $fn not found — is wsl-cloud-init installed?" >&2
    return 0
  fi
  # shellcheck disable=SC1090
  . "$fn"
  # Best-effort: branch-update prints its own diagnostics (dirty tree, detached
  # HEAD, rebase conflict). Never fail the .envrc load over a sync hiccup, so
  # other directives (e.g. use fnm) still apply.
  branch-update || echo "use_branch-update: branch not updated (see above); continuing" >&2
  return 0
}
