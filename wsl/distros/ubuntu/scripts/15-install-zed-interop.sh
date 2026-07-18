#!/bin/bash
set -euo pipefail

source /usr/local/lib/wsl-cloud-init/wsl-interop.sh

if [[ "${INSTALL_ZED_INTEROP:-}" != "true" ]]; then
  echo "INSTALL_ZED_INTEROP not set, skipping Zed interop install"
  exit 0
fi

# The wrapper is a real file under wsl/system (sparse-checked-out per
# user-data.template), installed idempotently with the executable bit. It resolves
# Zed's WSL-aware launcher itself at runtime via wsl_interop_zed_path (using
# $POWERSHELL from the env), so there is no per-editor value to persist here.
# Installing the wrapper is all opting into interop does; seeding the Windows-side
# Zed config is a separate opt-in gated below.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/zed /usr/local/bin/zed

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
