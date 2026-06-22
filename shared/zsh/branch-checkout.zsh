branch-checkout() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: branch-checkout <branch>" >&2
    return 1
  fi
  local branch="$1"

  # Must be inside a git work tree.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "branch-checkout: not inside a git repository" >&2
    return 1
  fi

  # Abort on a dirty tree so checkout never carries changes onto another branch
  # (branch-update would refuse anyway; failing here avoids a half-done switch).
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "branch-checkout: uncommitted changes — commit or stash before switching" >&2
    return 1
  fi

  # Switch to the branch (git DWIM: local, else a remote-tracking branch).
  git checkout "$branch" || return 1

  # Bring it up to date with the default branch (reuses branch-update.zsh).
  branch-update
}
