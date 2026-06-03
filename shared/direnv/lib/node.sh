use_node() {
  if [ $# -ne 1 ]; then
    echo "Error: use_node requires exactly 1 argument: <version>" >&2
    return 1
  fi
  local version=$1
  fnm install "$version"
  local full_version
  full_version=$(fnm list | awk -v v="v${version}" '$2 == v {print $2; exit}')
  if [ -z "$full_version" ]; then
    echo "Error: node v${version} not found after install — only fully qualified versions are permitted (e.g. 22.14.0)" >&2
    return 1
  fi
  PATH_add "$HOME/.fnm/node-versions/${full_version}/installation/bin"
}
