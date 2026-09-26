#!/bin/sh

set -u
CONFIG_PATH=${KINDLE_PHOTOFRAME_CONFIG:-/mnt/us/kindle-photoframe/config.sh}
. "$CONFIG_PATH"
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

valid_lux() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge 0 ]
}

set_frontlight() {
    value=$1
    lipc-set-prop -i com.lab126.powerd flIntensity "$value" >/dev/null 2>&1 || true
}

restore_automatic_frontlight() {
    current=$(lipc-get-prop -i com.lab126.powerd flIntensity 2>/dev/null || true)
    if [ -f "$STATE_DIR/frontlight-forced-off" ] || [ "$current" = 0 ]; then
        level=$FRONTLIGHT_DEFAULT_LEVEL
        if [ -f "$STATE_DIR/frontlight-intensity.previous" ]; then
            previous=$(cat "$STATE_DIR/frontlight-intensity.previous" 2>/dev/null || true)
            if valid_intensity "$previous" && [ "$previous" -gt 0 ]; then level=$previous; fi
        fi
        set_frontlight "$level"
    fi
    lipc-set-prop -i com.lab126.powerd flAuto 1 >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/frontlight-forced-off"
}

stop_stale_watchers() {
    this_pid=$$
    for process_dir in /proc/[0-9]*; do
        [ -r "$process_dir/cmdline" ] || continue
        pid=${process_dir#/proc/}
        [ "$pid" != "$this_pid" ] || continue
        cmdline=$(tr '\000' ' ' < "$process_dir/cmdline" 2>/dev/null || true)
        case "$cmdline" in
            *"/mnt/us/kindle-photoframe/frontlight.sh watch"*) kill "$pid" 2>/dev/null || true ;;
        esac
    done
}

apply_sensor_policy() {
    save_settings
    lux=$(lipc-get-prop -i com.lab126.powerd alsLux 2>/dev/null || true)
    if ! valid_lux "$lux"; then
        printf '%s\tunknown\t%s\tunavailable\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$lux" > "$STATE_DIR/frontlight-status.tsv"
        return 0
    fi

    if [ "$lux" -le "$FRONTLIGHT_DARK_LUX" ]; then
        lipc-set-prop -i com.lab126.powerd flAuto 0 >/dev/null 2>&1 || true
        set_frontlight 0
        touch "$STATE_DIR/frontlight-forced-off"
        condition=dark
        target=0
    elif [ "$lux" -ge "$FRONTLIGHT_BRIGHT_LUX" ]; then
        restore_automatic_frontlight
        condition=bright
        target=auto
    else
        if [ -f "$STATE_DIR/frontlight-forced-off" ]; then
            condition=hold-off
            target=0
        else
            restore_automatic_frontlight
            condition=hold-auto
            target=auto
        fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$condition" "$lux" "$target" > "$STATE_DIR/frontlight-status.tsv"
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
    rm -f "$STATE_DIR/frontlight-settings-saved" "$STATE_DIR/frontlight-intensity.previous" "$STATE_DIR/frontlight-auto.previous" "$STATE_DIR/frontlight-forced-off" "$STATE_DIR/frontlight-status.tsv"
}

case "${1:-}" in
    save) save_settings ;;
    apply) apply_sensor_policy ;;
    restore) restore_settings ;;
    watch)
        trap 'exit 0' HUP INT TERM
        stop_stale_watchers
        while :; do
            apply_sensor_policy
            sleep "$FRONTLIGHT_CHECK_SECONDS"
        done
        ;;
    *) echo "usage: frontlight.sh save|apply|restore|watch" >&2; exit 2 ;;
esac
