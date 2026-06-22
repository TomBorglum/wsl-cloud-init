gcreate() {
  local owner=""
  if [[ "$1" == "--owner" ]]; then
    if [[ -z "$2" ]]; then
      echo "Usage: gcreate [--owner <owner>] <repo>" >&2
      return 1
    fi
    owner="$2"
    shift 2
  fi
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: gcreate [--owner <owner>] <repo>" >&2
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
