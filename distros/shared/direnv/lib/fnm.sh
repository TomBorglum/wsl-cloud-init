#!/bin/bash
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
  PATH_add "$HOME/.fnm"
  local version_dir="$HOME/.fnm/node-versions/v${version}/installation/bin"
  if [ ! -d "$version_dir" ]; then
    if ! fnm list-remote | awk -v v="v${version}" '$1 == v {found=1} END {exit !found}'; then
      echo "Error: node v${version} is not a fully qualified release — use an exact version (e.g. 22.14.0)" >&2
      return 1
    fi
    fnm install "$version" || return 1
  fi
  PATH_add "$version_dir"
}
