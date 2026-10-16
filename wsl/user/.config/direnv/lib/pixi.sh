#!/bin/bash
use_pixi() {
  # Usage: use pixi <version> [template]
  #
  # pixi installs itself on first use rather than at provision time, so this directive does
  # not depend on the instance having been provisioned with it. Each pinned version lives in
  # its own directory under $PIXI_HOME/versions and $PIXI_HOME/bin/pixi is a symlink into
  # that store, the way SDKMAN and fnm keep theirs: switching back to a version already on
  # disk is instant and offline, and nothing is ever uninstalled (reclaim one with
  # `rm -rf ~/.pixi/versions/<version>`). PIXI_HOME stays ~/.pixi, which is also pixi's own
  # default, because pixi-completion.zsh evaluates $HOME/.pixi/bin/pixi by absolute path.
  local version="${1:-}" template="${2:-}"
  # Exact version only, as use_fnm requires of node: a partial pin is the drift this
  # directive exists to stop.
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "use_pixi: a fully qualified pixi version is required: use pixi <version> [template]" >&2
    return 1
  fi
  local pixi_home="$HOME/.pixi"
  local version_dir="$pixi_home/versions/$version/bin"
  local version_bin="$version_dir/pixi"
  # Guard on the version the binary reports, not merely on its presence: `pixi self-update`
  # run inside an active context rewrites it in place, and an existence check would then let
  # the wrong version survive every later load. Nothing here tries to police what happens
  # inside a context - this is what makes the next `direnv allow` put the pin back. It costs
  # one exec, against a body that already runs `pixi install`.
  if [[ "$("$version_bin" --version 2>/dev/null)" != "pixi $version" ]]; then
    # Say so before the download: it is the one moment `direnv allow` visibly stalls, and
    # direnv's own warn_timeout (5s) fires during it.
    echo "direnv: pixi $version is not installed — installing it now" >&2
    rm -rf "$pixi_home/versions/$version"
    # PIXI_VERSION takes a bare X.Y.Z (the installer normalises it to v${VERSION#v}).
    # PIXI_BIN_DIR puts the binary in the store rather than $PIXI_HOME/bin, and the installer
    # creates it. PIXI_NO_PATH_UPDATE=1 stops the installer editing shell rc files, since this
    # directive owns PATH via PATH_add below. --proto '=https' --tlsv1.2 pins the transfer to
    # HTTPS/TLS 1.2+ (no plaintext redirects).
    curl -fsSL --proto '=https' --tlsv1.2 https://pixi.sh/install.sh \
      | PIXI_VERSION="$version" PIXI_HOME="$pixi_home" \
        PIXI_BIN_DIR="$version_dir" PIXI_NO_PATH_UPDATE=1 bash || return 1
    # The installer's exit code is the only other signal, so confirm what it actually
    # produced. Removing a mismatched entry rather than leaving it means a half-finished
    # install retries here instead of wedging every later load.
    if [[ "$("$version_bin" --version 2>/dev/null)" != "pixi $version" ]]; then
      echo "use_pixi: could not install pixi $version to $version_bin" >&2
      rm -rf "$pixi_home/versions/$version"
      return 1
    fi
  fi
  # $PIXI_HOME/bin/pixi follows the version this context pins: it is what
  # pixi-completion.zsh evaluates, by absolute path, before any PATH_add has run. Relative,
  # so the tree survives being moved. Rewritten only when it has to be, since this runs on
  # every load; -n/-f also replaces a plain file left by an older install or by
  # claude-cloud-bootstrap's cloud/scripts/02-install-pixi.sh.
  local link="$pixi_home/bin/pixi" want="../versions/$version/bin/pixi"
  if [[ "$(readlink "$link" 2>/dev/null)" != "$want" ]]; then
    mkdir -p "$pixi_home/bin"
    ln -sfn "$want" "$link"
  fi
  if [[ ! -f pixi.toml ]]; then
    local project_name tpl_dir tpl_file
    project_name="$(basename "$PWD")"
    # `use pixi <version> python` scaffolds from a named template; without one it stays
    # minimal. pixi is polyglot, so the language lives in the template name, not this
    # directive.
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
      # @PROJECT_NAME@ is the only placeholder; substitute the project dir name. The pinned
      # pixi version is deliberately not written into the manifest: the .envrc is the single
      # source of it, and a directive that kept a tracked file in sync would rewrite it on
      # every bump.
      sed "s/@PROJECT_NAME@/$project_name/g" "$tpl_file" > pixi.toml
      echo "direnv: created pixi.toml from '$template' template — remember to commit it to git" >&2
    else
      # No template named: minimal starter manifest.
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
  # PATH_add prepends, so the pinned version directory added second wins for `pixi` itself
  # while $PIXI_HOME/bin behind it still resolves `pixi global`'s shims. Adding the version
  # directory rather than relying on the symlink is what keeps this context on its own pin
  # when another context activates a different one, the same way use_fnm and use_sdk put a
  # version directory on PATH.
  PATH_add "$pixi_home/bin"
  PATH_add "$version_dir"
  "$version_bin" install --quiet || return 1
  local env_bin
  env_bin="$(pwd)/.pixi/envs/default/bin"
  PATH_add "$env_bin"
}
