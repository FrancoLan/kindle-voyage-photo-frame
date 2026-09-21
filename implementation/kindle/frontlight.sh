#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh
mkdir -p "$STATE_DIR"

valid_intensity() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge 0 ] && [ "$1" -le 24 ]
}

save_settings() {
    [ -f "$STATE_DIR/frontlight-settings-saved" ] && return 0
    intensity=$(lipc-get-prop -i com.lab126.powerd flIntensity 2>/dev/null || true)
    auto=$(lipc-get-prop -i com.lab126.powerd flAuto 2>/dev/null || true)
    valid_intensity "$intensity" && printf '%s\n' "$intensity" > "$STATE_DIR/frontlight-intensity.previous"
    case "$auto" in 0|1) printf '%s\n' "$auto" > "$STATE_DIR/frontlight-auto.previous" ;; esac
    touch "$STATE_DIR/frontlight-settings-saved"
}

apply_schedule() {
    save_settings
    hour=$(date +%H)
    hour=${hour#0}
    [ -n "$hour" ] || hour=0
    if [ "$hour" -ge "$DAY_START_HOUR" ] && [ "$hour" -lt "$NIGHT_START_HOUR" ]; then
        current=$(lipc-get-prop -i com.lab126.powerd flIntensity 2>/dev/null || true)
        if [ "$current" = 0 ]; then
            target=$DAY_FRONTLIGHT_LEVEL
            if [ -f "$STATE_DIR/frontlight-intensity.previous" ]; then
                previous=$(cat "$STATE_DIR/frontlight-intensity.previous" 2>/dev/null || true)
                if valid_intensity "$previous" && [ "$previous" -gt 0 ]; then target=$previous; fi
            fi
            lipc-set-prop -i com.lab126.powerd flIntensity "$target" >/dev/null 2>&1 || true
        fi
        lipc-set-prop -i com.lab126.powerd flAuto 1 >/dev/null 2>&1 || true
        target=auto
        period=day
    else
        lipc-set-prop -i com.lab126.powerd flAuto 0 >/dev/null 2>&1 || true
        target=0
        period=night
        current=$(lipc-get-prop -i com.lab126.powerd flIntensity 2>/dev/null || true)
        if [ "$current" != 0 ]; then
            lipc-set-prop -i com.lab126.powerd flIntensity 0 >/dev/null 2>&1 || true
        fi
    fi
    printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$period" "$target" > "$STATE_DIR/frontlight-status.tsv"
}

restore_settings() {
    if [ -f "$STATE_DIR/frontlight-intensity.previous" ]; then
        intensity=$(cat "$STATE_DIR/frontlight-intensity.previous" 2>/dev/null || true)
        valid_intensity "$intensity" && lipc-set-prop -i com.lab126.powerd flIntensity "$intensity" >/dev/null 2>&1 || true
    fi
    if [ -f "$STATE_DIR/frontlight-auto.previous" ]; then
        auto=$(cat "$STATE_DIR/frontlight-auto.previous" 2>/dev/null || true)
        case "$auto" in 0|1) lipc-set-prop -i com.lab126.powerd flAuto "$auto" >/dev/null 2>&1 || true ;; esac
    fi
    rm -f "$STATE_DIR/frontlight-settings-saved" "$STATE_DIR/frontlight-intensity.previous" "$STATE_DIR/frontlight-auto.previous" "$STATE_DIR/frontlight-status.tsv"
}

case "${1:-}" in
    save) save_settings ;;
    apply) apply_schedule ;;
    restore) restore_settings ;;
    watch)
        trap 'exit 0' HUP INT TERM
        while :; do
            apply_schedule
            sleep "$FRONTLIGHT_CHECK_SECONDS"
        done
        ;;
    *) echo "usage: frontlight.sh save|apply|restore|watch" >&2; exit 2 ;;
esac
