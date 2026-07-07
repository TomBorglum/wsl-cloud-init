rebase-branch() {
  case "${1:-}" in
    -h|--help)
      echo "Usage: rebase-branch  (rebase the current branch onto the remote default)"
      return 0 ;;
  esac

  # Must be inside a git work tree.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "rebase-branch: not inside a git repository" >&2
    return 1
  fi

  # Base branch: ask the remote for its current default branch rather than
  # trusting the local origin/HEAD symref, which is cached at clone time and
  # goes stale if the default branch is changed upstream. Needs connectivity.
  local base
  base="$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's@^ref: refs/heads/\(.*\)\tHEAD$@\1@p')"
  if [[ -z "$base" ]]; then
    echo "rebase-branch: could not determine the remote's default branch — is origin reachable?" >&2
    return 1
  fi

  # Resolve the current branch; refuse on detached HEAD.
  local branch
  if ! branch="$(git symbolic-ref --quiet --short HEAD)"; then
    echo "rebase-branch: detached HEAD — check out a branch first" >&2
    return 1
  fi

  # Abort if the working tree has uncommitted changes.
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "rebase-branch: uncommitted changes — commit or stash before updating" >&2
    return 1
  fi

  # Fetch the latest base from origin, then rebase the branch onto it. Pass -q to
  # both so the success path stays quiet (no fetch summary, no "up to date" line);
  # the single "Updated ..." line below is the only success output. Errors and
  # rebase conflicts still report normally.
  git fetch -q origin "$base" || return 1

  if ! git rebase -q "origin/$base"; then
    echo "rebase-branch: rebase hit conflicts — resolve them, then run 'git rebase --continue' (or 'git rebase --abort')." >&2
    return 1
  fi

  echo "Updated $branch onto origin/$base"
}
