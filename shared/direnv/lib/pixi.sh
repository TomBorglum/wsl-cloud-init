use_pixi() {
  local pixi_bin="$HOME/.pixi/bin/pixi"

  if [ ! -x "$pixi_bin" ]; then
    echo "Error: pixi is not installed" >&2
    return 1
  fi

  if [ ! -f pixi.toml ]; then
    cat > pixi.toml <<EOF
[workspace]
name = "$(basename $PWD)"
channels = ["conda-forge"]
platforms = ["linux-64"]
EOF
    echo "direnv: created minimal pixi.toml — remember to commit it to git" >&2
  fi

  PATH_add "$HOME/.pixi/bin"

  "$pixi_bin" install --quiet

  local env_bin
  env_bin="$(pwd)/.pixi/envs/default/bin"

  PATH_add "$env_bin"

  eval "$("$pixi_bin" shell-hook --shell bash | grep -v '^export PATH')"
}
