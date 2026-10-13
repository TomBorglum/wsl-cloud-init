#!/bin/bash
set -euo pipefail

# Stop systemd-binfmt from wiping WSL's interop handler.
#
# binfmt_misc is one table shared by every distro in the WSL VM, and WSL's own /init
# registers the WSLInterop entry in it that makes Windows *.exe launches work (code,
# explorer.exe, the Windows git credential helper, ...).
#
# systemd-binfmt.service manages that same table on systemd's behalf:
#
#   ExecStart=/usr/lib/systemd/systemd-binfmt              # add what /usr/lib/binfmt.d lists
#   ExecStop=/usr/lib/systemd/systemd-binfmt --unregister  # flush the table - all of it
#
# The ExecStop is the problem. It runs when this distro shuts down and takes WSLInterop
# with it, so interop breaks in every *other* distro still running in the VM, with
# nothing to explain it but "Exec format error". The ExecStart half is merely noisy:
# python3.14-minimal ships /usr/lib/binfmt.d/python3.14.conf (the .pyc magic), which is
# what satisfies the unit's ConditionDirectoryNotEmpty and makes it run at all, so the
# first distro to boot registers it and every later one exits 1 on an entry that is
# already there - one failed unit, and `systemctl is-system-running` reporting
# "degraded" forever after.
#
# So mask it. Nothing here needs systemd to manage binfmt_misc: WSL registers the one
# entry that matters, and the .pyc handler it would add is a convenience nothing in a
# provisioned instance uses. Masking removes the cause outright, rather than repairing the
# damage afterwards with a poll that re-registered WSLInterop whenever it went missing.
#
# This only holds for distros that have it masked. binfmt_misc is shared, so one distro
# this repo never provisioned - or `docker buildx`'s binfmt installer, or
# qemu-user-static/binfmt-support - can still flush the table. Those are documented in
# the README as a step to take by hand, deliberately: a background service that polled
# against them would hide the fact that one was missed.

# cloud-init's package phase runs before this script and will already have started - and, on
# any distro that is not the first to boot in the VM, failed - the unit. Masking does not undo
# that: the failure stays recorded for the rest of the boot, so a freshly provisioned instance
# would report "degraded" and look as though this had not worked. Clear it first, then mask so
# it cannot come back. Both are idempotent - mask is a symlink to /dev/null that `mask`
# overwrites - so this needs no already-installed guard.
systemctl reset-failed systemd-binfmt.service >/dev/null 2>&1 || true
systemctl mask systemd-binfmt.service

# Say what the instance is left with, since the useful signal is the handler's presence
# rather than the unit's state. Not a gate: WSL registers WSLInterop when the distro
# starts, and provisioning can run before that has happened.
if grep -qs '^enabled' /proc/sys/fs/binfmt_misc/WSLInterop; then
  echo "systemd-binfmt masked; WSLInterop is registered"
else
  echo "systemd-binfmt masked; WSLInterop is not registered yet (WSL registers it on distro start)" >&2
fi
