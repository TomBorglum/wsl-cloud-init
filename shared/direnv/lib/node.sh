use_node() {
  if [ $# -ne 1 ]; then
    echo "Error: use_node requires exactly 1 argument: <version>" >&2
    return 1
  fi
  local version=$1
  eval "$(fnm env --shell bash)"
  fnm list | grep -q "v${version}" || fnm install "$version"
  fnm use "$version"
  local full_version
  full_version=$(fnm current)
  PATH_add "$HOME/.fnm/node-versions/${full_version}/installation/bin"
}
