use_update-branch() {
  # Reuse the installed update-branch implementation (portable shell, so it
  # sources fine in bash even though it lives among the zsh site-functions).
  local fn=/usr/local/share/zsh/site-functions/update-branch.zsh
  if [ ! -r "$fn" ]; then
    echo "use_update-branch: $fn not found — is wsl-cloud-init installed?" >&2
    return 0
  fi
  # Reload this .envrc on a branch switch so the update fires exactly once per
  # switch. HEAD's content changes on checkout but not on rebase (the symref
  # still reads "ref: refs/heads/<branch>"), so this does not loop.
  local headfile
  headfile="$(git rev-parse --git-path HEAD 2>/dev/null)"
  [ -n "$headfile" ] && [ -f "$headfile" ] && watch_file "$headfile"

  # Snapshot .envrc before the update. update-branch's rebase replays commits and
  # rewrites the working tree — bumping .envrc's mtime — which would otherwise
  # make direnv reload and update a second time. We restore the mtime afterward
  # iff .envrc's content is unchanged (if the rebase really changed .envrc, the
  # hash differs and we let direnv reload to apply it).
  local before_mtime before_sha after_sha
  before_mtime="$(stat -c %Y .envrc 2>/dev/null)"
  before_sha="$(git hash-object .envrc 2>/dev/null)"

  # shellcheck disable=SC1090
  . "$fn"
  # Best-effort: update-branch prints its own diagnostics (dirty tree, detached
  # HEAD, rebase conflict). Never fail the .envrc load over a sync hiccup, so
  # other directives (e.g. use fnm) still apply.
  update-branch || echo "use_update-branch: branch not updated (see above); continuing" >&2

  after_sha="$(git hash-object .envrc 2>/dev/null)"
  if [ -n "$before_mtime" ] && [ "$before_sha" = "$after_sha" ]; then
    touch -d "@$before_mtime" .envrc 2>/dev/null
  fi
  return 0
}
