#!/bin/bash
set -euo pipefail
# Keep secrets out of any xtrace output if the script is run with `bash -x`.
set +x

# Single source of truth for the provisioning run loop, used both by cloud-init
# (runcmd in user-data.template) and for on-demand re-runs in an already
# provisioned instance, e.g. to opt into an installation after the fact:
#
#   sudo INSTALL_GIT_CONFIG=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh
#
# This is the single point of derivation for both paths. The cloud-init runcmd
# block exports only TARGET_USER and the INSTALL_* flags; every Windows-derived
# value (paths, git identity, secrets) is resolved here at runtime via Windows
# interop, the same way for cloud-init and on-demand. provision.ps1 no longer
# derives or substitutes any of them, so nothing is persisted and no secret is
# ever written to disk.

REPO=/opt/wsl-cloud-init
SCRIPTS_DIR="$REPO/wsl/distros/ubuntu/scripts"

# The Linux account the per-user tooling is installed for. When invoked by hand
# this is the invoking user (sudo preserves it in SUDO_USER); cloud-init exports
# it explicitly.
export TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"

# Interop and Windows PowerShell are always present under WSL, and POWERSHELL is
# always needed (the ungated open/gh wrappers consume it at runtime), so it is
# always derived below. The remaining Windows-derived values are opt-in: each is
# queried only when its installation is selected and it isn't already provided.
vscode_q=false; git_q=false; claude_q=false
if [[ "${INSTALL_VS_CODE_INTEROP:-}" == "true" && -z "${VSCODE:-}" ]]; then
  vscode_q=true
fi
if [[ "${INSTALL_GIT_CONFIG:-}" == "true" ]] &&
   { [[ -z "${GIT_CREDENTIAL_MANAGER:-}" ]] || [[ -z "${GIT_NAME:-}" ]] ||
     [[ -z "${GIT_EMAIL:-}" ]]; }; then
  git_q=true
fi
if [[ "${INSTALL_CLAUDE_CODE:-}" == "true" && -z "${CONTEXT7_API_KEY:-}" ]]; then
  claude_q=true
fi

# Bootstrap interop from the fixed OS location of Windows PowerShell. It is
# part of Windows itself (independent of anything we install), and is only the
# entry point: the authoritative POWERSHELL value is self-reported below.
pwsh=""
for candidate in /mnt/*/Windows/System32/WindowsPowerShell/v1.0/powershell.exe; do
  [[ -x "$candidate" ]] && { pwsh="$candidate"; break; }
done
if [[ -z "$pwsh" ]]; then
  echo "install.sh: powershell.exe not found under /mnt/*/Windows/System32/WindowsPowerShell/v1.0/" >&2
  exit 1
fi

# The error-prone bits (credential-blob marshalling, Windows->WSL path
# conversion) are reused verbatim from the Windows side rather than
# reimplemented; pull them into the sparse checkout and dot-source them.
git -C "$REPO" sparse-checkout add windows/lib >/dev/null

# Build the PowerShell program: the two shared helpers plus a tail that emits the
# values we need as KEY=VALUE lines. The path/identity derivations mirror
# provision.ps1 one-for-one. POWERSHELL is always emitted; the opt-in values are
# appended when their installation was selected.
ps_tail='Write-Output ("POWERSHELL=" + (ConvertTo-WslPath (Get-Command powershell).Source))'$'\n'
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
fi
if [[ "$claude_q" == true ]]; then
  ps_tail+='Write-Output ("CONTEXT7_API_KEY=" + (Get-WindowsCredential "wsl-cloud-init:CONTEXT7_API_KEY"))'$'\n'
fi

# Suppress PowerShell's progress stream ("Preparing modules for first use"),
# which otherwise leaks to stderr as CLIXML noise since we capture only stdout.
ps_header='$ProgressPreference = "SilentlyContinue"'
ps_program="$ps_header"$'\n'"$(cat "$REPO/windows/lib/Credentials.ps1" "$REPO/windows/lib/Wsl.ps1")"$'\n'"$ps_tail"

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
    CONTEXT7_API_KEY=*)       export CONTEXT7_API_KEY="${line#*=}" ;;
    *)                        ;;
  esac
done <<< "$interop_output"

# Persist the resolved powershell.exe path so the open/gh wrappers read it from the
# environment at runtime rather than baking it in. Append it once and never override: if a
# POWERSHELL line already exists we leave it (that is the idempotency rule). cloud-init
# pre-creates .zshenv owned by TARGET_USER, so appending works here even though the home
# directory is still root-owned until 01-install-home.sh chowns it — appending to an
# already-owned file needs only file-write permission, not a writable parent dir. The value
# is written unquoted so ConvertTo-WslPath's backslash-escaped spaces resolve when zsh
# sources .zshenv (System32 has none, but this keeps the escaping honest).
: "${POWERSHELL:?POWERSHELL is required}"
zshenv="/home/$TARGET_USER/.zshenv"
if ! sudo -u "$TARGET_USER" grep -q '^export POWERSHELL=' "$zshenv" 2>/dev/null; then
  printf 'export POWERSHELL=%s\n' "$POWERSHELL" | sudo -u "$TARGET_USER" tee -a "$zshenv" >/dev/null
fi

# Run every install script in order. They are independent and self-skip when
# their installation isn't selected; if one genuinely fails, stop the run and name
# it rather than pressing on and masking the problem.
for script in "$SCRIPTS_DIR"/*.sh; do
  if ! bash "$script"; then
    echo "install.sh: $(basename "$script") failed; aborting" >&2
    exit 1
  fi
done

# On-demand opt-in runs leave new PATH entries (Claude), env vars, and zsh functions
# (git helpers) in the user's startup files; the calling shell only picks them up on
# its next read. We can't touch the parent shell from this child process, so just
# point the user at the reload. Gate on a TTY so cloud-init's first-boot run (no
# terminal, fresh login picks everything up anyway) stays quiet.
if [[ -t 1 ]]; then
  echo "Done. Run 'exec zsh' to load the new commands in this shell."
fi
