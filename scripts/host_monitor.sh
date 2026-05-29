#!/bin/bash
# host_monitor.sh - draait op Proxmox host parallel aan guest-bench
RUN="${1:?run-nummer}"; LABEL="${2:?label}"
DIR="/root/host_metrics/${LABEL}_run${RUN}"
mkdir -p "$DIR"

# 5-minuten capture, 5s interval
iostat -xkdz 5 60 > "$DIR/iostat.txt" &
vmstat 5 60      > "$DIR/vmstat.txt" &
mpstat -P ALL 5 60 > "$DIR/mpstat.txt" &
pidstat -urd 5 60  > "$DIR/pidstat.txt" &
wait
echo "Host metrics in $DIR"
