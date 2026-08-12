#!/bin/bash
# use_sdk <candidate> <version>
#
# CI-only (GitHub Actions) direnv directive for JVM SDKs via SDKMAN. The action
# installs this file onto the runner's ~/.config/direnv/lib; it is never run
# outside GitHub Actions. Self-contained by design: it sources no other file in
# this repository.
#
# Deliberately simpler than the interactive terminal directive: arg checks, an
# SDKMAN_DIR override, a subshell and PATH_add exist to keep direnv's interactive
# load/unload clean, which CI does not do.
use_sdk() {
  local candidate=$1
  local version=$2

  # Standard SDKMAN install; guard only to skip re-downloading on a warm rerun.
  # --proto '=https' --tlsv1.2 pins the transfer to HTTPS/TLS 1.2+ (no plaintext
  # redirects), matching how the runtime is installed at provision time.
  if [[ ! -d "$HOME/.sdkman" ]]; then
    curl -fsSL --proto '=https' --tlsv1.2 https://get.sdkman.io | bash
  fi
  # Once per .envrc evaluation, not once per candidate: sdkman-init.sh sets every
  # <CANDIDATE>_HOME to its candidates/<c>/current symlink, so a second `use sdk` line
  # re-sourcing it would undo the pinned value the first one exported below. The guard
  # is the `sdk` function it defines.
  if ! command -v sdk >/dev/null 2>&1; then
    source "$HOME/.sdkman/bin/sdkman-init.sh"
  fi

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
  # SDKMAN's <CANDIDATE>_HOME (JAVA_HOME, MAVEN_HOME, …). The name is derived from the
  # candidate (SDKMAN's convention), not hardcoded.
  #
  # export, not an echo to $GITHUB_ENV: sourcing sdkman-init.sh above already put
  # <CANDIDATE>_HOME in this environment, pointing at the floating candidates/<c>/current
  # symlink, and this overwrites it with the version the .envrc asked for. The action
  # forwards the environment wholesale afterwards, so writing the pinned path to
  # $GITHUB_ENV separately would leave the two disagreeing here and let the symlink reach
  # a later step.
  echo "$candidate_dir/bin" >> "$GITHUB_PATH"
  export "${candidate^^}_HOME=$candidate_dir"
  return 0
}
