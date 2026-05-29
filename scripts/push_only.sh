#!/bin/bash
set -euo pipefail
TYPE="$1"; ID="$2"; SCRIPT="$3"; NAME=$(basename "$SCRIPT")
case "$TYPE" in
  pct) pct push "$ID" "$SCRIPT" "/root/$NAME" && pct exec "$ID" -- chmod +x "/root/$NAME" ;;
  qm)
    B64=$(base64 -w0 "$SCRIPT")
    qm guest exec "$ID" --timeout 60 -- bash -c "echo '$B64' | base64 -d > /root/$NAME && chmod +x /root/$NAME"
    ;;
esac
echo "Pushed $NAME naar $TYPE $ID"
