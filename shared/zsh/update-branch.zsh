update-branch() {
  # Must be inside a git work tree.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "update-branch: not inside a git repository" >&2
    return 1
  fi

  # Base branch: explicit arg, otherwise the remote's default branch.
  # origin/HEAD resolves to e.g. origin/main; strip the remote prefix.
  local base="$1"
  if [[ -z "$base" ]]; then
    base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    base="${base#origin/}"
    if [[ -z "$base" ]]; then
      echo "update-branch: could not determine the default branch — pass it explicitly, e.g. 'update-branch main', or run 'git remote set-head origin -a'." >&2
      return 1
    fi
  fi

  # Resolve the current branch; refuse on detached HEAD.
  local branch
  if ! branch="$(git symbolic-ref --quiet --short HEAD)"; then
    echo "update-branch: detached HEAD — check out a branch first" >&2
    return 1
  fi

  # Abort if the working tree has uncommitted changes.
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "update-branch: uncommitted changes — commit or stash before updating" >&2
    return 1
  fi

  # Fetch the latest base from origin, then rebase the branch onto it.
  echo "Fetching origin/$base..."
  git fetch origin "$base" || return 1

  if ! git rebase "origin/$base"; then
    echo "update-branch: rebase hit conflicts — resolve them, then run 'git rebase --continue' (or 'git rebase --abort')." >&2
    return 1
  fi

  echo "Updated $branch onto origin/$base"
}
