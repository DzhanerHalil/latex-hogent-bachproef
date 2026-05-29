#!/bin/bash
# setup_tools.sh - VIC BP - install benchmarking + security tools
# Gebruik op alle 4 testomgevingen (VM/LXC × Proxmox 8/9)
set -euo pipefail

LOG=/root/setup_tools.log
exec > >(tee -a "$LOG") 2>&1

echo "=== setup_tools.sh start: $(date -Is) ==="
export DEBIAN_FRONTEND=noninteractive

echo "[1/5] Disable unattended upgrades (voorkomt drift tussen runs)..."
systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl disable unattended-upgrades.service 2>/dev/null || true
apt-get -y purge unattended-upgrades 2>/dev/null || true
sed -i 's|^APT::Periodic::Update-Package-Lists.*|APT::Periodic::Update-Package-Lists "0";|' \
    /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true

echo "[2/5] Refresh package list (geen full upgrade)..."
apt-get update -y

echo "[3/5] Install benchmark + monitoring tools..."
apt-get install -y --no-install-recommends \
    sysbench fio iperf3 stress-ng \
    apache2-utils wrk \
    htop sysstat time bc jq curl wget \
    procps iproute2 net-tools

echo "[4/5] Install security audit tools..."
apt-get install -y --no-install-recommends lynis

echo "[5/5] Install amicontained (pinned v0.4.9)..."
AMIC_URL="https://github.com/genuinetools/amicontained/releases/download/v0.4.9/amicontained-linux-amd64"
AMIC_SHA="d8a5066d04d31bce81550d9cf73c75a4d59f4d7d99f3bf5d6c7b7a3e2e80c6d3"  # verify before use
curl -fsSL "$AMIC_URL" -o /usr/local/bin/amicontained
chmod +x /usr/local/bin/amicontained

echo "=== Versies ==="
{
  echo "Datum: $(date -Is)"
  echo "Kernel: $(uname -r)"
  echo "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | head -1)"
  echo "--- tools ---"
  sysbench --version
  fio --version
  iperf3 --version | head -1
  stress-ng --version | head -1
  /usr/local/bin/amicontained --version 2>&1 | head -1
} | tee /root/tool_versions.txt

echo "=== setup_tools.sh klaar: $(date -Is) ==="
