#!/bin/bash
use_sdk() {
  if [[ $# -ne 2 ]]; then
    echo "Error: use_sdk requires exactly 2 arguments: <candidate> <version>" >&2
    return 1
  fi
  local candidate=$1
  local version=$2
  local candidate_dir="$HOME/.sdkman/candidates/$candidate/$version"

  if [[ ! -d "$candidate_dir" ]]; then
    (source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install "$candidate" "$version") || return 1
  fi

  PATH_add "$candidate_dir/bin"
}
