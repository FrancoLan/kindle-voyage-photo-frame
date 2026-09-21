#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh

DIAG_DIR="$STATE_DIR/button-diagnostics"
mkdir -p "$DIAG_DIR"
rm -f "$DIAG_DIR"/*.log "$DIAG_DIR"/complete

date > "$DIAG_DIR/started.log"

if command -v xset >/dev/null 2>&1; then
    xset r off >> "$DIAG_DIR/xset.log" 2>&1 || true
fi

lipc-wait-event -m -s 25 -t com.lab126.appmgrd '*' > "$DIAG_DIR/lipc-appmgrd.log" 2>&1 &
lipc_pid=$!

reader_pids=
for event_path in /dev/input/event*; do
    [ -r "$event_path" ] || continue
    event_name=$(basename "$event_path")
    sys_name=$(cat "/sys/class/input/$event_name/device/name" 2>/dev/null || printf unknown)
    printf '%s\t%s\n' "$event_path" "$sys_name" >> "$DIAG_DIR/devices.log"
    (
        while true; do
            dd if="$event_path" bs=16 count=1 2>/dev/null | od -An -tu2
        done
    ) > "$DIAG_DIR/$event_name.log" 2>&1 &
    reader_pids="$reader_pids $!"
done

sleep 25
kill "$lipc_pid" $reader_pids 2>/dev/null || true
wait "$lipc_pid" 2>/dev/null || true
for reader_pid in $reader_pids; do
    wait "$reader_pid" 2>/dev/null || true
done
date > "$DIAG_DIR/complete"
