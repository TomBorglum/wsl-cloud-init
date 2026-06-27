#!/bin/bash
set -euo pipefail
# Keep secrets out of any xtrace output if the script is run with `bash -x`.
set +x

# Single source of truth for the provisioning run loop, used both by cloud-init
# (runcmd in user-data.template) and for on-demand re-runs in an already
# provisioned instance, e.g. to opt into a capability after the fact:
#
#   sudo INSTALL_GIT_CONFIG=true bash /opt/wsl-cloud-init/distros/ubuntu/run.sh
#
# This is the single point of derivation for both paths. The cloud-init runcmd
# block exports only TARGET_USER and the INSTALL_* flags; every Windows-derived
# value (paths, git identity, secrets) is resolved here at runtime via Windows
# interop, the same way for cloud-init and on-demand. provision.ps1 no longer
# derives or substitutes any of them, so nothing is persisted and no secret is
# ever written to disk.

REPO=/opt/wsl-cloud-init
SCRIPTS_DIR="$REPO/distros/ubuntu/scripts"

# The Linux account the per-user tooling is installed for. When invoked by hand
# this is the invoking user (sudo preserves it in SUDO_USER); cloud-init exports
# it explicitly.
export TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"

# Work out which Windows-derived values are still missing. POWERSHELL is needed
# whenever unset because the (ungated) open-interop script consumes it; the rest
# are only needed when their capability is being installed.
need_interop=false
need_powershell=false; vscode_q=false; git_q=false; claude_q=false
if [[ -z "${POWERSHELL:-}" ]]; then need_powershell=true; need_interop=true; fi
if [[ "${INSTALL_VS_CODE_INTEROP:-}" == "true" && -z "${VSCODE:-}" ]]; then
  vscode_q=true; need_interop=true
fi
if [[ "${INSTALL_GIT_CONFIG:-}" == "true" ]] &&
   { [[ -z "${GIT_CREDENTIAL_MANAGER:-}" ]] || [[ -z "${GIT_NAME:-}" ]] ||
     [[ -z "${GIT_EMAIL:-}" ]] || [[ -z "${GH_TOKEN:-}" ]]; }; then
  git_q=true; need_interop=true
fi
if [[ "${INSTALL_CLAUDE_CODE:-}" == "true" && -z "${CONTEXT7_API_KEY:-}" ]]; then
  claude_q=true; need_interop=true
fi

if [[ "$need_interop" == true ]]; then
  # Bootstrap interop from the fixed OS location of Windows PowerShell. It is
  # part of Windows itself (independent of anything we install), and is only the
  # entry point: the authoritative POWERSHELL value is self-reported below.
  pwsh=""
  for candidate in /mnt/*/Windows/System32/WindowsPowerShell/v1.0/powershell.exe; do
    [[ -x "$candidate" ]] && { pwsh="$candidate"; break; }
  done
  if [[ -z "$pwsh" ]]; then
    echo "run.sh: powershell.exe not found under /mnt/*/Windows/System32/WindowsPowerShell/v1.0/" >&2
    exit 1
  fi

  # The error-prone bits (credential-blob marshalling, Windows->WSL path
  # conversion) are reused verbatim from the Windows side rather than
  # reimplemented; pull them into the sparse checkout and dot-source them.
  git -C "$REPO" sparse-checkout add windows/lib >/dev/null

  # Build the PowerShell program: the two shared helpers plus a tail that emits
  # only the values we still need as KEY=VALUE lines. The path/identity
  # derivations mirror provision.ps1 one-for-one.
  ps_tail=""
  if [[ "$need_powershell" == true ]]; then
    ps_tail+='Write-Output ("POWERSHELL=" + (ConvertTo-WslPath (Get-Command powershell).Source))'$'\n'
  fi
  if [[ "$vscode_q" == true ]]; then
    ps_tail+='$vsc = (Get-Command code).Source -replace "\.cmd$",""'$'\n'
    ps_tail+='Write-Output ("VSCODE=" + (ConvertTo-WslPath $vsc))'$'\n'
  fi
  if [[ "$git_q" == true ]]; then
    ps_tail+='$gitExe = (Get-Command git).Source'$'\n'
    ps_tail+='$credMgr = (Split-Path (Split-Path $gitExe -Parent) -Parent) + "\mingw64\bin\git-credential-manager.exe"'$'\n'
    ps_tail+='Write-Output ("GIT_CREDENTIAL_MANAGER=" + (ConvertTo-WslPath $credMgr))'$'\n'
    ps_tail+='Write-Output ("GIT_NAME=" + (git config --global user.name))'$'\n'
    ps_tail+='Write-Output ("GIT_EMAIL=" + (git config --global user.email))'$'\n'
    ps_tail+='Write-Output ("GH_TOKEN=" + (Get-WindowsCredential "wsl-cloud-init:GH_TOKEN"))'$'\n'
  fi
  if [[ "$claude_q" == true ]]; then
    ps_tail+='Write-Output ("CONTEXT7_API_KEY=" + (Get-WindowsCredential "wsl-cloud-init:CONTEXT7_API_KEY"))'$'\n'
  fi

  ps_program="$(cat "$REPO/windows/lib/Credentials.ps1" "$REPO/windows/lib/Wsl.ps1")"$'\n'"$ps_tail"

  # -EncodedCommand (base64 UTF-16LE) sidesteps cross-boundary quoting and the
  # fact that powershell.exe, a Windows process, cannot read our /opt paths
  # directly. Secrets are fetched inside PowerShell and returned on stdout; the
  # encoded program on the command line contains only the fetch code, never a
  # secret value.
  encoded="$(printf '%s' "$ps_program" | iconv -t UTF-16LE | base64 | tr -d '\n')"
  interop_output="$("$pwsh" -NoProfile -NonInteractive -EncodedCommand "$encoded")"

  # Parse KEY=VALUE lines. IFS=/-r preserve the backslash-escaped spaces in the
  # WSL paths; strip the trailing CR that PowerShell's Write-Output emits.
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    case "$line" in
      POWERSHELL=*)             export POWERSHELL="${line#*=}" ;;
      VSCODE=*)                 export VSCODE="${line#*=}" ;;
      GIT_CREDENTIAL_MANAGER=*) export GIT_CREDENTIAL_MANAGER="${line#*=}" ;;
      GIT_NAME=*)               export GIT_NAME="${line#*=}" ;;
      GIT_EMAIL=*)              export GIT_EMAIL="${line#*=}" ;;
      GH_TOKEN=*)               export GH_TOKEN="${line#*=}" ;;
      CONTEXT7_API_KEY=*)       export CONTEXT7_API_KEY="${line#*=}" ;;
    esac
  done <<< "$interop_output"
fi

# Run every script. They are independent, so one failing should not skip the
# rest; collect failures and report them so a real problem still surfaces (and is
# named) rather than aborting silently on the first.
failed=()
for script in "$SCRIPTS_DIR"/*.sh; do
  if ! bash "$script"; then
    failed+=("$(basename "$script")")
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "run.sh: the following scripts failed: ${failed[*]}" >&2
  exit 1
fi
