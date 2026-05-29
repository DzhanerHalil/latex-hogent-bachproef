#!/bin/bash
# pull_results.sh - haal /root/test_results/run_X uit guest naar host
# Gebruik: ./pull_results.sh <qm|pct> <id> <run> <local_dir>
set -euo pipefail
TYPE="$1"; ID="$2"; RUN="$3"; DEST="$4"
mkdir -p "$DEST"
case "$TYPE" in
  pct)
    pct exec "$ID" -- bash -c "tar czf /tmp/run_${RUN}.tar.gz -C /root/test_results run_${RUN}"
    pct pull "$ID" "/tmp/run_${RUN}.tar.gz" "$DEST/run_${RUN}.tar.gz"
    pct exec "$ID" -- rm -f "/tmp/run_${RUN}.tar.gz"
    ;;
  qm)
    qm guest exec "$ID" --timeout 60 -- bash -c \
      "tar czf /tmp/run_${RUN}.tar.gz -C /root/test_results run_${RUN}"
    qm guest exec "$ID" --timeout 120 -- bash -c "base64 -w0 /tmp/run_${RUN}.tar.gz" \
      | jq -r '."out-data"' | base64 -d > "$DEST/run_${RUN}.tar.gz"
    qm guest exec "$ID" --timeout 30 -- rm -f "/tmp/run_${RUN}.tar.gz"
    ;;
esac
tar xzf "$DEST/run_${RUN}.tar.gz" -C "$DEST/"
echo "✓ Run $RUN binnen in: $DEST/run_${RUN}/"
ls "$DEST/run_${RUN}/" | wc -l
