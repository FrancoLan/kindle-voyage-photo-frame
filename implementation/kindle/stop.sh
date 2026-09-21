#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh
mkdir -p "$STATE_DIR"
touch "$BASE_DIR/disabled"
killall kindle-xcontrols kindle-evgrab-cat >/dev/null 2>&1 || true

if [ -f "$STATE_DIR/buttons.pid" ]; then
    buttons_pid=$(cat "$STATE_DIR/buttons.pid" 2>/dev/null || true)
    if [ -n "$buttons_pid" ]; then
        kill "$buttons_pid" 2>/dev/null || true
    fi
fi

if [ -f "$STATE_DIR/player.pid" ]; then
    pid=$(cat "$STATE_DIR/player.pid" 2>/dev/null || true)
    if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' < "/proc/$pid/cmdline" | grep -q '/mnt/us/kindle-photoframe/player.sh'; then
        kill "$pid" 2>/dev/null || true
    fi
fi
sleep 1
/mnt/us/kindle-photoframe/restore-ui.sh >/dev/null 2>&1 || true
rm -f "$STATE_DIR/player.pid"
rm -f "$STATE_DIR/buttons.pid" "$STATE_DIR/navigation-command" "$STATE_DIR/exit-requested" "$STATE_DIR/touch-command" "$STATE_DIR/sync-complete" "$STATE_DIR/controls-ready" "$STATE_DIR/photo-controls-armed"
rmdir "$STATE_DIR/player.lock" 2>/dev/null || true
echo "Kindle photoframe disabled."
