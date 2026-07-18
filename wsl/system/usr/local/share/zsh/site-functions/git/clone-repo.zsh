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
# Path to the shared per-user cache library. Sourced only inside subshells (see
# _clone-repo_cache) so its wsl_cache_* helpers never leak into the interactive shell.
_clone_repo_cachelib=/usr/local/lib/wsl-cloud-init/wsl-cache.sh
# Run a wsl_cache_* function in an isolated subshell so its helpers stay out of the
# interactive shell. Cache reads echo to stdout; writes persist to disk regardless.
_clone-repo_cache() { ( source "$_clone_repo_cachelib" || return; "$@" ) }

_clone-repo_complete() {
  # The completion is inert without the shared cache library (e.g. a dev shell).
  [[ -r $_clone_repo_cachelib ]] || return
  local owner age
  if [[ ${words[CURRENT-1]} == "--owner" ]]; then
    [[ -n ${words[CURRENT]} ]] && compadd -S ' ' -- "${words[CURRENT]}"
    return
  fi
  local cachekey
  local -a listargs
  if [[ ${words[2]} == "--owner" ]]; then
    # clone-repo --owner <owner> <repo> : repo is word 4
    (( CURRENT == 4 )) || return
    owner="${words[3]}"
    [[ -z "$owner" ]] && return
    cachekey="${(L)owner}"
    listargs=("$owner")
  else
    # clone-repo <repo> : repo is word 2. Resolve the gh login (cached) so this
    # shares a cache with an explicit --owner <self>.
    (( CURRENT == 2 )) || return
    age="$(_clone-repo_cache wsl_cache_age login clone-repo)"
    if [[ -z "$age" || "$age" -gt 3600 ]]; then
      local login
      if login="$(gh api user -q .login 2>/dev/null)" && [[ -n "$login" ]]; then
        _clone-repo_cache wsl_cache_set "$(id -un)" login clone-repo "$login"
      fi
    fi
    owner="$(_clone-repo_cache wsl_cache_get login clone-repo)"
    [[ -z "$owner" ]] && return
    cachekey="${(L)owner}"
    listargs=()
  fi
  local cache=repo_${cachekey}
  age="$(_clone-repo_cache wsl_cache_age "$cache" clone-repo)"
  if [[ -z "$age" || "$age" -gt 3600 ]]; then
    zle -R "Fetching repos for ${owner:-your account}..."
    local tmp
    if tmp="$(gh repo list "${listargs[@]}" --limit 100 --json name -q '.[].name' 2>/dev/null)" \
       && [[ -n "$tmp" ]]; then
      _clone-repo_cache wsl_cache_set "$(id -un)" "$cache" clone-repo "$tmp"
    fi
    zle -R ""
  fi
  local repolist
  repolist="$(_clone-repo_cache wsl_cache_get "$cache" clone-repo)"
  [[ -n "$repolist" ]] || return
  local -a repos
  repos=(${(f)repolist})
  # Enter interactive menu selection on the first Tab rather than dumping a static
  # columnar list. A static listing taller than the terminal scrolls the prompt
  # off-screen and becomes unusable; menu selection (enabled globally by oh-my-zsh's
  # `menu select`) instead scrolls the matches in place, keeping the prompt visible.
  compadd -- "${repos[@]}" && compstate[insert]=menu
}
compdef _clone-repo_complete clone-repo
