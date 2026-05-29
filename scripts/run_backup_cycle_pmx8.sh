#!/bin/bash
set -euo pipefail
echo "═══ BACKUP-CYCLUS pve8 START $(date -Is) ═══"
COUNT=0
for SIZE in 5 12; do
  for RUN in 1 2 3; do
    /root/bp/scripts/run_backup_iteration.sh qm  100 vm-pmx8  $SIZE $RUN
    /root/bp/scripts/run_backup_iteration.sh pct 101 lxc-pmx8 $SIZE $RUN
    COUNT=$((COUNT + 2))
    if [ $((COUNT % 4)) -eq 0 ]; then
      echo "─── trigger PBS garbage collection (na $COUNT iteraties) ───"
      ssh -o StrictHostKeyChecking=no root@10.0.10.115 \
        'proxmox-backup-manager garbage-collection start bp-store' || true
      sleep 30
    fi
  done
done
echo "═══ BACKUP-CYCLUS pve8 KLAAR $(date -Is) ═══"
pvs && lvs -o lv_name,lv_size,data_percent | head -10
