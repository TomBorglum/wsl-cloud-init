#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_ZED_INTEROP:-}" != "true" ]]; then
  echo "INSTALL_ZED_INTEROP not set, skipping Zed interop install"
  exit 4  # not selected; see install.sh
fi

: "${TARGET_USER:?TARGET_USER is required}"

# The wrapper is a real file under wsl/system (sparse-checked-out per
# user-data.template), installed idempotently with the executable bit. It resolves
# Zed's WSL-aware launcher itself at runtime via wsl_interop_zed_path (using
# $POWERSHELL from the env), so there is no per-editor value to persist here.
# Installing the wrapper is all opting into interop does; seeding the Windows-side
# Zed config is a separate opt-in gated below.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/zed /usr/local/bin/zed

# Zed's Windows app runs a remote server inside this instance and remembers its PID across WSL
# restarts, even though PIDs do not survive one — which makes it kill whatever inherited that PID
# on the next boot, or hang on "Starting proxy" when that process is root's. The tmpfiles rule
# below clears the state at boot, when none of it can still be valid. Installed with interop
# rather than gated separately: both mean "this instance is used with Zed", and the rule is inert
# on one where Zed never runs.
#
# Written here rather than shipped as a wsl/system asset because the path is per-instance: the
# rule has to name the target user's home, and tmpfiles.d has no shell to resolve it. tee
# overwrites, so re-running is safe — which is how an already-provisioned instance picks this up.
tee /etc/tmpfiles.d/zed-server-state.conf > /dev/null <<EOF
# Clear Zed's stale WSL remote-server state at boot.
#
# Zed records its remote-server PID per workspace under server_state/<identifier>/server.pid.
# That directory survives a WSL restart; PIDs do not, since every boot restarts the PID
# namespace. check_pid_file (crates/remote_server/src/server.rs, Zed 1.14.2) only checks that the
# recorded PID exists, not that it belongs to a Zed server — so a survivor is either dead
# (harmless), reused by the user (Zed SIGKILLs an unrelated process of theirs, silently) or
# reused by root (the kill fails and the proxy exits, leaving the Windows client stuck on
# "Starting proxy").
#
# At boot there is by definition nothing valid here to protect, so clear it unconditionally — no
# liveness heuristic, and no way to race a running server. The '!' restricts this to boot;
# systemd-tmpfiles-setup.service is the only thing that runs with --boot, and only at boot.
#
# The trailing glob targets the contents rather than server_state/ itself: Zed's ServerPaths::new
# does a create_dir_all for the per-workspace subdir either way, so this is the smaller blast
# radius. Nothing matches on an instance where Zed has never run, which is not an error.
#
# Coupled to Zed's on-disk layout (verified against 1.14.2): if Zed moves server_state/, this rule
# stops matching and the bug returns quietly.
R! /home/$TARGET_USER/.local/share/zed/server_state/*
EOF

# Seeding the Windows Zed config is deliberately opt-in on top of interop: putting `zed`
# on PATH should not overwrite the user's settings.json/keymap.json. Only proceed when the
# WSL-only INSTALL_ZED_CONFIG flag is set (no provision-time switch feeds it).
if [[ "${INSTALL_ZED_CONFIG:-}" != "true" ]]; then
  echo "INSTALL_ZED_CONFIG not set, skipping Zed config seed"
  exit 0
fi

# Preconfigure the Windows Zed editor: seed settings.json/keymap.json into %APPDATA%\Zed.
# The assets are real files under wsl/system, pulled whole by the sparse checkout, so we copy
# straight from the /opt checkout: it is always present while install.sh runs (both cloud-init
# and on-demand opt-ins invoke this from /opt), and the config is consumed only here, during
# the run — no durable local mirror is needed.
ASSET_SRC=/opt/wsl-cloud-init/wsl/system/usr/local/share/zed

# Resolve %APPDATA%\Zed as a /mnt path over interop. ConvertTo-WslPath backslash-escapes
# spaces (a Windows username may contain them); undo that so the path works quoted in bash.
zed_cfg_dir="$(wsl_interop_zed_config_dir)"   # set -e exits here if resolution fails
zed_cfg_dir="${zed_cfg_dir//\\ / }"
: "${zed_cfg_dir:?could not resolve Windows Zed config dir}"

# Zed creates %APPDATA%\Zed on first launch, but on a box where it has never run the dir may
# not exist yet — create it so the seed does not fail on a fresh install.
mkdir -p "$zed_cfg_dir"

# Overwrite whatever is there, backing the previous file up to <name>.bak first so a hand
# edit is recoverable (only the most recent prior file is kept). Multiple WSL instances that
# opt into the config therefore converge on it, re-asserted on every opt-in run.
for f in settings.json keymap.json; do
  if [[ -f "$zed_cfg_dir/$f" ]]; then
    mv -f "$zed_cfg_dir/$f" "$zed_cfg_dir/$f.bak"
  fi
  cp -f "$ASSET_SRC/$f" "$zed_cfg_dir/$f"
done
