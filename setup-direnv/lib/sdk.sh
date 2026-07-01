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
# CI does not do.
use_sdk() {
  local candidate=$1
  local version=$2

  # Standard SDKMAN install; guard only to skip re-downloading on a warm rerun.
  if [[ ! -d "$HOME/.sdkman" ]]; then
    curl -fsSL https://get.sdkman.io | bash
  fi
  source "$HOME/.sdkman/bin/sdkman-init.sh"

  # `sdk home` is the canonical resolver: it prints the candidate's install dir and
  # exits non-zero when it isn't installed. Use it both as the idempotency gate
  # (skip `sdk install` — and its network round-trip — when already present) and,
  # after installing, as the real success signal. Don't gate on `sdk install`'s own
  # exit code: it returns non-zero even when the candidate installs fine.
  local candidate_dir
  candidate_dir="$(sdk home "$candidate" "$version" 2>/dev/null || true)"
  if [[ -z "$candidate_dir" ]]; then
    sdk install "$candidate" "$version" || true
    candidate_dir="$(sdk home "$candidate" "$version" 2>/dev/null || true)"
  fi
  if [[ ! -d "$candidate_dir" ]]; then
    echo "use_sdk: failed to install $candidate $version (SDKMAN_DIR=${SDKMAN_DIR:-unset})" >&2
    ls -la "${SDKMAN_DIR:-$HOME/.sdkman}/candidates/$candidate" >&2 2>/dev/null || true
    # exit, not return: direnv silently ignores a directive that `return`s a
    # non-zero code (the job would go green with nothing installed), whereas a
    # non-zero `exit` from the .envrc propagates and fails the step.
    exit 1
  fi

  # Expose the runtime to subsequent workflow steps: the bin on $GITHUB_PATH, plus
  # SDKMAN's <CANDIDATE>_HOME (JAVA_HOME, MAVEN_HOME, …) on $GITHUB_ENV. The name is
  # derived from the candidate (SDKMAN's convention), not hardcoded — matching the
  # terminal directive in distros/shared/direnv/lib/sdk.sh.
  echo "$candidate_dir/bin" >> "$GITHUB_PATH"
  echo "${candidate^^}_HOME=$candidate_dir" >> "$GITHUB_ENV"
}
