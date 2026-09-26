#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh

LOCK_DIR="$STATE_DIR/player.lock"
frame_entered=0
sync_pid=
PLAYLIST="$STATE_DIR/playback-playlist"
NORMAL_PLAYLIST="$STATE_DIR/normal-playback-playlist"
NEW_PHOTOS="$STATE_DIR/new-photos"
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
priority_active=0
resume_after_image=
resume_index=1
first_image=1
render_mode=full
manual_full_refresh_delay=${MANUAL_FULL_REFRESH_DELAY_SECONDS:-120}

choose_interval_seconds() {
    interval_min=${INTERVAL_MIN_SECONDS:-600}
    interval_max=${INTERVAL_MAX_SECONDS:-1200}
    case "$interval_min" in ''|*[!0-9]*) interval_min=600 ;; esac
    case "$interval_max" in ''|*[!0-9]*) interval_max=1200 ;; esac
    if [ "$interval_max" -lt "$interval_min" ]; then
        interval_max=$interval_min
    fi
    interval_range=$((interval_max - interval_min + 1))
    interval_random=
    if [ -r /dev/urandom ]; then
        interval_random=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -cd '0-9')
    fi
    case "$interval_random" in
        ''|*[!0-9]*) interval_random=$(($(date +%s) + $$)) ;;
    esac
    printf '%s\n' $((interval_min + interval_random % interval_range))
}

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
        if [ -s "$NEW_PHOTOS" ]; then
            cp "$PLAYLIST" "$NORMAL_PLAYLIST"
            resume_index=1
            normal_count=$(wc -l < "$NORMAL_PLAYLIST" | tr -d ' ')
            if [ -n "$resume_after_image" ]; then
                normal_index=0
                while IFS= read -r normal_image; do
                    normal_index=$((normal_index + 1))
                    if [ "$normal_image" = "$resume_after_image" ]; then
                        resume_index=$((normal_index + 1))
                        break
                    fi
                done < "$NORMAL_PLAYLIST"
            fi
            if [ "$resume_index" -gt "$normal_count" ]; then
                resume_index=1
            fi
            cp "$NEW_PHOTOS" "$PLAYLIST"
            rm -f "$NEW_PHOTOS"
            priority_active=1
            echo "New photos detected; playing them before resuming the existing sequence."
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

    /mnt/us/kindle-photoframe/render.sh "$image" "$render_mode" || true
    if [ "$render_mode" = quick ] && [ "$manual_full_refresh_delay" -gt 0 ]; then
        full_refresh_due=$manual_full_refresh_delay
    else
        full_refresh_due=0
    fi
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
    interval_seconds=$(choose_interval_seconds)
    echo "Next automatic photo change in ${interval_seconds} seconds."
    while [ "$elapsed" -lt "$interval_seconds" ] && [ ! -f "$BASE_DIR/disabled" ]; do
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
        elif [ "$full_refresh_due" -gt 0 ] && [ "$elapsed" -ge "$full_refresh_due" ]; then
            /mnt/us/kindle-photoframe/render.sh "$image" refresh || true
            full_refresh_due=0
            echo "Deferred full refresh completed for $image."
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
            render_mode=full
            continue
        fi
    fi

    case "$action" in
        exit)
            break
            ;;
        previous)
            render_mode=quick
            current_index=$((current_index - 1))
            if [ "$current_index" -lt 1 ]; then
                current_index=$photo_count
            fi
            ;;
        reload)
            render_mode=full
            current_index=1
            resume_after_image=$(cat "$STATE_DIR/current-image" 2>/dev/null || true)
            refresh_playlist=1
            sync_needed=0
            ;;
        next)
            render_mode=quick
            current_index=$((current_index + 1))
            if [ "$current_index" -gt "$photo_count" ]; then
                if [ "$priority_active" -eq 1 ]; then
                    cp "$NORMAL_PLAYLIST" "$PLAYLIST"
                    priority_active=0
                    current_index=$resume_index
                    photo_count=$(wc -l < "$PLAYLIST" | tr -d ' ')
                else
                    current_index=1
                    refresh_playlist=1
                    sync_needed=1
                fi
            fi
            ;;
        '')
            render_mode=full
            current_index=$((current_index + 1))
            if [ "$current_index" -gt "$photo_count" ]; then
                if [ "$priority_active" -eq 1 ]; then
                    cp "$NORMAL_PLAYLIST" "$PLAYLIST"
                    priority_active=0
                    current_index=$resume_index
                    photo_count=$(wc -l < "$PLAYLIST" | tr -d ' ')
                else
                    current_index=1
                    refresh_playlist=1
                    sync_needed=1
                fi
            fi
            ;;
    esac
done
