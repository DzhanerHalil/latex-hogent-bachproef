#!/bin/bash
# run_iteration.sh - één BP benchmark iteratie
# Gebruik: ./run_iteration.sh <qm|pct> <id> <run#> <label> <host_ip>
set -euo pipefail

if [ $# -ne 5 ]; then
  echo "args: <qm|pct> <id> <run#> <label> <host_ip>"; exit 1
fi
TYPE="$1"; ID="$2"; RUN="$3"; LABEL="$4"; HOST_IP="$5"
RES_BASE="/root/bp/results/${LABEL}"
HM_BASE="/root/bp/host_metrics/${LABEL}"
mkdir -p "$RES_BASE" "$HM_BASE"

echo "═══════════════════════════════════════"
echo " $LABEL run=$RUN  ($TYPE $ID @ $(date -Is))"
echo "═══════════════════════════════════════"

# 1. Rollback
echo "[1/5] rollback baseline"
case "$TYPE" in
  qm)  qm  rollback "$ID" baseline ;;
  pct) pct rollback "$ID" baseline ;;
esac

# 2. Start + warmup
echo "[2/5] start $TYPE $ID + 30s warmup"
case "$TYPE" in
  qm)  qm  start "$ID" ;;
  pct) pct start "$ID" ;;
esac
sleep 30

# 3. Host-monitor parallel — 10 min coverage (120 samples × 5s)
echo "[3/5] host-monitor in achtergrond"
HM_DIR="$HM_BASE/run_${RUN}"
mkdir -p "$HM_DIR"
iostat  -xkdz 5 120 > "$HM_DIR/iostat.txt"   &
vmstat            5 120 > "$HM_DIR/vmstat.txt"   &
mpstat  -P ALL    5 120 > "$HM_DIR/mpstat.txt"  &

# 4. Benchmark in guest (blokkeert tot klaar)
echo "[4/5] benchmark in guest"
START_TS=$(date +%s)
case "$TYPE" in
  qm)
    qm guest exec "$ID" --timeout 1200 -- /root/run_benchmarks.sh "$RUN" "$HOST_IP" \
      > "$RES_BASE/run_${RUN}_log.json" 2>&1
    ;;
  pct)
    pct exec "$ID" -- /root/run_benchmarks.sh "$RUN" "$HOST_IP" \
      > "$RES_BASE/run_${RUN}_log.txt" 2>&1
    ;;
esac
END_TS=$(date +%s)
echo "     benchmark duur: $((END_TS-START_TS))s"

# 5. Wacht op host-monitor af, dan pull + stop
echo "[5/5] wait monitors / pull / stop"
wait
/root/bp/scripts/pull_results.sh "$TYPE" "$ID" "$RUN" "$RES_BASE"
case "$TYPE" in
  qm)  qm  stop "$ID" ;;
  pct) pct stop "$ID" ;;
esac
sleep 5

echo "✓ DONE  results=$RES_BASE/run_$RUN/  host=$HM_DIR/"
