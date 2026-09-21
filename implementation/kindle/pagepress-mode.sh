#!/bin/sh
set -u
. /mnt/us/kindle-photoframe/config.sh
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/pagepress-mode.log"
# Voyage control interface used by KOReader PR #10290.
for prop in fsrkeypadEnable fsrkeypadNextEnable fsrkeypadPrevEnable; do
    saved="$STATE_DIR/$prop.previous"
    case "${1:-}" in
        enable)
            if [ ! -f "$saved" ]; then
                value=$(lipc-get-prop com.lab126.deviced "$prop" 2>> "$LOG") || continue
                case "$value" in 0|1) printf '%s\n' "$value" > "$saved" ;; *) echo "Unexpected $prop: $value" >> "$LOG"; continue ;; esac
                echo "$prop before=$value" >> "$LOG"
            fi
            lipc-set-prop -i com.lab126.deviced "$prop" 1 >> "$LOG" 2>&1 || continue
            value=$(lipc-get-prop com.lab126.deviced "$prop" 2>> "$LOG")
            echo "$prop enabled=$value" >> "$LOG"
            ;;
        restore)
            [ -f "$saved" ] || continue
            value=$(cat "$saved")
            case "$value" in 0|1) ;; *) continue ;; esac
            if lipc-set-prop -i com.lab126.deviced "$prop" "$value" >> "$LOG" 2>&1; then
                echo "$prop restored=$value" >> "$LOG"
                rm -f "$saved"
            fi
            ;;
    esac
done
