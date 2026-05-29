#!/bin/bash
# pull_security.sh - haal /root/security_results/$LABEL uit guest
# Gebruik: ./pull_security.sh <qm|pct> <id> <label> <local_dest>
set -euo pipefail
TYPE="$1"; ID="$2"; LABEL="$3"; DEST="$4"
mkdir -p "$DEST"
case "$TYPE" in
  pct)
    pct exec "$ID" -- bash -c "tar czf /tmp/sec.tar.gz -C /root/security_results $LABEL"
    pct pull "$ID" "/tmp/sec.tar.gz" "$DEST/${LABEL}.tar.gz"
    pct exec "$ID" -- rm -f /tmp/sec.tar.gz
    ;;
  qm)
    qm guest exec "$ID" --timeout 60 -- bash -c "tar czf /tmp/sec.tar.gz -C /root/security_results $LABEL"
    qm guest exec "$ID" --timeout 60 -- bash -c "base64 -w0 /tmp/sec.tar.gz" \
      | jq -r '."out-data"' | base64 -d > "$DEST/${LABEL}.tar.gz"
    qm guest exec "$ID" --timeout 30 -- rm -f /tmp/sec.tar.gz
    ;;
esac
tar xzf "$DEST/${LABEL}.tar.gz" -C "$DEST/"
echo "✓ Security $LABEL: $DEST/${LABEL}/"
ls "$DEST/${LABEL}/" 2>/dev/null
