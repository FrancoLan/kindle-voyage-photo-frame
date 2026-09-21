#!/bin/sh

KINDLE_ROOT=${KINDLE_ROOT:-/mnt/us}
MANAGER_DIR=${MANAGER_DIR:-$KINDLE_ROOT/kindle-manager}
STATE_DIR="$MANAGER_DIR/state"
mkdir -p "$STATE_DIR"
SUPERVISOR_LOCK="$STATE_DIR/supervisor.lock"
if ! mkdir "$SUPERVISOR_LOCK" 2>/dev/null; then
    existing_pid=$(cat "$STATE_DIR/supervisor.pid" 2>/dev/null || true)
    if [ -n "$existing_pid" ] && [ -r "/proc/$existing_pid/cmdline" ] && tr '\000' ' ' < "/proc/$existing_pid/cmdline" | grep -q "$MANAGER_DIR/supervisor.sh"; then
        exit 0
    fi
    rm -rf "$SUPERVISOR_LOCK"
    mkdir "$SUPERVISOR_LOCK" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" > "$STATE_DIR/supervisor.pid"
cleanup() {
    rm -f "$STATE_DIR/supervisor.pid"
    rmdir "$SUPERVISOR_LOCK" 2>/dev/null || true
}
trap 'cleanup' EXIT
trap 'exit 0' HUP INT TERM

while :; do
    env KINDLE_ROOT="$KINDLE_ROOT" MANAGER_DIR="$MANAGER_DIR" sh "$MANAGER_DIR/manager.sh" >> "$STATE_DIR/manager.log" 2>&1
    code=$?
    printf '%s manager exited with code %s; restarting in 10 seconds\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$code" >> "$STATE_DIR/supervisor.log"
    sleep 10
done
