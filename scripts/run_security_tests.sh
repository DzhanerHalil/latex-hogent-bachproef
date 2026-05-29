#!/bin/bash
# run_security_tests.sh - VIC BP - draai BINNEN guest (VM, LXC unpriv, LXC priv)
# Slaat alle relevante artefacten op in /root/security_results/
set -euo pipefail
LABEL="${1:-unknown}"   # bv. VM_pmx8, LXC_unpriv_pmx8, LXC_priv_pmx8
DIR="/root/security_results/$LABEL"
mkdir -p "$DIR"

echo "=== Security audit: $LABEL ==="
{
  echo "## meta"
  date -Is
  uname -a
  cat /etc/os-release | head -3
} > "$DIR/00_meta.txt"

# === 1. amicontained ===
echo "[1/6] amicontained..."
/usr/local/bin/amicontained > "$DIR/01_amicontained.txt" 2>&1 || true

# === 2. Capabilities ===
echo "[2/6] capabilities..."
{
  echo "## /proc/self/status"
  grep -E 'Cap(Inh|Prm|Eff|Bnd|Amb)' /proc/self/status
  echo "## capsh --print"
  capsh --print 2>/dev/null || echo "capsh not installed"
} > "$DIR/02_capabilities.txt"

# === 3. Namespaces ===
echo "[3/6] namespaces..."
ls -l /proc/self/ns/ > "$DIR/03_namespaces.txt"

# === 4. Cgroup info ===
echo "[4/6] cgroup..."
{
  echo "## /proc/self/cgroup"
  cat /proc/self/cgroup
  echo "## memory.max"
  cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null
  echo "## cpu.max"
  cat /sys/fs/cgroup/cpu.max 2>/dev/null
} > "$DIR/04_cgroup.txt"

# === 5. Cgroup memory limit test (BP §3.4.3 punt 3) ===
echo "[5/6] stress-ng memory limit doorbraak-test..."
# Probeer 2× allocated RAM te vragen — moet door OOM-killer worden gedood
timeout 90 stress-ng --vm 1 --vm-bytes 10G --timeout 60s --metrics-brief \
    > "$DIR/05_stress_oom.txt" 2>&1 || echo "stress-ng exit=$? (verwacht: gedood door OOM)" >> "$DIR/05_stress_oom.txt"
dmesg | tail -50 > "$DIR/05_dmesg_after_stress.txt" 2>/dev/null || true

# === 6. Filesystem / device access ===
echo "[6/6] filesystem isolation..."
{
  echo "## lsblk (verwacht: leeg/beperkt in unpriv LXC)"
  lsblk 2>&1 || echo "denied"
  echo "## fdisk -l"
  fdisk -l 2>&1 | head -20 || echo "denied"
  echo "## /dev/sda toegang"
  ls -la /dev/sda 2>&1 || echo "no /dev/sda"
  dd if=/dev/sda of=/dev/null bs=512 count=1 2>&1 || echo "read denied"
  echo "## mount poging"
  mount 2>&1 | head
} > "$DIR/06_filesystem.txt"

echo "Klaar. Resultaten: $DIR"
echo "Vergelijk later: VM vs LXC-unpriv vs LXC-priv"
