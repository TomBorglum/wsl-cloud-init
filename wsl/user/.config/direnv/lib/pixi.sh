#!/bin/bash
use_pixi() {
  local pixi_bin="$HOME/.pixi/bin/pixi"
  if [[ ! -x "$pixi_bin" ]]; then
    echo "Error: pixi is not installed" >&2
    return 1
  fi
  if [[ ! -f pixi.toml ]]; then
    local project_name template tpl_dir tpl_file
    project_name="$(basename "$PWD")"
    # `use pixi python` scaffolds from a named template; bare `use pixi` stays minimal.
    # pixi is polyglot, so the language lives in the template name, not this directive.
    template="${1:-}"
    tpl_dir="$HOME/.config/pixi/templates"
    if [[ -n "$template" ]]; then
      # A named template that doesn't exist is a typo to surface, not something to
      # paper over with a minimal manifest: error out before creating pixi.toml or
      # installing, mirroring the pixi-not-installed guard above.
      tpl_file="$tpl_dir/$template.toml"
      if [[ ! -f "$tpl_file" ]]; then
        echo "use_pixi: no '$template' template found in $tpl_dir" >&2
        return 1
      fi
      # @PROJECT_NAME@ is the only placeholder; substitute the project dir name.
      sed "s/@PROJECT_NAME@/$project_name/g" "$tpl_file" > pixi.toml
      echo "direnv: created pixi.toml from '$template' template — remember to commit it to git" >&2
    else
      # Bare `use pixi`: minimal starter manifest.
      cat > pixi.toml <<EOF
[workspace]
name = "$project_name"
channels = ["conda-forge"]
platforms = ["linux-64"]
EOF
      echo "direnv: created minimal pixi.toml — remember to commit it to git" >&2
    fi
  fi
  # Re-run this directive whenever the manifest changes, so editing dependencies
  # re-triggers `pixi install` — no manual `watch_file pixi.toml` in the .envrc.
  # Idempotent: harmless if the .envrc still lists it explicitly.
  watch_file pixi.toml
  PATH_add "$HOME/.pixi/bin"
  "$pixi_bin" install --quiet || return 1
  local env_bin
  env_bin="$(pwd)/.pixi/envs/default/bin"
  PATH_add "$env_bin"
}
