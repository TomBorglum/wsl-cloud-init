use_fnm() {
  if [ $# -ne 2 ]; then
    echo "Error: use_fnm requires exactly 2 arguments: <tool> <version>" >&2
    return 1
  fi
  local tool=$1
  local version=$2
  if [ "$tool" != "node" ]; then
    echo "Error: use_fnm only supports the 'node' tool (got '$tool')" >&2
    return 1
  fi
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: node version must be fully qualified (e.g. 22.14.0), got '$version'" >&2
    return 1
  fi
  PATH_add "$HOME/.fnm"
  local version_dir="$HOME/.fnm/node-versions/v${version}/installation/bin"
  if [ ! -d "$version_dir" ]; then
    fnm install "$version" || return 1
  fi
  PATH_add "$version_dir"
}
