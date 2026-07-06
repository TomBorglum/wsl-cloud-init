#!/bin/bash
set -euo pipefail

# Single source of truth for the provisioning run loop, used both by cloud-init
# (runcmd in user-data.template) and for on-demand re-runs on an already
# provisioned instance, e.g. to opt into an installation after the fact:
#
#   sudo INSTALL_GIT_CONFIG=true bash /opt/wsl-cloud-init/wsl/distros/ubuntu/install.sh
#
# install.sh derives one value shared by every install script (POWERSHELL, the WSL
# path to powershell.exe) and runs the install scripts in order. It passes through
# only the environment it is given (TARGET_USER, the INSTALL_* flags) plus the
# POWERSHELL it derives; each install script resolves whatever else it needs
# (Windows-derived values, secrets) on its own, so install.sh stays uncoupled from
# them and no secret is written to disk here.

REPO=/opt/wsl-cloud-init
SCRIPTS_DIR="$REPO/wsl/distros/ubuntu/scripts"

# The Linux account the per-user tooling is installed for. When invoked by hand
# this is the invoking user (sudo preserves it in SUDO_USER); cloud-init exports
# it explicitly.
export TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"

# POWERSHELL is always needed: the open/gh wrappers consume it at runtime. Interop
# and Windows PowerShell are always present under WSL, so it is derived below for
# every run.

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
# and dot-source it.
git -C "$REPO" sparse-checkout add windows/lib >/dev/null

# Build the PowerShell program: the shared path helper plus a tail that emits the
# converted powershell.exe path as a POWERSHELL=<value> line on stdout.
ps_tail='Write-Output ("POWERSHELL=" + (ConvertTo-WslPath (Get-Command powershell).Source))'

# Suppress PowerShell's progress stream ("Preparing modules for first use"),
# which otherwise leaks to stderr as CLIXML noise since we capture only stdout.
ps_header='$ProgressPreference = "SilentlyContinue"'
ps_program="$ps_header"$'\n'"$(cat "$REPO/windows/lib/Wsl.ps1")"$'\n'"$ps_tail"

# -EncodedCommand (base64 UTF-16LE) sidesteps cross-boundary quoting and the
# fact that powershell.exe, a Windows process, cannot read our /opt paths
# directly. The derived value is returned on stdout as a KEY=VALUE line.
encoded="$(printf '%s' "$ps_program" | iconv -t UTF-16LE | base64 | tr -d '\n')"
interop_output="$("$pwsh" -NoProfile -NonInteractive -EncodedCommand "$encoded")"

# Pull the POWERSHELL=<value> line off stdout and strip the trailing CR that
# PowerShell's Write-Output emits. The value keeps its backslash-escaped spaces.
POWERSHELL="$(sed -n 's/^POWERSHELL=//p' <<< "$interop_output" | tr -d '\r')"
export POWERSHELL

# Persist the resolved powershell.exe path so the open/gh wrappers read it from the
# environment at runtime rather than baking it in. Append it once and never override: if a
# POWERSHELL line already exists we leave it (that is the idempotency rule). cloud-init
# pre-creates .zshenv owned by TARGET_USER, so appending works here even while the home
# directory is still root-owned — appending to an already-owned file needs only file-write
# permission, not a writable parent dir. The value is written unquoted so its
# backslash-escaped spaces resolve when zsh sources .zshenv (System32 has none, but this
# keeps the escaping honest).
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

# On-demand opt-in runs leave new PATH entries, env vars, and zsh functions in the
# user's startup files; the calling shell only picks them up on its next read. We
# can't touch the parent shell from this child process, so just point the user at
# the reload. Gate on a TTY so cloud-init's first-boot run (no terminal, fresh login
# picks everything up anyway) stays quiet.
if [[ -t 1 ]]; then
  echo "Done. Run 'exec zsh' to load the new commands in this shell."
fi
