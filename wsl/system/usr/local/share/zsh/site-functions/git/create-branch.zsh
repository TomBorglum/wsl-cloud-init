create-branch() {
  local usage="Usage: create-branch <branch>"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) echo "$usage"; return 0 ;;
      --) shift; break ;;
      -*) echo "create-branch: unknown option: $1" >&2; echo "$usage" >&2; return 1 ;;
      *) break ;;
    esac
  done
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "$usage" >&2
    return 1
  fi
  local branch="$1"

  # Must be inside a git work tree.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "create-branch: not inside a git repository" >&2
    return 1
  fi

  # Determine existence on both sides. gh's {owner}/{repo} placeholders resolve
  # from the current repo's remote.
  local local_exists=false remote_exists=false
  git show-ref --verify --quiet "refs/heads/$branch" && local_exists=true
  gh api "repos/{owner}/{repo}/git/ref/heads/$branch" >/dev/null 2>&1 && remote_exists=true

  # A local-only branch would otherwise get a divergent remote ref created off
  # the default branch — refuse and let the user push or remove it themselves.
  if $local_exists && ! $remote_exists; then
    echo "create-branch: local branch '$branch' already exists but is not on origin — push it with 'git push -u origin $branch' or remove it first" >&2
    return 1
  fi

  # Create the ref on origin first, then check it out locally with tracking, so a
  # plain 'git push' just works (no -u needed).
  if $remote_exists; then
    # Already on origin — skip creation and just check it out.
    echo "Already exists: $branch — checking it out"
  else
    # Base the new branch on the repo's current default branch.
    local default sha
    default="$(gh api repos/{owner}/{repo} -q .default_branch 2>/dev/null)"
    if [[ -z "$default" ]]; then
      echo "create-branch: could not determine the repo's default branch — is origin reachable?" >&2
      return 1
    fi
    sha="$(gh api "repos/{owner}/{repo}/git/ref/heads/$default" -q .object.sha 2>/dev/null)"
    if [[ -z "$sha" ]]; then
      echo "create-branch: could not resolve the tip of '$default'" >&2
      return 1
    fi
    gh api "repos/{owner}/{repo}/git/refs" -f ref="refs/heads/$branch" -f sha="$sha" >/dev/null || return 1
    echo "Created $branch off $default (tracking origin/$branch)"
  fi

  # Bring it down and check out with tracking, then navigate to the repo root.
  git fetch -q origin "$branch" || return 1
  if $local_exists; then
    git switch -q "$branch" || return 1
  else
    git switch -qc "$branch" --track "origin/$branch" || return 1
  fi
  cd "$(git rev-parse --show-toplevel)"
}
