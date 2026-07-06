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

# Install the shared WSL->Windows interop runtime to a durable, git-free location,
# co-located with the PowerShell helpers it dot-sources. This is a bootstrap (not a
# numbered script): install.sh sources the lib itself to derive POWERSHELL, and the
# gh wrapper re-sources it at runtime to re-authenticate after a Windows-side token
# rotation — neither can depend on the /opt checkout being present or writable.
# Idempotent: install(1) and `sparse-checkout add` overwrite cleanly on re-runs.
INTEROP_DIR=/usr/local/lib/wsl-cloud-init
INTEROP_SRC="$REPO/wsl/system/usr/local/lib/wsl-cloud-init"
git -C "$REPO" sparse-checkout add wsl/system/usr/local/lib/wsl-cloud-init windows/lib >/dev/null
install -D -m 644 "$INTEROP_SRC/wsl-interop.sh"       "$INTEROP_DIR/wsl-interop.sh"
install -D -m 644 "$REPO/windows/lib/Wsl.ps1"         "$INTEROP_DIR/Wsl.ps1"
install -D -m 644 "$REPO/windows/lib/Credentials.ps1" "$INTEROP_DIR/Credentials.ps1"

# Shared WSL->Windows interop helpers (dot-source + run a PowerShell derivation),
# sourced from the durable bundle the bootstrap above just installed.
source "$INTEROP_DIR/wsl-interop.sh"

# The Linux account the per-user tooling is installed for. When invoked by hand
# this is the invoking user (sudo preserves it in SUDO_USER); cloud-init exports
# it explicitly.
export TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"

# POWERSHELL is always needed: the open/gh wrappers consume it at runtime. Interop
# and Windows PowerShell are always present under WSL, so it is derived below for
# every run.

# Resolve the WSL path to Windows powershell.exe. wsl_interop_powershell_path
# bootstraps and self-reports it over interop; install.sh stays pure bash.
POWERSHELL="$(wsl_interop_powershell_path)" || exit 1
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
