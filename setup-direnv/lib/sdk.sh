#!/bin/bash
# use_sdk <candidate> <version>
#
# CI-only (GitHub Actions) direnv directive for JVM SDKs via SDKMAN. The action
# installs this file onto the runner's ~/.config/direnv/lib; it is never run
# outside GitHub Actions. Self-contained by design: it sources no other file in
# this repository.
#
# Deliberately simpler than the terminal directive in
# distros/shared/direnv/lib/sdk.sh: that version's arg checks, SDKMAN_DIR override,
# subshell and PATH_add exist to keep direnv's interactive load/unload clean, which
# CI does not do. Here we use standard SDKMAN and rely on its built-in idempotency.
use_sdk() {
  local candidate=$1
  local version=$2
  local candidate_dir="$HOME/.sdkman/candidates/$candidate/$version"

  # Standard SDKMAN install; guard only to skip re-downloading on a warm rerun.
  if [[ ! -d "$HOME/.sdkman" ]]; then
    curl -fsSL https://get.sdkman.io | bash || return 1
  fi

  # SDKMAN is idempotent: an already-installed candidate is a no-op that exits 0.
  # Keep the || return 1 so a failed install fails the job rather than falling
  # through to the exports below and passing green with no SDK installed.
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk install "$candidate" "$version" || return 1

  # Expose the runtime to subsequent workflow steps.
  echo "$candidate_dir/bin" >> "$GITHUB_PATH"
  [[ "$candidate" == "java" ]] && echo "JAVA_HOME=$candidate_dir" >> "$GITHUB_ENV"
}
