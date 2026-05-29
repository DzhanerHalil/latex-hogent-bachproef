#!/bin/bash
# run_benchmarks.sh - VIC BP - 1 iteratie performance suite
# Gebruik: ./run_benchmarks.sh <run_nummer> <host_ip>
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Gebruik: $0 <run_nummer> <proxmox_host_ip>"
    echo "Voorbeeld: $0 1 10.0.10.110"
    exit 1
fi

RUN="$1"
HOST_IP="$2"
RES_DIR="/root/test_results/run_${RUN}"
mkdir -p "$RES_DIR"

# --- Run-metadata vastleggen ---
{
  echo "run=$RUN"
  echo "start=$(date -Is)"
  echo "hostname=$(hostname)"
  echo "kernel=$(uname -r)"
  echo "os=$(lsb_release -ds 2>/dev/null || head -1 /etc/os-release)"
  echo "host_ip=$HOST_IP"
  echo "cpu_count=$(nproc)"
  echo "mem_total_kB=$(grep MemTotal /proc/meminfo | awk '{print $2}')"
  cat /proc/cpuinfo | grep -m1 'model name'
} > "$RES_DIR/meta.txt"

# Helper: drop caches voor reproduceerbaarheid
drop_caches() { sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true; }

echo "============================================="
echo "RUN $RUN — start $(date -Is)"
echo "Resultaten: $RES_DIR"
echo "============================================="

# === 0. IDLE BASELINE (BP §3.4.3 punt 2) ===
echo "[0/8] Idle-baseline (60s)..."
sleep 5  # laat shell-overhead bezinken
{
  echo "--- meminfo ---"; cat /proc/meminfo
  echo "--- ps_count ---"; ps -e | wc -l
  echo "--- top_idle ---"; top -bn1 | head -20
  echo "--- free_idle ---"; free -m
} > "$RES_DIR/idle_baseline.txt"
# 60s vmstat sample
vmstat 5 12 > "$RES_DIR/idle_vmstat.txt"

# === 1. CPU - single thread ===
echo "[1/8] CPU sysbench 1 thread (60s)..."
drop_caches
sysbench cpu --threads=1 --time=60 --cpu-max-prime=20000 run \
    > "$RES_DIR/cpu_1_thread.txt"

# === 2. CPU - multi thread ===
echo "[2/8] CPU sysbench 4 threads (60s)..."
drop_caches
sysbench cpu --threads=4 --time=60 --cpu-max-prime=20000 run \
    > "$RES_DIR/cpu_4_threads.txt"

# === 3. Memory ===
echo "[3/8] Memory sysbench (60s)..."
drop_caches
sysbench memory --threads=1 --time=60 \
    --memory-block-size=1M --memory-total-size=100G \
    --memory-oper=write run > "$RES_DIR/memory.txt"

# === 4. Disk I/O (random RW, 4K, queue 32) — JSON output ===
echo "[4/8] Disk fio randrw 4K (60s)..."
drop_caches
fio --name=vic_disk --ioengine=libaio --direct=1 \
    --rw=randrw --rwmixread=70 --bs=4k --numjobs=1 --iodepth=32 \
    --size=1G --runtime=60 --time_based --group_reporting \
    --filename="$RES_DIR/.fio_testfile" \
    --output-format=json --output="$RES_DIR/disk_io.json"
rm -f "$RES_DIR/.fio_testfile"

# === 5. Network TCP throughput ===
echo "[5/8] Network iperf3 TCP (15s) naar $HOST_IP..."
iperf3 -c "$HOST_IP" -t 15 -J > "$RES_DIR/network_tcp.json"

# === 6. Network UDP latency/jitter ===
echo "[6/8] Network iperf3 UDP (15s)..."
iperf3 -c "$HOST_IP" -t 15 -u -b 100M -J > "$RES_DIR/network_udp.json"

# === 7. Webserver workload (wrk) ===
echo "[7/8] Webserver wrk (statisch + dynamisch, 30s elk)..."
wrk -t2 -c50 -d30s --latency http://localhost/statisch.html \
    > "$RES_DIR/web_static.txt"
wrk -t2 -c50 -d30s --latency http://localhost/dynamisch.php \
    > "$RES_DIR/web_dynamic.txt"
wrk -t2 -c50 -d30s --latency http://localhost:8080/statisch.html \
    > "$RES_DIR/web_proxy.txt"

# === 8. Database workload (sysbench OLTP) ===
echo "[8/8] DB sysbench oltp_read_write (60s)..."
drop_caches
sysbench oltp_read_write \
    --db-driver=mysql --mysql-user=vic_tester --mysql-password=geheim123 \
    --mysql-db=sbtest --tables=4 --table-size=10000 \
    --threads=4 --time=60 run > "$RES_DIR/db_oltp.txt"

# Run-eindtijd
echo "end=$(date -Is)" >> "$RES_DIR/meta.txt"
echo "============================================="
echo "RUN $RUN klaar. Bestanden: $RES_DIR"
echo "Volgende stap: kopieer $RES_DIR via scp naar je laptop,"
echo "DAN snapshot rollback in Proxmox web-UI."
echo "============================================="
