repo-create() {
  local owner=""
  if [[ "$1" == "--owner" ]]; then
    if [[ -z "$2" ]]; then
      echo "Usage: repo-create [--owner <owner>] <repo>" >&2
      return 1
    fi
    owner="$2"
    shift 2
  fi
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: repo-create [--owner <owner>] <repo>" >&2
    return 1
  fi
  local repo="$1"
  local spec="$repo"
  [[ -n "$owner" ]] && spec="$owner/$repo"
  local dir
  dir="$(basename "$repo" .git)"
  local target=~/projects/$dir
  mkdir -p ~/projects
  if [[ -d "$target" ]]; then
    # Only reuse the existing checkout if its owner matches the requested one
    # (the --owner value, or the logged-in user by default).
    local expected="$owner"
    [[ -z "$expected" ]] && expected="$(gh api user -q .login 2>/dev/null)"
    local url actual
    url="$(git -C "$target" remote get-url origin 2>/dev/null)"
    url="${url%.git}"
    actual="${url%/*}"
    actual="${actual##*[:/]}"
    if [[ -z "$actual" || "${(L)actual}" != "${(L)expected}" ]]; then
      echo "repo-create: ~/projects/$dir is already checked out for owner '${actual:-unknown}', not '$expected' — cannot reuse it." >&2
      return 1
    fi
    echo "Already exists: $dir — cd'ing into it"
    cd "$target"
    return
  fi
  cd ~/projects
  gh repo create "$spec" --private --clone >/dev/null || return 1
  cd "$target"
  echo "# $dir" > README.md
  git add README.md
  git commit -q -m "Initial commit"
  git push -qu origin main
  echo "Created $dir at $(git remote get-url origin)"
}
