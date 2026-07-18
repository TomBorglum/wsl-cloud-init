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
# Unlike the other opt-in installers this one does not early-exit when `zed` is
# already on PATH: the Windows-side config seed below must (re)run on every opt-in.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/zed /usr/local/bin/zed

# Preconfigure the Windows Zed editor: seed settings.json/keymap.json into %APPDATA%\Zed.
# The assets are real files under wsl/system (sparse-checked-out whole); install them to a
# durable mirror location so we copy from a stable local path rather than the /opt checkout.
ASSET_DIR=/usr/local/share/zed
ASSET_SRC=/opt/wsl-cloud-init/wsl/system/usr/local/share/zed
install -D -m 644 "$ASSET_SRC/settings.json" "$ASSET_DIR/settings.json"
install -D -m 644 "$ASSET_SRC/keymap.json"   "$ASSET_DIR/keymap.json"

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
# opt into Zed therefore converge on this config, re-asserted on every run.
for f in settings.json keymap.json; do
  if [[ -f "$zed_cfg_dir/$f" ]]; then
    mv -f "$zed_cfg_dir/$f" "$zed_cfg_dir/$f.bak"
  fi
  cp -f "$ASSET_DIR/$f" "$zed_cfg_dir/$f"
done
