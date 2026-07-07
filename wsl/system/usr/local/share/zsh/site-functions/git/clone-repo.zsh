clone-repo() {
  local usage="Usage: clone-repo [--owner <owner>] <repo>"
  local owner=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) echo "$usage"; return 0 ;;
      --owner)
        if [[ -z "${2:-}" ]]; then echo "$usage" >&2; return 1; fi
        owner="$2"; shift 2 ;;
      --) shift; break ;;
      -*) echo "clone-repo: unknown option: $1" >&2; echo "$usage" >&2; return 1 ;;
      *) break ;;
    esac
  done
  if [[ $# -ne 1 || -z "$1" ]]; then
    echo "$usage" >&2
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
_clone-repo_complete() {
  local cache owner
  if [[ ${words[CURRENT-1]} == "--owner" ]]; then
    [[ -n ${words[CURRENT]} ]] && compadd -S ' ' -- "${words[CURRENT]}"
    return
  fi
  local cachekey
  local -a listargs
  local cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/clone-repo"
  if [[ ${words[2]} == "--owner" ]]; then
    # clone-repo --owner <owner> <repo> : repo is word 4
    (( CURRENT == 4 )) || return
    owner="${words[3]}"
    [[ -z "$owner" ]] && return
    cachekey="${(L)owner}"
    listargs=("$owner")
  else
    # clone-repo <repo> : repo is word 2. Resolve the gh login (cached to a file)
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
  # Enter interactive menu selection on the first Tab rather than dumping a static
  # columnar list. A static listing taller than the terminal scrolls the prompt
  # off-screen and becomes unusable; menu selection (enabled globally by oh-my-zsh's
  # `menu select`) instead scrolls the matches in place, keeping the prompt visible.
  compadd -- "${repos[@]}" && compstate[insert]=menu
}
compdef _clone-repo_complete clone-repo
