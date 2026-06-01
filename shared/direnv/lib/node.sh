use_node() {
  local version=$1
  if [ -n "$version" ]; then
    eval "$(fnm env --shell bash)"
    fnm list | grep -q "v${version}" || fnm install "$version"
    fnm use "$version"
    local full_version
    full_version=$(fnm current)
    PATH_add "$HOME/.fnm/node-versions/${full_version}/installation/bin"
  fi
}
