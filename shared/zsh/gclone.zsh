gclone() {
  local owner=""
  if [[ "$1" == "--owner" ]]; then
    if [[ -z "$2" ]]; then
      echo "Usage: gclone [--owner <owner>] <repo>" >&2
      return 1
    fi
    owner="$2"
    shift 2
  fi
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: gclone [--owner <owner>] <repo>" >&2
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
    echo "Already cloned: $dir — cd'ing into it"
    cd "$target"
    return
  fi
  gh repo clone "$spec" "$target" || return 1
  cd "$target"
}
_gclone_complete() {
  local cache owner
  if [[ ${words[CURRENT-1]} == "--owner" ]]; then
    [[ -n ${words[CURRENT]} ]] && compadd -S ' ' -- "${words[CURRENT]}"
    return
  fi
  if [[ ${words[2]} == "--owner" ]]; then
    owner="${words[3]}"
  else
    owner="$(gh api user -q .login 2>/dev/null || echo '')"
  fi
  [[ -z "$owner" ]] && return
  cache=~/.cache/gh_repos_${owner}
  if [[ ! -f "$cache" ]] || [[ -n $(find "$cache" -mmin +60 2>/dev/null) ]]; then
    mkdir -p ~/.cache
    zle -R "Fetching repos for $owner..."
    local tmp
    if tmp="$(gh repo list "$owner" --limit 100 --json name -q '.[].name' 2>/dev/null)"; then
      echo "$tmp" > "$cache"
    fi
    zle -R ""
  fi
  [[ -f "$cache" ]] || return
  local -a repos
  repos=(${(f)"$(cat "$cache")"})
  compadd "${repos[@]}"
}
compdef _gclone_complete gclone
