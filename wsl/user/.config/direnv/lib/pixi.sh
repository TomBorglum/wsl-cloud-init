#!/bin/bash
use_pixi() {
  # pixi installs itself on first use rather than at provision time, so this
  # directive does not depend on the instance having been provisioned with it.
  # PIXI_HOME pins the location (binary at $PIXI_HOME/bin/pixi) and drives the
  # guard and PATH below; the value stays ~/.pixi, which is also pixi's own default.
  local pixi_home="$HOME/.pixi"
  local pixi_bin="$pixi_home/bin/pixi"
  if [[ ! -x "$pixi_bin" ]]; then
    # Say so before the download: it is the one moment `direnv allow` visibly
    # stalls, and direnv's own warn_timeout (5s) fires during it.
    echo "direnv: pixi is not installed — installing it now" >&2
    # The same fetch as the CI directive in actions/setup-direnv/lib/pixi.sh.
    # --proto '=https' --tlsv1.2 pins the transfer to HTTPS/TLS 1.2+ (no plaintext
    # redirects); PIXI_NO_PATH_UPDATE=1 stops the installer editing shell rc files,
    # since this directive owns PATH via PATH_add below.
    curl -fsSL --proto '=https' --tlsv1.2 https://pixi.sh/install.sh \
      | PIXI_HOME="$pixi_home" PIXI_NO_PATH_UPDATE=1 bash || return 1
    # The installer's exit code is the only other signal, so confirm what it
    # actually produced. Guarding on the binary rather than the directory (which is
    # what the CI copy tests) also means a half-finished install retries here
    # instead of wedging every later load.
    if [[ ! -x "$pixi_bin" ]]; then
      echo "use_pixi: pixi install did not produce $pixi_bin" >&2
      return 1
    fi
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
      # installing, mirroring the install guard above.
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
  PATH_add "$pixi_home/bin"
  "$pixi_bin" install --quiet || return 1
  local env_bin
  env_bin="$(pwd)/.pixi/envs/default/bin"
  PATH_add "$env_bin"
}
