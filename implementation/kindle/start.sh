#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh
mkdir -p "$STATE_DIR"

if [ -f /mnt/us/kindle-manager/restart-required ]; then
    # The updater invokes this script before its parent can record completion.
    # Persist the current command first so the replacement manager does not
    # execute the same update again after the old manager is terminated.
    command_id=$(sed -n 's/^id	//p' /mnt/us/kindle-manager/state/command.tsv 2>/dev/null | head -n 1)
    if echo "$command_id" | grep -Eq '^[a-f0-9-]{36}$'; then
        printf '%s\n' "$command_id" > /mnt/us/kindle-manager/state/last-command-id
    fi
    for process_dir in /proc/[0-9]*; do
        [ -r "$process_dir/cmdline" ] || continue
        if tr '\000' ' ' < "$process_dir/cmdline" | grep -q '/mnt/us/kindle-manager/'; then
            process_pid=${process_dir#/proc/}
            [ "$process_pid" = "$$" ] || kill "$process_pid" 2>/dev/null || true
        fi
    done
    rm -f /mnt/us/kindle-manager/state/manager.pid /mnt/us/kindle-manager/state/supervisor.pid
    rm -rf /mnt/us/kindle-manager/state/manager.lock /mnt/us/kindle-manager/state/supervisor.lock
    rm -f /mnt/us/kindle-manager/restart-required
    sleep 2
fi

if [ -f /mnt/us/kindle-manager/start.sh ]; then
    sh /mnt/us/kindle-manager/start.sh >/dev/null 2>&1 || true
fi

if [ -f "$STATE_DIR/player.pid" ]; then
    pid=$(cat "$STATE_DIR/player.pid" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "Photoframe is already running as PID $pid."
        exit 0
    fi
    rm -f "$STATE_DIR/player.pid"
    rmdir "$STATE_DIR/player.lock" 2>/dev/null || true
fi

rm -f "$BASE_DIR/disabled"
killall kindle-xcontrols kindle-evgrab-cat >/dev/null 2>&1 || true
sleep 1
nohup sh /mnt/us/kindle-photoframe/player.sh > "$STATE_DIR/player.log" 2>&1 &
echo "Photoframe start requested."
