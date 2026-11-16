#!/bin/bash
use_pixi() {
  # Usage: use pixi <version> [template]
  #
  # pixi installs itself on first use rather than at provision time, so this directive does
  # not depend on the instance having been provisioned with it. Each pinned version lives in
  # its own directory under $PIXI_HOME/versions, with $PIXI_HOME/bin/pixi a symlink into that
  # store, and nothing is ever uninstalled. PIXI_HOME stays ~/.pixi because
  # pixi-completion.zsh evaluates $HOME/.pixi/bin/pixi by absolute path.
  local version="${1:-}" template="${2:-}"
  # Exact version only, as use_fnm requires of node: a partial pin is the drift this directive
  # exists to stop.
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "use_pixi: a fully qualified pixi version is required: use pixi <version> [template]" >&2
    return 1
  fi
  local pixi_home="$HOME/.pixi"
  local version_dir="$pixi_home/versions/$version/bin"
  local version_bin="$version_dir/pixi"
  # Guarded on the version the binary reports, not merely on its presence: `pixi self-update`
  # run inside an active context rewrites it in place, and an existence check would then let
  # the wrong version survive every later load.
  if [[ "$("$version_bin" --version 2>/dev/null)" != "pixi $version" ]]; then
    # Say so before the download: it is the one moment `direnv allow` visibly stalls, and
    # direnv's own warn_timeout (5s) fires during it.
    echo "direnv: pixi $version is not installed — installing it now" >&2
    rm -rf "$pixi_home/versions/$version"
    # PIXI_BIN_DIR puts the binary in the version store rather than $PIXI_HOME/bin, and
    # PIXI_NO_PATH_UPDATE=1 keeps the installer out of the shell rc files, since this directive
    # owns PATH. --proto '=https' --tlsv1.2 keeps the transfer on HTTPS and TLS 1.2 or newer.
    curl -fsSL --proto '=https' --tlsv1.2 https://pixi.sh/install.sh \
      | PIXI_VERSION="$version" PIXI_HOME="$pixi_home" \
        PIXI_BIN_DIR="$version_dir" PIXI_NO_PATH_UPDATE=1 bash || return 1
    # Removing a mismatched entry rather than leaving it means a half-finished install retries
    # here instead of wedging every later load.
    if [[ "$("$version_bin" --version 2>/dev/null)" != "pixi $version" ]]; then
      echo "use_pixi: could not install pixi $version to $version_bin" >&2
      rm -rf "$pixi_home/versions/$version"
      return 1
    fi
  fi
  # $PIXI_HOME/bin/pixi follows the version this context pins, because pixi-completion.zsh
  # evaluates it by absolute path before any PATH_add has run. The target is relative so the
  # tree survives being moved, and -n/-f also replaces a plain file left by an older install.
  local link="$pixi_home/bin/pixi" want="../versions/$version/bin/pixi"
  if [[ "$(readlink "$link" 2>/dev/null)" != "$want" ]]; then
    mkdir -p "$pixi_home/bin"
    ln -sfn "$want" "$link"
  fi
  if [[ ! -f pixi.toml ]]; then
    local project_name tpl_dir tpl_file
    project_name="$(basename "$PWD")"
    # `use pixi <version> python` scaffolds from a named template; without one it stays
    # minimal.
    tpl_dir="$HOME/.config/pixi/templates"
    if [[ -n "$template" ]]; then
      # A named template that does not exist is a typo to surface rather than paper over with
      # a minimal manifest, so this errors out before creating pixi.toml or installing.
      tpl_file="$tpl_dir/$template.toml"
      if [[ ! -f "$tpl_file" ]]; then
        echo "use_pixi: no '$template' template found in $tpl_dir" >&2
        return 1
      fi
      # @PROJECT_NAME@ is the only placeholder. The pinned pixi version is deliberately not
      # written into the manifest: the .envrc is the single source of it, and a directive that
      # kept a tracked file in sync would rewrite it on every bump.
      sed "s/@PROJECT_NAME@/$project_name/g" "$tpl_file" > pixi.toml
      echo "direnv: created pixi.toml from '$template' template — remember to commit it to git" >&2
    else
      cat > pixi.toml <<EOF
[workspace]
name = "$project_name"
channels = ["conda-forge"]
platforms = ["linux-64"]
EOF
      echo "direnv: created minimal pixi.toml — remember to commit it to git" >&2
    fi
  fi
  # Watched here even though require_allowed watches what it guards: the pixi.lock guard below
  # is conditional on the file existing. Idempotent against an .envrc that also lists them.
  watch_file pixi.toml pixi.lock
  # PATH_add prepends, so the pinned version directory added second wins for `pixi` itself
  # while $PIXI_HOME/bin behind it still resolves `pixi global`'s shims. The version directory
  # rather than the symlink is what keeps this context on its own pin when another context
  # activates a different one.
  PATH_add "$pixi_home/bin"
  PATH_add "$version_dir"
  # Everything below executes code the project supplies: `pixi install` builds a pypi source
  # dependency, and activation runs the packages' activate.d scripts and the manifest's
  # [activation] section. A manifest or lockfile that changed under the user is re-approved
  # before any of that runs. Requires direnv >= 2.38.0.
  require_allowed pixi.toml
  "$version_bin" install --quiet || return 1
  # Guarded after the install, not beside the manifest: `direnv allow` errors on a required
  # file that does not exist, so listing pixi.lock before the install that creates it blocks
  # every load of a project without one, including one just scaffolded above.
  if [[ -f pixi.lock ]]; then
    require_allowed pixi.lock
  fi
  # --shell bash: direnv evaluates an .envrc with bash, and the zsh hook emits compinit lines
  # that do not parse there. The hook expands PATH as it writes it, so it has to follow both
  # PATH_add calls for the pinned directories to survive behind the environment.
  local hook
  # Captured first: `eval "$(...)"` would report eval's status, not the hook's.
  hook="$("$version_bin" shell-hook --shell bash --change-ps1 false --frozen --no-install)" || return 1
  eval "$hook"
}
