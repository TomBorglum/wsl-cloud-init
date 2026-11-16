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
  # SDKMAN's own convention is <CANDIDATE>_HOME (JAVA_HOME, MAVEN_HOME, ...), derived rather
  # than hardcoded, and pinned here to the project's version instead of the global default. A
  # plain `export` is tracked by direnv and restored on leaving, unlike `sdk use`, which
  # mutates the live shell.
  export "${candidate^^}_HOME=$candidate_dir"
}
