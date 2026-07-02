#!/bin/bash
# use_fnm <tool> <version>
#
# CI-only (GitHub Actions) direnv directive for Node via fnm. The action installs
# this file onto the runner's ~/.config/direnv/lib; it is never run outside GitHub
# Actions. Self-contained by design: it sources no other file in this repository.
#
# Deliberately simpler than the terminal directive in
# distros/shared/direnv/lib/fnm.sh: that version's arg checks, list-remote guard
# and PATH_add exist to keep direnv's interactive load/unload clean, which CI does
# not do. Node has no canonical <TOOL>_HOME convention, so this exports only the
# bin dir to $GITHUB_PATH (no $GITHUB_ENV, unlike use_sdk).
use_fnm() {
  # $1 is the trusted tool token ('node'); fnm is Node-only, so ignore it and take
  # the version. CI trusts the committed .envrc — no arg validation.
  local version=$2

  # Standard fnm install into ~/.fnm; guard only to skip re-downloading on a warm
  # rerun / full cache hit. --proto '=https' --tlsv1.2 pins the transfer to
  # HTTPS/TLS 1.2+ (no plaintext redirects), matching the repo's other installers
  # (distros/ubuntu/scripts/06-install-fnm.sh).
  if [[ ! -d "$HOME/.fnm" ]]; then
    curl -fsSL --proto '=https' --tlsv1.2 https://fnm.vercel.app/install \
      | bash -s -- --install-dir "$HOME/.fnm" --skip-shell
  fi
  # Put the fnm binary on PATH (CI has no shell integration / PATH_add) — the analog
  # of the terminal directive's `PATH_add "$HOME/.fnm"`. No FNM_DIR export: fnm
  # already defaults its data dir to ~/.fnm (where the version_dir below and the
  # action's cache expect it), same as the terminal copy relies on.
  export PATH="$HOME/.fnm:$PATH"

  # `fnm install` is idempotent, so run it unconditionally and don't gate on its
  # exit — the dir check below is the real success signal. A non-exact version (e.g.
  # '22') installs as v22.x.y, so v${version} won't exist and this fails cleanly
  # rather than exporting a path to nothing.
  fnm install "$version" || true
  local version_dir="$HOME/.fnm/node-versions/v${version}/installation/bin"
  if [[ ! -d "$version_dir" ]]; then
    echo "use_fnm: failed to install node $version" >&2
    ls -la "$HOME/.fnm/node-versions" >&2 2>/dev/null || true
    # exit, not return: direnv silently ignores a directive that `return`s a
    # non-zero code (the job would go green with nothing installed), whereas a
    # non-zero `exit` from the .envrc propagates and fails the step.
    exit 1
  fi

  # Expose the runtime to subsequent workflow steps: the node bin on $GITHUB_PATH.
  echo "$version_dir" >> "$GITHUB_PATH"
  return 0
}
