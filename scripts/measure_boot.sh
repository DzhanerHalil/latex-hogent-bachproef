#!/bin/bash
# measure_boot.sh - VIC BP - meet opstarttijd tot service ready
# Draait OP de Proxmox HOST. Gebruik: ./measure_boot.sh <qm|pct> <id> <ip> <run> <type-label>
set -euo pipefail

if [ "$#" -ne 5 ]; then
    cat <<EOF
Gebruik: $0 <type> <id> <ip> <run> <label>
  type:  qm | pct
  id:    Proxmox VM/CT ID
  ip:    IP-adres dat de webserver host
  run:   1..N (run-nummer)
  label: vrije tekst, bv. "VM_pmx8" of "LXC_pmx9"
Voorbeeld: $0 qm 100 10.0.110.1 1 VM_pmx8
EOF
    exit 1
fi

TYPE="$1"; ID="$2"; IP="$3"; RUN="$4"; LABEL="$5"
CSV=/root/boot_results.csv
TIMEOUT=120  # seconden — bail-out als service nooit komt

# Header schrijven indien nog niet bestaat
if [ ! -f "$CSV" ]; then
    echo "timestamp,run,label,type,id,ip,boot_seconds,status" > "$CSV"
fi

echo "[$(date -Is)] $LABEL run=$RUN — stop instance $ID..."
case "$TYPE" in
    qm)  qm stop "$ID" 2>/dev/null || true; qm wait "$ID" --timeout 60 2>/dev/null || true ;;
    pct) pct stop "$ID" 2>/dev/null || true ;;
    *)   echo "Type moet 'qm' of 'pct' zijn"; exit 1 ;;
esac
sleep 3

echo "[$(date -Is)] Start instance $ID, stopwatch aan..."
START=$(date +%s.%N)
case "$TYPE" in
    qm)  qm start "$ID" ;;
    pct) pct start "$ID" ;;
esac

# Poll http elke 100ms tot 200 OF timeout
STATUS="timeout"
DEADLINE=$(echo "$START + $TIMEOUT" | bc -l)
while (( $(echo "$(date +%s.%N) < $DEADLINE" | bc -l) )); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 "http://${IP}/statisch.html" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        STATUS="ok"
        END=$(date +%s.%N)
        break
    fi
    sleep 0.1
done

if [ "$STATUS" = "timeout" ]; then
    ELAPSED="NA"
else
    ELAPSED=$(echo "$END - $START" | bc -l)
fi

echo "$(date -Is),$RUN,$LABEL,$TYPE,$ID,$IP,$ELAPSED,$STATUS" >> "$CSV"
echo "[$(date -Is)] $LABEL run=$RUN: status=$STATUS, elapsed=${ELAPSED}s"
echo "CSV: $CSV"
