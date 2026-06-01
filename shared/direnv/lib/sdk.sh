use_sdk() {
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  while [ $# -gt 0 ]; do
    local candidate=$1
    local version=$2
    sdk install "$candidate" "$version" 2>/dev/null
    sdk use "$candidate" "$version"
    shift 2
  done
}
