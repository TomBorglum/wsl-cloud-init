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

# Resolve the WSL path to Windows powershell.exe. Derived unconditionally on every
# run: the open/gh wrappers consume POWERSHELL at runtime, and both interop and
# Windows PowerShell are always present under WSL, so there is nothing to gate on.
# wsl_interop_powershell_path bootstraps and self-reports it over interop, keeping
# install.sh pure bash.
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
# just be noise -- and so is a step announcing that it had nothing to do. There each step is
# reduced to a single status line, with its own output captured rather than shown (and replayed
# only if it fails). The label is printed before the step runs, so a slow one is visibly in
# progress; nothing can interrupt that line, because the step's output is being captured.
#
# The gate is a TTY check rather than a flag because it needs no plumbing and cannot be wrong:
# cloud-init's stdout is the log file and is never a terminal.
if [[ -t 1 ]]; then on_tty=1; else on_tty=0; fi

# Install scripts report what they did through their exit code, since a script that skipped is
# otherwise indistinguishable from one that installed something:
#
#   0  did the work
#   3  already installed -- the guard at the top found its payload in place
#   4  not selected -- the INSTALL_* flag for an opt-in feature is not set
#   *  failed, and the run stops
#
# 3 and 4 keep clear of 1 (generic error), 2 (misuse) and the 126+ range the shell reserves.
# Every numbered script has to honour this; running one by hand can therefore exit non-zero
# without anything being wrong.
STATUS_ALREADY_INSTALLED=3
STATUS_NOT_SELECTED=4

# Sample the monotonic clock and return centiseconds since boot, as a plain integer.
#
# The first field of /proc/uptime is seconds since boot, written by the kernel as %lu.%02lu:
# always exactly two decimal places, and always a literal '.' whatever the locale. Deleting
# that '.' is therefore a unit conversion to centiseconds, not a truncation, and it keeps
# every duration in integer arithmetic -- bash has no floating point. Two prerequisites ride
# on that: /proc must be mounted, and the format must stay at two decimals, since a kernel
# writing a different precision would silently change the unit this returns.
#
# The clock must be monotonic, not a wall clock. A fresh instance boots with an approximate
# CLOCK_REALTIME that time synchronisation corrects once systemd and the network are up --
# which is what 02-install-docker.sh brings up, inside the range being timed. EPOCHREALTIME
# and bash's $SECONDS both track CLOCK_REALTIME and so step when that correction lands;
# /proc/uptime does not.
#
# `read` is a builtin, so sampling costs no process. Centisecond resolution is far finer than
# the tenth of a second ever displayed.
uptime_cs() {
  local up _
  read -r up _ < /proc/uptime
  printf '%s' "${up/./}"
}

# Mirrors Format-Duration in windows/scripts/provision.ps1: one decimal below a minute (most
# steps finish well inside a second), minutes above it, with the minute count floored so that
# 90 seconds reads as "1m30s". Takes centiseconds, the unit uptime_cs returns.
format_duration() {
  local cs=$1 s tenths
  if (( cs < 0 )); then cs=0; fi
  s=$(( cs / 100 ))
  if (( s < 60 )); then
    # Round the whole centisecond value to tenths, rather than truncating its remainder:
    # provision.ps1 formats with ToString('0.0'), which rounds, and the two renderings have to
    # agree. Rounding the whole value also carries: 196cs gives 2.0s, not 1.10s.
    tenths=$(( (cs + 5) / 10 ))
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
run_start=$(uptime_cs)
for script in "${scripts[@]}"; do
  i=$((i + 1))
  name="$(basename "$script")"

  # Sized to the same column as provision.ps1's $StepLabelWidth, which fits the longest label
  # this can produce ('[14/16] 14-install-direnv-functions.sh'). Nothing parses the terminal
  # line -- the two just need to look alike.
  label="$(printf '[%02d/%02d] %s' "$i" "$total" "$name")"

  step_start=$(uptime_cs)

  # Every step runs with stdin on /dev/null. The steps are non-interactive by contract --
  # cloud-init runs them with no terminal at all -- but on a terminal they would otherwise
  # inherit it, and a step that read from it would hang with nothing on screen: its output is
  # being captured, so the prompt it is waiting on is invisible, and a step that puts the
  # terminal into raw mode (any TUI installer or CLI that decides it is interactive because
  # stdin is a tty) also swallows Ctrl-C, leaving the terminal apparently locked up. Detaching
  # stdin turns that silent hang into an immediate, visible failure, which the handler below
  # replays. Applied on both branches so the two behave identically.
  #
  # `rc=0; cmd || rc=$?` rather than `if ! cmd`, so a status of 3 or 4 is read rather than
  # treated as the failure `set -e` would otherwise make of it.
  rc=0
  if (( on_tty )); then
    # Written unpadded; the padding that lines the '->' column up is added when the status
    # arrives, so a step that fails here does not leave a trail of spaces behind it.
    printf '%s' "$label"
    out="$(bash "$script" 2>&1 </dev/null)" || rc=$?
  else
    printf '===> %s\n' "$label"
    bash "$script" </dev/null || rc=$?
  fi
  # The `<===` line must carry a non-negative duration: provision.ps1 matches it with `[\d.]+`,
  # which no negative value satisfies. uptime_cs is monotonic, so the subtraction cannot go
  # negative and the clamp never fires; it is here to state that requirement at the single
  # point both renderings below read the value from.
  step_cs=$(( $(uptime_cs) - step_start ))
  if (( step_cs < 0 )); then step_cs=0; fi

  case $rc in
    0)                            status='ok' ;;
    $STATUS_ALREADY_INSTALLED)    status='already installed' ;;
    $STATUS_NOT_SELECTED)         status='not selected' ;;
    *)
      # Nothing was shown while the step ran on a terminal, so put back what it said before
      # naming it. `out` is only set on that path, hence the ${out:-} guard under `set -u`.
      if (( on_tty )); then
        printf '\n'
        if [[ -n "${out:-}" ]]; then printf '%s\n' "$out"; fi
      fi
      echo "install.sh: $name failed; aborting" >&2
      exit 1
      ;;
  esac

  if (( on_tty )); then
    # 39 = the 38-wide label column plus the single space before '->'; at least one space
    # always separates them, however long the name grows.
    pad=$(( 39 - ${#label} ))
    if (( pad < 1 )); then pad=1; fi
    printf '%*s-> %s (%s)\n' "$pad" '' "$status" "$(format_duration "$step_cs")"
  else
    # The literal `ok` and a bare decimal, whatever the status: provision.ps1's marker pattern
    # requires that exact shape and formats the duration itself, so substituting the status
    # word here would fail its match and cost the step its timing. The status is not lost --
    # the log holds the script's own message saying what it did.
    printf '<=== %s ok (%d.%ds)\n' "$name" "$((step_cs / 100))" "$(( (step_cs % 100) / 10 ))"
  fi
done
printf 'install.sh: %d scripts completed in %s\n' "$total" "$(format_duration $(( $(uptime_cs) - run_start )))"

# On-demand opt-in runs leave new PATH entries, env vars, and zsh functions in the
# user's startup files; the calling shell only picks them up on its next read. We
# can't touch the parent shell from this child process, so just point the user at
# the reload. Gate on a TTY so cloud-init's first-boot run (no terminal, fresh login
# picks everything up anyway) stays quiet.
if [[ -t 1 ]]; then
  echo "Done. Run 'exec zsh' to load the new commands in this shell."
fi
