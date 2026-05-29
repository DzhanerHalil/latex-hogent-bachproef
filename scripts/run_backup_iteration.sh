#!/bin/bash
# run_backup_iteration.sh - 1 iteratie: rollback → start → load data → full → incr → restore → cleanup
# Gebruik: ./run_backup_iteration.sh <qm|pct> <id> <label> <size_gb> <run>
set -euo pipefail

[ $# -eq 5 ] || { echo "args: <qm|pct> <id> <label> <size_gb> <run>"; exit 1; }
TYPE="$1"; ID="$2"; LABEL="$3"; SIZE_GB="$4"; RUN="$5"
PBS_STORAGE="pbs-bp"
RESTORE_ID=$((ID + 500))
CSV=/root/bp/backup_results.csv

mkdir -p /root/bp
[ -f "$CSV" ] || echo "ts,run,label,size_gb,phase,seconds,size" > "$CSV"

t0(){ date +%s.%N; }
dt(){ echo "$2 - $1" | bc -l; }

echo "════ $LABEL ${SIZE_GB}GB run=$RUN @ $(date -Is) ════"

# 1. Rollback
echo "[1/7] rollback baseline"
case "$TYPE" in
  qm)  qm  rollback "$ID" baseline ;;
  pct) pct rollback "$ID" baseline ;;
esac

# 2. Start
echo "[2/7] start"
case "$TYPE" in
  qm)  qm  start "$ID"; sleep 60 ;;
  pct) pct start "$ID"; sleep 5 ;;
esac

# 3. Genereer data
echo "[3/7] genereer ${SIZE_GB}GB urandom data"
GEN="mkdir -p /payload && dd if=/dev/urandom of=/payload/data.bin bs=1M count=$((SIZE_GB*1024)) status=none && sync && du -h /payload/data.bin"
case "$TYPE" in
  qm)  qm guest exec "$ID" --timeout 900 -- bash -c "$GEN" ;;
  pct) pct exec "$ID" -- bash -c "$GEN" ;;
esac

# 4. FULL backup
echo "[4/7] FULL backup"
S=$(t0)
vzdump "$ID" --mode snapshot --storage "$PBS_STORAGE" --compress zstd \
  --notes-template "BP $LABEL ${SIZE_GB}GB run=$RUN full" \
  > /tmp/vzdump_full.log 2>&1
E=$(t0)
SF=$(grep -oE 'transferred [0-9.]+ [KMG]iB' /tmp/vzdump_full.log | tail -1 | awk '{print $2$3}' || echo NA)
TF=$(dt $S $E)
echo "$(date -Is),$RUN,$LABEL,$SIZE_GB,full,$TF,$SF" >> "$CSV"
echo "  full: ${TF}s  size=$SF"

# 5. Delta + INCREMENTAL backup
echo "[5/7] delta + incremental backup"
DELTA="dd if=/dev/urandom of=/payload/delta.bin bs=1M count=100 status=none && sync"
case "$TYPE" in
  qm)  qm guest exec "$ID" --timeout 60 -- bash -c "$DELTA" ;;
  pct) pct exec "$ID" -- bash -c "$DELTA" ;;
esac
S=$(t0)
vzdump "$ID" --mode snapshot --storage "$PBS_STORAGE" --compress zstd \
  --notes-template "BP $LABEL ${SIZE_GB}GB run=$RUN incr" \
  > /tmp/vzdump_incr.log 2>&1
E=$(t0)
SI=$(grep -oE 'transferred [0-9.]+ [KMG]iB' /tmp/vzdump_incr.log | tail -1 | awk '{print $2$3}' || echo NA)
TI=$(dt $S $E)
echo "$(date -Is),$RUN,$LABEL,$SIZE_GB,incremental,$TI,$SI" >> "$CSV"
echo "  incr: ${TI}s  size=$SI"

# 6. RESTORE (laatste backup)
echo "[6/7] restore naar ID $RESTORE_ID"
LATEST=$(pvesm list "$PBS_STORAGE" --vmid "$ID" | tail -1 | awk '{print $1}')
S=$(t0)
case "$TYPE" in
  qm)  qmrestore   "$LATEST" "$RESTORE_ID" --storage local-lvm > /tmp/restore.log 2>&1 ;;
  pct) pct restore "$RESTORE_ID" "$LATEST" --storage local-lvm > /tmp/restore.log 2>&1 ;;
esac
E=$(t0)
TR=$(dt $S $E)
echo "$(date -Is),$RUN,$LABEL,$SIZE_GB,restore,$TR,NA" >> "$CSV"
echo "  restore: ${TR}s"

# 7. Cleanup
echo "[7/7] cleanup"
case "$TYPE" in
  qm)  qm  destroy "$RESTORE_ID" --purge 2>/dev/null || true; qm  stop "$ID" ;;
  pct) pct destroy "$RESTORE_ID" --purge 2>/dev/null || true; pct stop "$ID" ;;
esac
sleep 5
echo "✓ DONE"
# 8. Prune PBS snapshots voor deze VMID (free space)
echo "[8/8] PBS prune"
for VOLID in $(pvesm list "$PBS_STORAGE" --vmid "$ID" 2>/dev/null | awk 'NR>1 {print $1}'); do
  pvesm free "$VOLID" 2>/dev/null || true
done
