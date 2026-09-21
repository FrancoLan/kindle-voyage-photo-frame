#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh

LOCK_DIR="$STATE_DIR/player.lock"
frame_entered=0
sync_pid=
PLAYLIST="$STATE_DIR/playback-playlist"
TOUCH_FILE="$STATE_DIR/touch-command"
SYNC_COMPLETE="$STATE_DIR/sync-complete"
mkdir -p "$STATE_DIR"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Photoframe player is already running." >&2
    exit 5
fi

cleanup() {
    if [ -r "$STATE_DIR/frontlight.pid" ]; then
        frontlight_pid=$(cat "$STATE_DIR/frontlight.pid" 2>/dev/null || true)
        [ -z "$frontlight_pid" ] || kill "$frontlight_pid" 2>/dev/null || true
    fi
    if [ -r "$STATE_DIR/buttons.pid" ]; then
        buttons_pid=$(cat "$STATE_DIR/buttons.pid" 2>/dev/null || true)
        if [ -n "$buttons_pid" ]; then
            kill "$buttons_pid" 2>/dev/null || true
            wait "$buttons_pid" 2>/dev/null || true
        fi
    fi
    rm -f "$STATE_DIR/buttons.pid" "$STATE_DIR/navigation-command" "$STATE_DIR/exit-requested" "$STATE_DIR/photo-controls-armed" "$TOUCH_FILE"
    rm -f "$STATE_DIR/player.pid" "$STATE_DIR/frontlight.pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    if [ "$frame_entered" -eq 1 ]; then
        if [ -f "$STATE_DIR/maintenance-restart" ]; then
            rm -f "$STATE_DIR/maintenance-restart"
        else
            /mnt/us/kindle-photoframe/restore-ui.sh >/dev/null 2>&1 || true
        fi
    fi
}
trap 'exit 0' HUP INT TERM
trap cleanup EXIT
printf '%s\n' "$$" > "$STATE_DIR/player.pid"

if [ -f "$BASE_DIR/disabled" ]; then
    echo "Photoframe is disabled." >&2
    exit 6
fi

rm -f "$STATE_DIR/navigation-command" "$STATE_DIR/exit-requested" "$STATE_DIR/controls-ready" "$STATE_DIR/photo-controls-armed" "$TOUCH_FILE" "$SYNC_COMPLETE"
nohup sh /mnt/us/kindle-photoframe/buttons.sh > "$STATE_DIR/buttons.log" 2>&1 &
printf '%s\n' "$!" > "$STATE_DIR/buttons.pid"

controls_wait=0
while [ ! -f "$STATE_DIR/controls-ready" ] && [ "$controls_wait" -lt 5 ]; do
    sleep 1
    controls_wait=$((controls_wait + 1))
done
if [ ! -f "$STATE_DIR/controls-ready" ]; then
    echo "X controls did not become ready." >&2
    exit 9
fi

/mnt/us/kindle-photoframe/enter-frame-mode.sh || exit 7
frame_entered=1
sh "$BASE_DIR/frontlight.sh" watch >> "$STATE_DIR/frontlight.log" 2>&1 &
printf '%s\n' "$!" > "$STATE_DIR/frontlight.pid"
sh "$BASE_DIR/pagepress-mode.sh" enable
current_index=1
refresh_playlist=1
sync_needed=1
first_image=1

show_exit_confirmation() {
    "$FBINK" --cls=top=484,left=96,width=880,height=480 -B WHITE >/dev/null 2>&1 || true
    "$FBINK" -S 3 -m -M -y -2 -p "EXIT PHOTO MODE?" >/dev/null 2>&1 || true
    "$FBINK" -S 2 -m -M -y 2 -p "LEFT: CANCEL    RIGHT: EXIT" >/dev/null 2>&1 || true
}

wait_for_exit_confirmation() {
    CONFIRM_ACTION=cancel
    confirm_elapsed=0
    rm -f "$TOUCH_FILE" "$STATE_DIR/navigation-command"
    while [ "$confirm_elapsed" -lt 15 ] && [ ! -f "$BASE_DIR/disabled" ]; do
        if [ -f "$STATE_DIR/exit-requested" ]; then
            CONFIRM_ACTION=exit
            return
        elif [ -s "$TOUCH_FILE" ]; then
            touch_action=$(cat "$TOUCH_FILE" 2>/dev/null || true)
            rm -f "$TOUCH_FILE"
            case "$touch_action" in
                touch-right) CONFIRM_ACTION=exit ;;
                *) CONFIRM_ACTION=cancel ;;
            esac
            return
        elif [ -s "$STATE_DIR/navigation-command" ]; then
            CONFIRM_ACTION=$(cat "$STATE_DIR/navigation-command" 2>/dev/null || true)
            rm -f "$STATE_DIR/navigation-command"
            case "$CONFIRM_ACTION" in next|previous) ;; *) CONFIRM_ACTION=cancel ;; esac
            return
        fi
        sleep 1
        confirm_elapsed=$((confirm_elapsed + 1))
    done
}

while [ ! -f "$BASE_DIR/disabled" ]; do
    if [ "$refresh_playlist" -eq 1 ]; then
        if [ "$sync_needed" -eq 1 ] && { [ -z "$sync_pid" ] || ! kill -0 "$sync_pid" 2>/dev/null; }; then
            sh "$BASE_DIR/sync.sh" >> "$STATE_DIR/sync.log" 2>&1 &
            sync_pid=$!
        fi
        sync_needed=0
        if [ -s "$STATE_DIR/playlist" ]; then
            cp "$STATE_DIR/playlist" "$PLAYLIST"
        else
            find "$CACHE_DIR" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.pgm' \) | sort > "$PLAYLIST"
        fi
        photo_count=$(wc -l < "$PLAYLIST" | tr -d ' ')
        if [ "$photo_count" -eq 0 ]; then
            echo "No playable images in $CACHE_DIR" >&2
            exit 8
        fi
        if [ "$current_index" -gt "$photo_count" ]; then
            current_index=1
        fi
        refresh_playlist=0
    fi

    image=$(sed -n "${current_index}p" "$PLAYLIST")
    if [ ! -f "$image" ]; then
        refresh_playlist=1
        continue
    fi

    /mnt/us/kindle-photoframe/render.sh "$image" || true
    printf '%s\n' "$image" > "$STATE_DIR/current-image"
    if [ "$first_image" -eq 1 ]; then
        # Drain startup taps while the first e-ink refresh settles.
        sleep 1
        rm -f "$STATE_DIR/navigation-command" "$STATE_DIR/exit-requested" "$TOUCH_FILE"
        touch "$STATE_DIR/photo-controls-armed"
        first_image=0
        echo "Photo controls armed after first image."
    fi

    action=
    elapsed=0
    while [ "$elapsed" -lt "$INTERVAL_SECONDS" ] && [ ! -f "$BASE_DIR/disabled" ]; do
        if [ -f "$STATE_DIR/exit-requested" ]; then
            action=exit
            break
        elif [ -f "$SYNC_COMPLETE" ]; then
            rm -f "$SYNC_COMPLETE"
            action=reload
            break
        elif [ -s "$TOUCH_FILE" ]; then
            rm -f "$TOUCH_FILE"
            action=confirm-exit
            break
        elif [ -s "$STATE_DIR/navigation-command" ]; then
            action=$(cat "$STATE_DIR/navigation-command" 2>/dev/null || true)
            rm -f "$STATE_DIR/navigation-command"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    [ ! -f "$BASE_DIR/disabled" ] || break

    if [ "$action" = "confirm-exit" ]; then
        show_exit_confirmation
        wait_for_exit_confirmation
        action=$CONFIRM_ACTION
        if [ "$action" = "cancel" ]; then
            /mnt/us/kindle-photoframe/render.sh "$image" || true
            continue
        fi
    fi

    case "$action" in
        exit)
            break
            ;;
        previous)
            current_index=$((current_index - 1))
            if [ "$current_index" -lt 1 ]; then
                current_index=$photo_count
            fi
            ;;
        reload)
            current_index=1
            refresh_playlist=1
            sync_needed=0
            ;;
        next|'')
            current_index=$((current_index + 1))
            if [ "$current_index" -gt "$photo_count" ]; then
                current_index=1
                refresh_playlist=1
                sync_needed=1
            fi
            ;;
    esac
done
