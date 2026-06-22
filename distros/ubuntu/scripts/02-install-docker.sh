#!/bin/bash
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  echo "docker already installed, skipping"
  exit 0
fi

CODENAME=$(lsb_release -cs)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
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
