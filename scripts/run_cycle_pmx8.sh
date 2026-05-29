#!/bin/bash
set -euo pipefail
N="${1:?args: <run-nummer>}"
echo "═══ CYCLUS $N — pmx8 ═══ $(date -Is)"
/root/bp/scripts/run_iteration.sh qm  100 "$N" vm-pmx8  10.0.10.110
/root/bp/scripts/run_iteration.sh pct 101 "$N" lxc-pmx8 10.0.10.110
echo "─── disk-druk na cyclus $N ───"
pvs && lvs -o lv_name,lv_size,data_percent | head -10
