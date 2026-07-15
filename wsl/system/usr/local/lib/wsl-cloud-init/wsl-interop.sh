#!/bin/bash
# wsl-interop.sh — shared WSL->Windows interop helpers.
#
# Sourced (not executed) by install.sh, the install scripts that resolve
# Windows-derived values (paths, secrets), and the gh wrapper that re-authenticates
# on the fly. It encapsulates all of the PowerShell: from a caller's point of view
# this is just a bash script that exposes functions returning plain values.
#
# It is installed as a durable runtime bundle at /usr/local/lib/wsl-cloud-init/,
# co-located with the Wsl.ps1 / Credentials.ps1 helpers it dot-sources. That makes it
# self-contained: no git, no /opt checkout, no network at call time — so a runtime
# consumer (the gh wrapper) can re-authenticate after a Windows-side token rotation.
# Callers own `set -euo pipefail`; this file deliberately does not.
#
#   source /usr/local/lib/wsl-cloud-init/wsl-interop.sh
#   POWERSHELL="$(wsl_interop_powershell_path)"
#   VSCODE="$(wsl_interop_vscode_path)"
#   ZED="$(wsl_interop_zed_path)"
#   ZED_CONFIG_DIR="$(wsl_interop_zed_config_dir)"
#   secret="$(wsl_interop_credential "wsl-cloud-init:CONTEXT7_API_KEY")"

# ---------------------------------------------------------------------------
# Private plumbing (leading underscore): not part of the public API.
# ---------------------------------------------------------------------------

# Directory this script was installed into. The PowerShell helpers (Wsl.ps1,
# Credentials.ps1) are copied here alongside it at install time, so they are read
# relative to self rather than pulled from a repo checkout.
_WSL_INTEROP_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

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
# <lib>        basename of a co-located helper to dot-source (e.g. Wsl.ps1,
#              Credentials.ps1), or empty to dot-source nothing.
# <ps_tail>    PowerShell appended after the helper; its Write-Output lines are stdout.
_wsl_interop_run() {
  local powershell="$1" lib="$2" ps_tail="$3" program encoded
  # Suppress PowerShell's progress stream ("Preparing modules for first use"),
  # which otherwise leaks to stderr as CLIXML noise since we capture only stdout.
  program='$ProgressPreference = "SilentlyContinue"'$'\n'
  # Reuse the error-prone Windows->WSL path/credential helpers verbatim from the
  # co-located .ps1 rather than reimplementing them in PowerShell here.
  [[ -n "$lib" ]] && program+="$(cat "$_WSL_INTEROP_DIR/$lib")"$'\n'
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
  # Assembled line by line (each PowerShell statement one bash line, joined by $'\n')
  # so no single source line runs off the screen.
  local ps_tail=''
  ps_tail+='$gitExe = (Get-Command git).Source'$'\n'
  ps_tail+='$credMgr = (Split-Path (Split-Path $gitExe -Parent) -Parent) +'$'\n'
  ps_tail+='  "\mingw64\bin\git-credential-manager.exe"'$'\n'
  ps_tail+='Write-Output ("GIT_CREDENTIAL_MANAGER=" + (ConvertTo-WslPath $credMgr))'$'\n'
  ps_tail+='Write-Output ("GIT_NAME=" + (git config --global user.name))'$'\n'
  ps_tail+='Write-Output ("GIT_EMAIL=" + (git config --global user.email))'
  _wsl_interop_run "$POWERSHELL" Wsl.ps1 "$ps_tail"
}

# Echo the Windows VS Code `code` shell-script launcher in /mnt form, for baking into a
# `code` wrapper. The wrapper is invoked from bash over /mnt, so it must point at the
# WSL-aware POSIX shell script (`bin/code`), not the `code.cmd`/`.exe` siblings. Resolve
# whatever `Get-Command code` returns to its directory and target the `code` sibling
# directly, so the result is correct regardless of which launcher is first on PATH; fail
# loudly if that shell script is absent rather than baking a wrapper that can't run.
wsl_interop_vscode_path() {
  : "${POWERSHELL:?POWERSHELL is required}"
  # Assembled line by line (each PowerShell statement one bash line, joined by $'\n')
  # so no single source line runs off the screen.
  local ps_tail=''
  ps_tail+='$src = (Get-Command code).Source'$'\n'
  ps_tail+='$shell = Join-Path (Split-Path $src -Parent) "code"'$'\n'
  ps_tail+='if (-not (Test-Path -LiteralPath $shell)) {'$'\n'
  ps_tail+='  throw "wsl-interop: VS Code '"'"'code'"'"' shell launcher missing beside $src"'$'\n'
  ps_tail+='}'$'\n'
  ps_tail+='Write-Output (ConvertTo-WslPath $shell)'
  _wsl_interop_run "$POWERSHELL" Wsl.ps1 "$ps_tail"
}

# Echo the Windows Zed `zed` shell-script launcher in /mnt form, for baking into a
# `zed` wrapper. Like VS Code, Zed ships a WSL-aware POSIX shell launcher (`zed`, no
# extension) beside its `zed.exe`/`zed.cmd` siblings; the wrapper is invoked from bash
# over /mnt, so it must point at that shell script, not the `.exe`. Resolve whatever
# `Get-Command zed` returns to its directory and target the `zed` sibling directly, so
# the result is correct regardless of which launcher is first on PATH; fail loudly if
# that shell script is absent rather than baking a wrapper that can't run.
wsl_interop_zed_path() {
  : "${POWERSHELL:?POWERSHELL is required}"
  # Assembled line by line (each PowerShell statement one bash line, joined by $'\n')
  # so no single source line runs off the screen.
  local ps_tail=''
  ps_tail+='$src = (Get-Command zed).Source'$'\n'
  ps_tail+='$shell = Join-Path (Split-Path $src -Parent) "zed"'$'\n'
  ps_tail+='if (-not (Test-Path -LiteralPath $shell)) {'$'\n'
  ps_tail+='  throw "wsl-interop: Zed '"'"'zed'"'"' shell launcher missing beside $src"'$'\n'
  ps_tail+='}'$'\n'
  ps_tail+='Write-Output (ConvertTo-WslPath $shell)'
  _wsl_interop_run "$POWERSHELL" Wsl.ps1 "$ps_tail"
}

# Echo the WSL /mnt path to the Windows Zed config directory (%APPDATA%\Zed), for seeding
# settings.json/keymap.json onto the Windows side from WSL. $env:APPDATA is always the Roaming
# folder of the invoking Windows user; ConvertTo-WslPath maps it to /mnt form. As with the
# launcher resolvers the spaces come back backslash-escaped (a Windows username may contain
# them), so a caller that uses the path in a quoted bash context must unescape them first.
wsl_interop_zed_config_dir() {
  : "${POWERSHELL:?POWERSHELL is required}"
  # Assembled line by line (each PowerShell statement one bash line, joined by $'\n')
  # so no single source line runs off the screen.
  local ps_tail=''
  ps_tail+='$dir = Join-Path $env:APPDATA "Zed"'$'\n'
  ps_tail+='Write-Output (ConvertTo-WslPath $dir)'
  _wsl_interop_run "$POWERSHELL" Wsl.ps1 "$ps_tail"
}
