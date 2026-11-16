rebase-branch() {
  case "${1:-}" in
    -h|--help)
      echo "Usage: rebase-branch  (rebase the current branch onto the remote default)"
      return 0 ;;
  esac

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "rebase-branch: not inside a git repository" >&2
    return 1
  fi

  # Asked of the remote rather than read from the local origin/HEAD symref, which is cached at
  # clone time and goes stale when the default branch changes upstream. Needs connectivity.
  local base
  base="$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's@^ref: refs/heads/\(.*\)\tHEAD$@\1@p')"
  if [[ -z "$base" ]]; then
    echo "rebase-branch: could not determine the remote's default branch — is origin reachable?" >&2
    return 1
  fi

  local branch
  if ! branch="$(git symbolic-ref --quiet --short HEAD)"; then
    echo "rebase-branch: detached HEAD — check out a branch first" >&2
    return 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "rebase-branch: uncommitted changes — commit or stash before updating" >&2
    return 1
  fi

  git fetch -q origin "$base" || return 1

  if ! git rebase -q "origin/$base"; then
    echo "rebase-branch: rebase hit conflicts — resolve them, then run 'git rebase --continue' (or 'git rebase --abort')." >&2
    return 1
  fi

  echo "Updated $branch onto origin/$base"
}
