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
# This is the single point of derivation for POWERSHELL. The cloud-init runcmd
# block exports only TARGET_USER and the INSTALL_* flags; POWERSHELL is resolved
# here at runtime via Windows interop, the same way for cloud-init and on-demand.
# provision.ps1 no longer derives or substitutes it, so nothing else is persisted.
# The opt-in scripts resolve their own Windows-derived values and secrets: 07 reads
# the git identity, 08 the Context7 key, 10 the VS Code path, the gh wrapper the
# GitHub token, so install.sh doesn't know about them and no secret is written to disk.

REPO=/opt/wsl-cloud-init
SCRIPTS_DIR="$REPO/wsl/distros/ubuntu/scripts"

# The Linux account the per-user tooling is installed for. When invoked by hand
# this is the invoking user (sudo preserves it in SUDO_USER); cloud-init exports
# it explicitly.
export TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"

# Interop and Windows PowerShell are always present under WSL, and POWERSHELL is
# always needed (the ungated open/gh wrappers consume it at runtime), so it is
# always derived below. Every opt-in script (07 for the git identity, 08 for the
# Context7 key, 10 for the VS Code path) resolves its own Windows-derived values
# over interop, so install.sh doesn't know about them.

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

# The error-prone bit (Windows->WSL path conversion) is reused verbatim from the
# Windows side rather than reimplemented; pull windows/lib into the sparse checkout
# and dot-source it. (07/08/10 read the same checkout for their own derivations.)
git -C "$REPO" sparse-checkout add windows/lib >/dev/null

# Build the PowerShell program: the shared path helper plus a tail that emits
# POWERSHELL as a KEY=VALUE line. The derivation mirrors provision.ps1 one-for-one.
ps_tail='Write-Output ("POWERSHELL=" + (ConvertTo-WslPath (Get-Command powershell).Source))'

# Suppress PowerShell's progress stream ("Preparing modules for first use"),
# which otherwise leaks to stderr as CLIXML noise since we capture only stdout.
ps_header='$ProgressPreference = "SilentlyContinue"'
ps_program="$ps_header"$'\n'"$(cat "$REPO/windows/lib/Wsl.ps1")"$'\n'"$ps_tail"

# -EncodedCommand (base64 UTF-16LE) sidesteps cross-boundary quoting and the
# fact that powershell.exe, a Windows process, cannot read our /opt paths
# directly. The derived values are returned on stdout as KEY=VALUE lines.
encoded="$(printf '%s' "$ps_program" | iconv -t UTF-16LE | base64 | tr -d '\n')"
interop_output="$("$pwsh" -NoProfile -NonInteractive -EncodedCommand "$encoded")"

# Parse KEY=VALUE lines. IFS=/-r preserve the backslash-escaped spaces in the
# WSL paths; strip the trailing CR that PowerShell's Write-Output emits.
while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -z "$line" ]] && continue
  case "$line" in
    POWERSHELL=*) export POWERSHELL="${line#*=}" ;;
    *)            ;;
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
