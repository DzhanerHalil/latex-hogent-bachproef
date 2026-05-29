#!/bin/bash
set -euo pipefail
N="${1:?args: <run-nummer>}"
echo "═══ CYCLUS $N — pmx9 ═══ $(date -Is)"
/root/bp/scripts/run_iteration.sh qm  200 "$N" vm-pmx9  10.0.10.111
/root/bp/scripts/run_iteration.sh pct 201 "$N" lxc-pmx9 10.0.10.111
echo "─── disk-druk na cyclus $N ───"
pvs && lvs -o lv_name,lv_size,data_percent | head -10
