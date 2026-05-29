#!/bin/bash
set -euo pipefail
echo "═══ RESUME pve8 12GB START $(date -Is) ═══"
for RUN in 1 2 3; do
  /root/bp/scripts/run_backup_iteration.sh qm  100 vm-pmx8  12 $RUN
  /root/bp/scripts/run_backup_iteration.sh pct 101 lxc-pmx8 12 $RUN
  echo "─── PBS GC na 12GB run $RUN ───"
  ssh -o StrictHostKeyChecking=no root@10.0.10.115 \
    'proxmox-backup-manager garbage-collection start bp-store' || true
  sleep 30
done
echo "═══ RESUME pve8 12GB KLAAR $(date -Is) ═══"
pvs && lvs -o lv_name,data_percent | head -5
