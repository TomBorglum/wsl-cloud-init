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

  # Standard SDKMAN install; guard only to skip re-downloading on a warm rerun.
  if [[ ! -d "$HOME/.sdkman" ]]; then
    curl -fsSL https://get.sdkman.io | bash
  fi
  source "$HOME/.sdkman/bin/sdkman-init.sh"

  # `sdk install` is idempotent, but its exit code is unreliable — it returns
  # non-zero even when the candidate installs fine — so don't gate on it. Install,
  # then ask SDKMAN itself where the candidate lives; `sdk home` is the canonical
  # resolver and its success is the real signal that the install landed.
  sdk install "$candidate" "$version" || true
  local candidate_dir
  candidate_dir="$(sdk home "$candidate" "$version" 2>/dev/null || true)"
  if [[ -z "$candidate_dir" || ! -d "$candidate_dir" ]]; then
    echo "use_sdk: failed to install $candidate $version (SDKMAN_DIR=${SDKMAN_DIR:-unset})" >&2
    ls -la "${SDKMAN_DIR:-$HOME/.sdkman}/candidates/$candidate" >&2 2>/dev/null || true
    # exit, not return: direnv silently ignores a directive that `return`s a
    # non-zero code (the job would go green with nothing installed), whereas a
    # non-zero `exit` from the .envrc propagates and fails the step.
    exit 1
  fi

  # Expose the runtime to subsequent workflow steps.
  echo "$candidate_dir/bin" >> "$GITHUB_PATH"
  [[ "$candidate" == "java" ]] && echo "JAVA_HOME=$candidate_dir" >> "$GITHUB_ENV"
}
