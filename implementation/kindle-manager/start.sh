#!/bin/sh

KINDLE_ROOT=${KINDLE_ROOT:-/mnt/us}
MANAGER_DIR=${MANAGER_DIR:-$KINDLE_ROOT/kindle-manager}
STATE_DIR="$MANAGER_DIR/state"
mkdir -p "$STATE_DIR"
if [ -f "$STATE_DIR/supervisor.pid" ]; then
    pid=$(cat "$STATE_DIR/supervisor.pid" 2>/dev/null || true)
    if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' < "/proc/$pid/cmdline" | grep -q "$MANAGER_DIR/supervisor.sh"; then
        exit 0
    fi
    rm -f "$STATE_DIR/supervisor.pid"
fi
nohup env KINDLE_ROOT="$KINDLE_ROOT" MANAGER_DIR="$MANAGER_DIR" sh "$MANAGER_DIR/supervisor.sh" > "$STATE_DIR/supervisor.log" 2>&1 &
