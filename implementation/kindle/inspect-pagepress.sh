#!/bin/sh
# Read-only firmware/input capability snapshot; does not enter frame mode.
set -u
BASE_DIR=/mnt/us/kindle-photoframe
OUT="$BASE_DIR/state/pagepress-firmware.log"
mkdir -p "$BASE_DIR/state"
exec > "$OUT" 2>&1
date
echo 'Application PagePress capability flags:'
if [ -r /var/local/appreg.db ] && command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 /var/local/appreg.db '.dump properties' | grep -E 'whisper|grip|shell_integration'
fi
echo 'Window manager property inventory:'
lipc-probe -v com.lab126.winmgr
echo 'Input device inventory and sysfs attribute names:'
for input in /sys/class/input/event*; do
    echo "$input"
    cat "$input/device/name"
    ls -l "$input/device/"
done
echo 'FSR driver attribute inventory:'
find /sys/devices -iname '*fsr*' -print 2>/dev/null | while IFS= read -r node; do
    [ -d "$node" ] || continue
    ls -l "$node/"
    for attr in enable enabled state mode keymap key_mask keymask buttons button_mask; do
        [ ! -r "$node/$attr" ] || { echo "$node/$attr"; cat "$node/$attr"; }
    done
done
echo 'SNAPSHOT COMPLETE'
