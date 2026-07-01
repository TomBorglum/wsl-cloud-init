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
  # Mirror SDKMAN, which exports <CANDIDATE>_HOME (JAVA_HOME, MAVEN_HOME, …) for the
  # selected version. Derive the name from the candidate (SDKMAN's convention)
  # instead of hardcoding it, pinned to this project's version rather than the global
  # default. A plain `export` is tracked by direnv and restored to its prior value
  # when the directory is left (unlike `sdk use`, which mutates the live shell).
  export "${candidate^^}_HOME=$candidate_dir"
}
