update-branch() {
  case "${1:-}" in
    -h|--help)
      echo "Usage: update-branch  (rebase the current branch onto the remote default)"
      return 0 ;;
  esac
  # Reuse the same implementation direnv runs via 'use update-branch'. Source it
  # in a subshell so the sourced _update-branch/use_update-branch definitions
  # don't leak into the interactive namespace; the rebase mutates on-disk git
  # state, so it persists regardless. The subshell's status is the return code.
  local lib="$HOME/.config/direnv/lib/update-branch.sh"
  if [[ ! -r "$lib" ]]; then
    echo "update-branch: implementation not found at $lib" >&2
    return 1
  fi
  ( source "$lib" && _update-branch )
}
