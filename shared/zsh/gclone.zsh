gclone() {
  if [[ -z "$1" ]]; then
    echo "Usage: gclone <owner/repo>" >&2
    return 1
  fi
  local repo="$1"
  local dir
  dir="$(basename "$repo" .git)"
  local target=~/projects/$dir
  mkdir -p ~/projects
  if [[ -d "$target" ]]; then
    echo "Already cloned: $dir — cd'ing into it"
    cd "$target"
    return
  fi
  gh repo clone "$repo" "$target" || return 1
  cd "$target"
}
_gclone_complete() {
  local cache owner
  if [[ ${words[2]} == */* ]]; then
    owner="${words[2]%%/*}"
  elif [[ -n ${words[2]} ]]; then
    owner="${words[2]}"
  else
    owner="$(gh api user -q .login 2>/dev/null || echo '')"
    [[ -z "$owner" ]] && return
  fi
  cache=~/.cache/gh_repos_${owner}
  if [[ ! -f "$cache" ]] || [[ -n $(find "$cache" -mmin +60 2>/dev/null) ]]; then
    mkdir -p ~/.cache
    zle -R "Fetching repos for $owner..."
    local tmp
    if tmp="$(gh repo list "$owner" --limit 100 --json nameWithOwner -q '.[].nameWithOwner' 2>/dev/null)"; then
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
