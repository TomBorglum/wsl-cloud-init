use_sdk() {
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  if [ $# -ne 2 ]; then
    echo "Error: use_sdk requires exactly 2 arguments: <candidate> <version>" >&2
    return 1
  fi
  local candidate=$1
  local version=$2
  sdk install "$candidate" "$version" || return 1
  sdk use "$candidate" "$version"
}
