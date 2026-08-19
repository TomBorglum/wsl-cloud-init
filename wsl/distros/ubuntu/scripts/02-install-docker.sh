#!/bin/bash
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  echo "docker already installed, skipping"
  exit 3  # already installed; see install.sh
fi

CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
if [[ -z "$CODENAME" ]]; then
  echo "Could not determine Ubuntu codename from /etc/os-release" >&2
  exit 1
fi
install -m 0755 -d /etc/apt/keyrings
curl -fsSL --proto '=https' --tlsv1.2 https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq
printf '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
rm /usr/sbin/policy-rc.d
mkdir -p /etc/docker
tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl enable docker
systemctl start docker

# Docker is not just this script's payload -- bringing dockerd up creates the docker0 bridge
# and rewrites the host's iptables rules, which briefly disrupts WSL's network. Every script
# after this one downloads over that network, and a curl that starts during the churn fails
# mid-transfer, taking the run down three steps away from the actual cause. `systemctl start`
# returns on systemd's view of the unit, so wait here until the daemon is genuinely up and
# answering before handing back to install.sh and letting the next script begin.
#
# The wait is counted in poll iterations, not against a wall clock: a fresh instance boots
# with an approximate CLOCK_REALTIME that time synchronisation corrects while this very
# script runs (see the uptime_cs comment in install.sh), so $SECONDS can step mid-loop.
# One poll per second, so the poll count is the timeout in seconds and the two cannot drift
# apart in the message below.
DOCKER_WAIT_POLLS=60
DOCKER_WAIT_INTERVAL=1

# ActiveState and SubState are read as key=value pairs rather than by position: systemd prints
# `show` properties in its own internal order, not the order the -p flags are given, so
# `--value` output cannot be split positionally. Comparing whole values also keeps
# ActiveState=activating from reading as active.
active='' sub=''
for (( i = 0; i < DOCKER_WAIT_POLLS; i++ )); do
  while IFS='=' read -r key value; do
    case "$key" in
      ActiveState) active="$value" ;;
      SubState)    sub="$value" ;;
    esac
  done < <(systemctl show docker -p ActiveState -p SubState)
  if [[ "$active" == "active" && "$sub" == "running" ]]; then
    break
  fi
  sleep "$DOCKER_WAIT_INTERVAL"
done
if [[ "$active" != "active" || "$sub" != "running" ]]; then
  echo "docker did not reach active/running within ${DOCKER_WAIT_POLLS}s (last state: ${active:-unknown}/${sub:-unknown})" >&2
  # Diagnostics only, on the way out: `systemctl status` exits non-zero for a failed unit.
  systemctl status docker --no-pager >&2 || true
  journalctl -u docker -n 50 --no-pager >&2 || true
  exit 1
fi

# active/running is systemd's view of dockerd. This confirms the daemon is answering on its
# socket, which is what the next script's network -- and the user's first `docker` command --
# actually depend on.
ready=0
for (( i = 0; i < DOCKER_WAIT_POLLS; i++ )); do
  if docker info >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep "$DOCKER_WAIT_INTERVAL"
done
if (( ! ready )); then
  echo "docker is active/running but the daemon is not answering on its socket" >&2
  journalctl -u docker -n 50 --no-pager >&2 || true
  exit 1
fi

echo "docker is active/running and answering on its socket"
