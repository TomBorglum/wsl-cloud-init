#!/bin/bash
set -euo pipefail

# Stop the virtual-console getty from holding the instance at "degraded".
#
# The Ubuntu WSL image enables a VT login the way it would on bare metal, with an image-time
# symlink at /etc/systemd/system/getty.target.wants/getty@tty1.service. Under WSL that login
# can never work and can never be reached:
#
#   agetty starts on /dev/tty1, the WSL VM gives it no usable virtual console, and it exits
#   immediately on SIGHUP. getty@.service carries Restart=always, so systemd restarts it in a
#   tight loop until the start limit trips, and the unit then sits at
#   `failed (Result: start-limit-hit)` for the rest of the boot.
#
# One permanently failed unit is enough to hold `systemctl is-system-running` at "degraded",
# which costs the instance its only one-bit health signal -- the same consequence
# 10-install-wsl-interop-fix.sh masks systemd-binfmt.service to avoid. Nothing is lost by
# removing the getty: sessions arrive through WSL's /init and wsl.exe on pts/*, never through a
# VT, and systemd's own container interface says as much for the analogous case ("spawn a single
# shell on /dev/console, and not care about VTs or multiple gettys on VTs"). WSL is not detected
# as a container, so the VT getty is attempted here anyway. Units of this kind are already
# masked here by two separate mechanisms: WSL's own systemd generator masks
# console-getty.service and both network-wait units on every boot
# (/run/systemd/generator/<unit> -> /dev/null), and the Ubuntu packaging ships hwclock,
# screen-cleanup, x11-common, cryptdisks and sudo.service pre-masked in /usr/lib. The VT getty
# is the one both of them miss.
#
# Mask rather than disable. Disabling only removes the image's .wants symlink, which a
# `systemctl preset-all` or a systemd package reinstall can put back -- and the instance would
# then return to "degraded" on some later boot with nothing to say why. A mask is a symlink to
# /dev/null that no enablement, preset or manual start can override.
#
# Canonical documents a third option for units that misbehave under WSL, a drop-in carrying
# `ConditionVirtualization=!wsl`, and recommends it by name for systemd-binfmt.service. It is
# not used here because it is release-dependent: WSL detection landed in systemd v256, and
# provision.ps1 also supports Ubuntu 24.04 (systemd 255) and 22.04 (249). systemd ignores an
# unrecognized virtualization id rather than failing closed, so on those two releases the getty
# loop would come back with no visible sign the fix had not applied. Masking behaves identically
# on all three.

# cloud-init's package phase runs long before this script, so the unit has already looped and
# failed by the time we get here. Masking alone does not undo that -- the failure stays recorded
# for the rest of the boot, so a freshly provisioned instance would still report "degraded" and
# look as though this had not worked. `--now` stops the unit, cancelling the restart loop if it
# is still cycling; `reset-failed` afterwards clears the record. The order matters: stopping a
# failed unit leaves it failed, so clearing first and masking second would leave the first boot
# degraded anyway. Both commands are idempotent, which is why this needs no already-installed
# guard -- and why it must not have one, since reset-failed has to run on every invocation.
systemctl mask --now getty@tty1.service
systemctl reset-failed getty@tty1.service >/dev/null 2>&1 || true

# Say what the instance is left with. Deliberately not `is-system-running`: this runs inside
# cloud-final, where that reports "starting" or "degraded" on cloud-init's own account and would
# print a verdict that says nothing about this unit.
echo "getty@tty1 masked ($(systemctl is-enabled getty@tty1.service 2>&1), $(systemctl is-active getty@tty1.service 2>&1))"
