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
  # Mirror SDKMAN, which exports JAVA_HOME for the selected java. Pin it to this
  # project's version (like `sdk use java <version>`) rather than leaving it on the
  # global default. direnv tracks this export and restores the prior value when the
  # directory is left. SDKMAN sets no *_HOME for maven/gradle/etc., so neither do we.
  [[ "$candidate" == "java" ]] && export JAVA_HOME="$candidate_dir"
}
