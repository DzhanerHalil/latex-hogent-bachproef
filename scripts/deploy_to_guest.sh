#!/bin/bash
# deploy_to_guest.sh - push een script naar een VM/LXC en draai het
# Gebruik: ./deploy_to_guest.sh <qm|pct> <id> <pad-naar-script>
set -euo pipefail
TYPE="$1"; ID="$2"; SCRIPT="$3"
NAME=$(basename "$SCRIPT")
echo ">>> [$TYPE $ID] push $NAME"
case "$TYPE" in
  pct)
    pct push "$ID" "$SCRIPT" "/root/$NAME"
    pct exec "$ID" -- chmod +x "/root/$NAME"
    echo ">>> [$TYPE $ID] running $NAME (live output)..."
    pct exec "$ID" -- "/root/$NAME"
    ;;
  qm)
    B64=$(base64 -w0 "$SCRIPT")
    qm guest exec "$ID" --timeout 60 -- bash -c \
      "echo '$B64' | base64 -d > /root/$NAME && chmod +x /root/$NAME"
    echo ">>> [$TYPE $ID] running $NAME (output buffered tot klaar)..."
    qm guest exec "$ID" --timeout 1800 -- "/root/$NAME"
    ;;
  *) echo "type moet 'qm' of 'pct' zijn"; exit 1 ;;
esac
echo ">>> [$TYPE $ID] DONE"
