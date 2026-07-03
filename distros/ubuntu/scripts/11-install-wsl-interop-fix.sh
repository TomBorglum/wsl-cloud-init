#!/bin/bash
set -euo pipefail

# Keep WSL's binfmt_misc interop handler registered.
#
# binfmt_misc is shared across the WSL VM. When another distro's
# systemd-binfmt (or a daemon-reload) flushes it, this distro's WSLInterop
# entry is wiped and never restored -- so Windows *.exe launches (code,
# explorer.exe, ...) start failing. A ~10s timer re-registers the handler
# whenever it goes missing.

tee /etc/systemd/system/wsl-interop-register.service > /dev/null <<'EOF'
[Unit]
Description=Re-register WSL interop binfmt handler if missing
ConditionPathExists=/init

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'grep -qs "^enabled" /proc/sys/fs/binfmt_misc/WSLInterop || { echo -1 > /proc/sys/fs/binfmt_misc/WSLInterop 2>/dev/null; echo ":WSLInterop:M::MZ::/init:P" > /proc/sys/fs/binfmt_misc/register; }'
EOF

tee /etc/systemd/system/wsl-interop-register.timer > /dev/null <<'EOF'
[Unit]
Description=Keep WSL interop binfmt registration alive

[Timer]
OnBootSec=10s
OnUnitActiveSec=10s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable wsl-interop-register.timer
systemctl start wsl-interop-register.timer
