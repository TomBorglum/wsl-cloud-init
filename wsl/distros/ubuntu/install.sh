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
# The source paths (wsl/system/usr/local/lib/wsl-cloud-init, windows/lib) are provided
# by the sparse checkout declared in user-data.template's runcmd. Idempotent: install(1)
# overwrites cleanly on re-runs.
INTEROP_DIR=/usr/local/lib/wsl-cloud-init
INTEROP_SRC="$REPO/wsl/system/usr/local/lib/wsl-cloud-init"
install -D -m 644 "$INTEROP_SRC/wsl-interop.sh"       "$INTEROP_DIR/wsl-interop.sh"
install -D -m 644 "$INTEROP_SRC/wsl-cache.sh"         "$INTEROP_DIR/wsl-cache.sh"
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
# POWERSHELL line already exists we leave it (that is the idempotency rule). cloud-init's
# first runcmd chowns the home directory to TARGET_USER before install.sh runs, so this
# `sudo -u "$TARGET_USER" tee -a` both creates .zshenv (when absent) and writes it as the
# user. The value is written unquoted so its backslash-escaped spaces resolve when zsh
# sources .zshenv (System32 has none, but this keeps the escaping honest).
: "${POWERSHELL:?POWERSHELL is required}"
zshenv="/home/$TARGET_USER/.zshenv"
if ! sudo -u "$TARGET_USER" grep -q '^export POWERSHELL=' "$zshenv" 2>/dev/null; then
  printf 'export POWERSHELL=%s\n' "$POWERSHELL" | sudo -u "$TARGET_USER" tee -a "$zshenv" >/dev/null
fi

# Run every install script in order. They are independent and self-skip when
# their installation isn't selected; if one genuinely fails, stop the run and name
# it rather than pressing on and masking the problem.
#
# Each step is announced and timed, in one of two forms.
#
# Under cloud-init this output lands in /var/log/cloud-init-output.log, which is the only
# way to tell which step a slow or hung provision is sitting on -- `cloud-init analyze blame`
# collapses this entire loop into a single modules-final/config-scripts_user entry. There the
# `===> ` and `<=== ` markers are the contract provision.ps1 parses to pair each step into one
# progress line, so the two files are coupled: the prefixes and the `ok (N.Ns)` duration format
# both have to change together with the regexes there. They stay on separate lines so the log
# still reads sequentially; provision.ps1 is what joins them for display.
#
# On a terminal there is no provision.ps1 to do that joining, so printing the raw contract would
# just be noise. Each step gets the rendered equivalent instead -- the same line provisioning
# shows, emitted once the step has finished. Nothing is piped or reformatted on the way, so a
# step's own output stays live and untouched above its line.
#
# The gate is a TTY check rather than a flag because it needs no plumbing and cannot be wrong:
# cloud-init's stdout is the log file and is never a terminal.
if [[ -t 1 ]]; then on_tty=1; else on_tty=0; fi

# Mirrors Format-Duration in windows/scripts/provision.ps1: one decimal below a minute (most
# steps finish well inside a second), minutes above it, with the minute count floored so 90
# seconds does not read as "2m30s". Takes microseconds because that is what the loop measures.
format_duration() {
  local us=$1 s tenths
  s=$(( us / 1000000 ))
  if (( s < 60 )); then
    # Rounded to tenths as a whole, not by truncating the remainder: PowerShell's ToString('0.0')
    # rounds, so truncating here would print 1.0s where a provisioning log shows 1.1s. Carrying
    # through the whole value keeps 1.96s at 2.0s rather than an impossible 1.10s.
    tenths=$(( (us + 50000) / 100000 ))
    printf '%d.%ds' "$(( tenths / 10 ))" "$(( tenths % 10 ))"
  else
    printf '%dm%02ds' "$(( s / 60 ))" "$(( s % 60 ))"
  fi
}

# The glob is collected into an array first so the step count is known up front (and so
# the count never comes from parsing `ls`).
scripts=("$SCRIPTS_DIR"/*.sh)
total=${#scripts[@]}
i=0
for script in "${scripts[@]}"; do
  i=$((i + 1))
  name="$(basename "$script")"
  # $SECONDS is integer-only and most of these finish well inside a second, so time them from
  # EPOCHREALTIME (bash 5+, and every supported LTS ships at least 5.1) instead. It renders with
  # the locale's decimal separator, so the [.,] class strips either one and leaves plain integer
  # microseconds -- no float parsing, and correct under a comma-decimal locale. The stripped value
  # is around 1.8e15, comfortably inside bash's 64-bit arithmetic.
  step_start=${EPOCHREALTIME/[.,]/}
  (( on_tty )) || printf '===> [%02d/%02d] %s\n' "$i" "$total" "$name"
  if ! bash "$script"; then
    echo "install.sh: $name failed; aborting" >&2
    exit 1
  fi
  step_us=$(( ${EPOCHREALTIME/[.,]/} - step_start ))
  if (( on_tty )); then
    # Padded to the same column as provision.ps1's $StepLabelWidth, which fits the longest
    # label this can produce ('[14/16] 14-install-direnv-functions.sh'). Nothing parses this
    # line -- the two just need to look alike.
    label="$(printf '[%02d/%02d] %s' "$i" "$total" "$name")"
    printf '%-38s -> ok (%s)\n' "$label" "$(format_duration "$step_us")"
  else
    # Plain seconds, always: provision.ps1 matches `ok \(([\d.]+)s\)` and applies its own
    # formatting, so emitting "2m05s" here would stop matching and strand the step line open.
    printf '<=== %s ok (%d.%ds)\n' "$name" "$((step_us / 1000000))" "$(( (step_us % 1000000) / 100000 ))"
  fi
done
printf 'install.sh: %d scripts completed in %ds\n' "$total" "$SECONDS"

# On-demand opt-in runs leave new PATH entries, env vars, and zsh functions in the
# user's startup files; the calling shell only picks them up on its next read. We
# can't touch the parent shell from this child process, so just point the user at
# the reload. Gate on a TTY so cloud-init's first-boot run (no terminal, fresh login
# picks everything up anyway) stays quiet.
if [[ -t 1 ]]; then
  echo "Done. Run 'exec zsh' to load the new commands in this shell."
fi
