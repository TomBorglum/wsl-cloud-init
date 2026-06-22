repo-clone() {
  local owner=""
  if [[ "$1" == "--owner" ]]; then
    if [[ -z "$2" ]]; then
      echo "Usage: repo-clone [--owner <owner>] <repo>" >&2
      return 1
    fi
    owner="$2"
    shift 2
  fi
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "Usage: repo-clone [--owner <owner>] <repo>" >&2
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
_repo-clone_complete() {
  local cache owner
  if [[ ${words[CURRENT-1]} == "--owner" ]]; then
    [[ -n ${words[CURRENT]} ]] && compadd -S ' ' -- "${words[CURRENT]}"
    return
  fi
  local cachekey
  local -a listargs
  local cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/repo-clone"
  if [[ ${words[2]} == "--owner" ]]; then
    # repo-clone --owner <owner> <repo> : repo is word 4
    (( CURRENT == 4 )) || return
    owner="${words[3]}"
    [[ -z "$owner" ]] && return
    cachekey="${(L)owner}"
    listargs=("$owner")
  else
    # repo-clone <repo> : repo is word 2. Resolve the gh login (cached to a file)
    # so this shares a cache with an explicit --owner <self>.
    (( CURRENT == 2 )) || return
    local logincache="$cachedir/login"
    if [[ ! -s "$logincache" ]] || [[ -n $(find "$logincache" -mmin +60 2>/dev/null) ]]; then
      mkdir -p "$cachedir"
      local login
      if login="$(gh api user -q .login 2>/dev/null)" && [[ -n "$login" ]]; then
        print -r -- "$login" >| "$logincache"
      fi
    fi
    [[ -s "$logincache" ]] && owner="$(<"$logincache")"
    [[ -z "$owner" ]] && return
    cachekey="${(L)owner}"
    listargs=()
  fi
  cache="$cachedir/repos_${cachekey}"
  if [[ ! -f "$cache" ]] || [[ -n $(find "$cache" -mmin +60 2>/dev/null) ]]; then
    mkdir -p "$cachedir"
    zle -R "Fetching repos for ${owner:-your account}..."
    local tmp
    if tmp="$(gh repo list "${listargs[@]}" --limit 100 --json name -q '.[].name' 2>/dev/null)"; then
      echo "$tmp" > "$cache"
    fi
    zle -R ""
  fi
  [[ -f "$cache" ]] || return
  local -a repos
  repos=(${(f)"$(cat "$cache")"})
  compadd "${repos[@]}"
}
compdef _repo-clone_complete repo-clone
