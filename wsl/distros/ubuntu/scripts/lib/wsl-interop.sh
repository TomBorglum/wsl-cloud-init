#!/bin/bash
# wsl-interop.sh — shared WSL->Windows interop helpers.
#
# Sourced (not executed) by install.sh and the install scripts that resolve
# Windows-derived values (paths, secrets) over interop. It encapsulates all of
# the PowerShell: from a caller's point of view this is just a bash script that
# exposes functions returning plain values. Everything Windows-facing — pulling
# windows/lib into the sparse checkout, dot-sourcing a .ps1 helper, running a
# derivation through powershell.exe, and stripping the trailing CR — lives here.
# Callers own `set -euo pipefail`; this file deliberately does not.
#
#   source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/wsl-interop.sh"
#   POWERSHELL="$(wsl_interop_powershell_path)"
#   VSCODE="$(wsl_interop_vscode_path)"
#   secret="$(wsl_interop_credential "wsl-cloud-init:CONTEXT7_API_KEY")"

# ---------------------------------------------------------------------------
# Private plumbing (leading underscore): not part of the public API.
# ---------------------------------------------------------------------------

# The sparse checkout of this repo on the guest. Overridable, but the same fixed
# location every caller previously hard-coded.
WSL_INTEROP_REPO="${WSL_INTEROP_REPO:-/opt/wsl-cloud-init}"

# Locate the Windows powershell.exe from its fixed OS location. It is part of
# Windows itself (independent of anything we install) and serves only as the
# bootstrap entry point; the authoritative POWERSHELL path is self-reported by
# wsl_interop_powershell_path. Echoes the path, or fails with a message.
_wsl_interop_locate_powershell() {
  local candidate
  for candidate in /mnt/*/Windows/System32/WindowsPowerShell/v1.0/powershell.exe; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "wsl-interop: powershell.exe not found under /mnt/*/Windows/System32/WindowsPowerShell/v1.0/" >&2
  return 1
}

# Run a PowerShell derivation over interop and echo its stdout (CR stripped).
#
#   _wsl_interop_run <powershell> <lib> <ps_tail>
#
# <powershell> path to powershell.exe to invoke. Passed explicitly (not read from
#              the env) so the powershell-path resolver can use the bootstrap
#              binary before the authoritative $POWERSHELL is known.
# <lib>        basename of a helper under windows/lib to dot-source (e.g. Wsl.ps1,
#              Credentials.ps1), or empty to dot-source nothing.
# <ps_tail>    PowerShell appended after the helper; its Write-Output lines are stdout.
_wsl_interop_run() {
  local powershell="$1" lib="$2" ps_tail="$3" program encoded
  # Reuse the error-prone Windows->WSL path/credential helpers verbatim from the
  # Windows side rather than reimplementing them; pull windows/lib into the sparse
  # checkout and dot-source the requested helper.
  git -C "$WSL_INTEROP_REPO" sparse-checkout add windows/lib >/dev/null
  # Suppress PowerShell's progress stream ("Preparing modules for first use"),
  # which otherwise leaks to stderr as CLIXML noise since we capture only stdout.
  program='$ProgressPreference = "SilentlyContinue"'$'\n'
  [[ -n "$lib" ]] && program+="$(cat "$WSL_INTEROP_REPO/windows/lib/$lib")"$'\n'
  program+="$ps_tail"
  # -EncodedCommand (base64 UTF-16LE) sidesteps cross-boundary quoting and the fact
  # that powershell.exe, a Windows process, cannot read our /opt paths directly.
  encoded="$(printf '%s' "$program" | iconv -t UTF-16LE | base64 | tr -d '\n')"
  # Strip the trailing CR that PowerShell's Write-Output emits on each line.
  "$powershell" -NoProfile -NonInteractive -EncodedCommand "$encoded" | tr -d '\r'
}

# ---------------------------------------------------------------------------
# Public API: bash functions that return plain values. No caller sees PowerShell.
# ---------------------------------------------------------------------------

# Echo the WSL path to Windows powershell.exe (backslash-escaped spaces preserved).
# Self-contained: bootstraps from the fixed OS location, then self-reports the
# authoritative path over interop. Unlike the other helpers it does not need
# $POWERSHELL — it is what resolves $POWERSHELL in the first place.
wsl_interop_powershell_path() {
  local bootstrap
  bootstrap="$(_wsl_interop_locate_powershell)" || return 1
  _wsl_interop_run "$bootstrap" Wsl.ps1 \
    'Write-Output (ConvertTo-WslPath (Get-Command powershell).Source)'
}

# Echo a Windows Credential Manager secret for the given target (e.g.
# "wsl-cloud-init:CONTEXT7_API_KEY"). The value is fetched inside PowerShell and
# only the fetch code crosses the boundary, never the secret on argv.
wsl_interop_credential() {
  local target="$1"
  : "${POWERSHELL:?POWERSHELL is required}"
  _wsl_interop_run "$POWERSHELL" Credentials.ps1 \
    "Write-Output (Get-WindowsCredential \"$target\")"
}

# Echo the git config resolved from Windows as three KEY=VALUE lines:
# GIT_CREDENTIAL_MANAGER=, GIT_NAME=, GIT_EMAIL=. Callers parse the lines.
wsl_interop_git_config() {
  : "${POWERSHELL:?POWERSHELL is required}"
  _wsl_interop_run "$POWERSHELL" Wsl.ps1 \
    '$gitExe = (Get-Command git).Source'$'\n''$credMgr = (Split-Path (Split-Path $gitExe -Parent) -Parent) + "\mingw64\bin\git-credential-manager.exe"'$'\n''Write-Output ("GIT_CREDENTIAL_MANAGER=" + (ConvertTo-WslPath $credMgr))'$'\n''Write-Output ("GIT_NAME=" + (git config --global user.name))'$'\n''Write-Output ("GIT_EMAIL=" + (git config --global user.email))'
}

# Echo the Windows VS Code executable in /mnt form, for baking into a `code` wrapper.
wsl_interop_vscode_path() {
  : "${POWERSHELL:?POWERSHELL is required}"
  _wsl_interop_run "$POWERSHELL" Wsl.ps1 \
    '$vsc = (Get-Command code).Source -replace "\.cmd$",""'$'\n''Write-Output (ConvertTo-WslPath $vsc)'
}
