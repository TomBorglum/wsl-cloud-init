checkout-branch() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: checkout-branch <branch>" >&2
    return 1
  fi
  local branch="$1"

  # Must be inside a git work tree.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "checkout-branch: not inside a git repository" >&2
    return 1
  fi

  # Abort on a dirty tree so checkout never carries changes onto another branch
  # (update-branch would refuse anyway; failing here avoids a half-done switch).
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "checkout-branch: uncommitted changes — commit or stash before switching" >&2
    return 1
  fi

  # Switch to the branch (git DWIM: local, else a remote-tracking branch).
  git checkout "$branch" || return 1

  # Bring it up to date with the default branch (reuses update-branch.zsh).
  update-branch
}
_checkout-branch_complete() {
  # Only complete the single branch argument.
  (( CURRENT == 2 )) || return
  local -a refs
  # Local branches keep their short name (strip refs/heads/); remote branches
  # drop the remote too (strip refs/remotes/origin/) to match git checkout's
  # DWIM, which checks out the bare name.
  refs=(
    ${(f)"$(git for-each-ref --format='%(refname:strip=2)' refs/heads 2>/dev/null)"}
    ${(f)"$(git for-each-ref --format='%(refname:strip=3)' refs/remotes 2>/dev/null)"}
  )
  # Drop the remote's symbolic HEAD pointer and de-duplicate.
  refs=(${refs:#HEAD})
  compadd -- ${(u)refs}
}
compdef _checkout-branch_complete checkout-branch
