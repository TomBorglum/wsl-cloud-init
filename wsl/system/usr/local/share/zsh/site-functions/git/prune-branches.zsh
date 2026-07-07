prune-branches() {
  local usage="Usage: prune-branches [-y|--yes]"
  local help="$usage

Delete local branches whose upstream branch is gone (merged and auto-deleted, or
deleted). Branches that were never pushed, or that still track a live upstream, are
kept, and the branch you're on is never touched. Each deletion prints the tip SHA so
it can be restored with 'git branch <name> <sha>'.

Asks before each deletion:
  y          delete this branch
  n / Enter  keep it (default)
  a          delete this and all remaining without asking
  q          stop
  -y, --yes  delete all candidates without prompting"
  local assume_yes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) echo "$help"; return 0 ;;
      -y|--yes) assume_yes=true; shift ;;
      --) shift; break ;;
      -*) echo "prune-branches: unknown option: $1" >&2; echo "$usage" >&2; return 1 ;;
      *) break ;;
    esac
  done

  # Must be inside a git work tree.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "prune-branches: not inside a git repository" >&2
    return 1
  fi

  # Current branch (never deleted — you can't -D the checked-out branch); empty on
  # detached HEAD, which is fine.
  local current
  current="$(git symbolic-ref --quiet --short HEAD)"

  # Refresh which branches are [gone] and drop stale origin/* refs. Passing --prune
  # explicitly keeps this correct whether or not the user's git enables fetch.prune,
  # so the function never relies on a particular config. -q keeps success quiet.
  git fetch --prune -q origin || return 1

  # Gather candidates before prompting: the prompt can't live inside this read loop,
  # since the loop's stdin is the for-each-ref stream (a `read` there would consume a
  # branch line, not the keystroke). Each entry is "name<TAB>short-sha".
  # Classify in one pass: name, upstream ref (empty when the branch tracks nothing),
  # and the track marker ([gone] once the upstream is deleted); tab-separated (%09).
  local -a gone=()
  local name upstream track
  while IFS=$'\t' read -r name upstream track; do
    [[ "$name" == "$current" ]] && continue
    # Keep a branch that tracks nothing (pure-local work, never pushed) — the one thing
    # worth protecting is commits that never left this machine.
    [[ -z "$upstream" ]] && continue
    # Keep a branch that still has a live upstream (work in progress).
    [[ "$track" != "[gone]" ]] && continue
    gone+=("$name"$'\t'"$(git rev-parse --short "$name")")
  done < <(git for-each-ref --format='%(refname:short)%09%(upstream)%09%(upstream:track)' refs/heads)

  if [[ ${#gone[@]} -eq 0 ]]; then
    echo "prune-branches: nothing to prune"
    return 0
  fi

  # Without -y we need an interactive terminal to ask. In a pipe/script, list the
  # candidates and delete nothing rather than blocking or reading EOF as an answer.
  local entry was
  if ! $assume_yes && [[ ! -t 0 ]]; then
    echo "prune-branches: gone branches (re-run interactively, or with -y, to delete):" >&2
    for entry in "${gone[@]}"; do
      echo "  ${entry%%$'\t'*} (was ${entry#*$'\t'})" >&2
    done
    return 0
  fi

  # Delete, prompting per branch. 'a' switches to delete-all; 'q' stops; anything else
  # (incl. Enter) keeps the branch. -D (force) is required: a squash-merged branch isn't
  # an ancestor of the default branch, so -d would refuse. The printed SHA is the
  # recovery handle — git branch <name> <sha> brings it back until gc.
  local -a deleted=()
  local assume_all=$assume_yes ans
  for entry in "${gone[@]}"; do
    name="${entry%%$'\t'*}"
    was="${entry#*$'\t'}"
    if ! $assume_all; then
      read -k 1 "ans?Delete $name (was $was)? [y/N/a/q] "
      echo
      case "$ans" in
        y|Y) ;;
        a|A) assume_all=true ;;
        q|Q) break ;;
        *) continue ;;
      esac
    fi
    if git branch -D "$name" >/dev/null 2>&1; then
      echo "Deleted $name (was $was)"
      deleted+=("$name")
    fi
  done

  if [[ ${#deleted[@]} -eq 0 ]]; then
    echo "prune-branches: nothing pruned"
    return 0
  fi
  echo "Pruned ${#deleted[@]} branch(es)"
}
