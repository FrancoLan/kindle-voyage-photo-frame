#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh

COMMAND_FILE="$STATE_DIR/navigation-command"
EXIT_FILE="$STATE_DIR/exit-requested"
TOUCH_FILE="$STATE_DIR/touch-command"
READY_FILE="$STATE_DIR/controls-ready"
ARMED_FILE="$STATE_DIR/photo-controls-armed"
CONTROL_FIFO="/var/tmp/kindle-photoframe-controls.$$"
mkdir -p "$STATE_DIR"
rm -f "$READY_FILE" "$CONTROL_FIFO"

send_navigation() {
    command=$1
    [ ! -f "$EXIT_FILE" ] || return 0
    temp="$COMMAND_FILE.tmp.$command"
    printf '%s\n' "$command" > "$temp"
    mv "$temp" "$COMMAND_FILE"
}

send_exit() {
    touch "$EXIT_FILE"
    rm -f "$COMMAND_FILE" "$TOUCH_FILE"
}

send_touch() {
    touch_side=$1
    [ ! -f "$EXIT_FILE" ] || return 0
    temp="$TOUCH_FILE.tmp.$touch_side"
    printf '%s\n' "$touch_side" > "$temp"
    mv "$temp" "$TOUCH_FILE"
}

find_input_device() {
    wanted_name=$1
    for candidate in /dev/input/event*; do
        [ -r "$candidate" ] || continue
        candidate_name=$(basename "$candidate")
        device_name=$(cat "/sys/class/input/$candidate_name/device/name" 2>/dev/null || true)
        if [ "$device_name" = "$wanted_name" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

read_power_events() {
    event_path=$1
    echo "power listener using $event_path."
    while [ ! -f "$BASE_DIR/disabled" ]; do
        event_words=$(dd if="$event_path" bs=16 count=1 2>/dev/null | od -An -tu2)
        set -- $event_words
        [ "$#" -ge 7 ] || continue
        [ "$5" = 1 ] || continue
        [ "$7" = 1 ] || continue
        case " $EXIT_KEY_CODES " in
            *" $6 "*) send_exit; echo "power $6: exit" ;;
        esac
    done
}

read_control_commands() {
    while IFS= read -r action; do
        if [ ! -f "$ARMED_FILE" ]; then
            echo "Startup input ignored: $action"
            continue
        fi
        case "$action" in
            next)
                send_navigation next
                echo "X control: next"
                ;;
            previous)
                send_navigation previous
                echo "X control: previous"
                ;;
            touch-left|touch-right)
                send_touch "$action"
                echo "X control: $action"
                ;;
        esac
    done
}

child_pids=
cleanup() {
    rm -f "$READY_FILE"
    [ -z "$child_pids" ] || kill $child_pids 2>/dev/null || true
    rm -f "$CONTROL_FIFO"
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

echo "Button listener started."
if [ ! -x "$X_CONTROLS" ]; then
    echo "X control helper is missing or not executable: $X_CONTROLS" >&2
    exit 10
fi
if ! mkfifo "$CONTROL_FIFO"; then
    echo "Could not create the X control pipe." >&2
    exit 11
fi

read_control_commands < "$CONTROL_FIFO" &
child_pids="$child_pids $!"
# Keep one evdev descriptor open throughout capture, without EVIOCGRAB.
# Limit to 64 KiB and terminate the reader in cleanup if it has not filled.
if pagepress_path=$(find_input_device "$PAGEPRESS_DEVICE_NAME"); then
    dd if="$pagepress_path" of="$STATE_DIR/pagepress-events.bin" bs=16 count=4096 2> "$STATE_DIR/pagepress-capture.log" &
    child_pids="$child_pids $!"
    echo "Raw PagePress capture: $pagepress_path (maximum 4096 records)."
fi
"$X_CONTROLS" > "$CONTROL_FIFO" 2> "$STATE_DIR/x-events.bin" &
x_controls_pid=$!
child_pids="$child_pids $x_controls_pid"
sleep 1
if ! kill -0 "$x_controls_pid" 2>/dev/null; then
    wait "$x_controls_pid"
    x_controls_status=$?
    echo "X control helper failed at stage $x_controls_status." >&2
    exit 12
fi
touch "$READY_FILE"
echo "X keyboard and pointer controls are active."

if power_path=$(find_input_device "$POWER_DEVICE_NAME"); then
    read_power_events "$power_path" &
    child_pids="$child_pids $!"
else
    echo "power device '$POWER_DEVICE_NAME' was not found." >&2
fi

while [ ! -f "$BASE_DIR/disabled" ] && kill -0 "$x_controls_pid" 2>/dev/null; do
    sleep 1
done
