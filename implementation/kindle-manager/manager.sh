#!/bin/sh

set -u
KINDLE_ROOT=${KINDLE_ROOT:-/mnt/us}
MANAGER_DIR=${MANAGER_DIR:-$KINDLE_ROOT/kindle-manager}
. "$MANAGER_DIR/config.sh"

STATE_DIR="$MANAGER_DIR/state"
APP_DIR="$KINDLE_ROOT/kindle-photoframe"
DOCUMENTS_DIR="$KINDLE_ROOT/documents"
BACKUP_DIR="$MANAGER_DIR/backups"
COMMAND_FILE="$STATE_DIR/command.tsv"
STATUS_FILE="$STATE_DIR/status.tsv"
LAST_COMMAND_FILE="$STATE_DIR/last-command-id"
mkdir -p "$STATE_DIR" "$BACKUP_DIR"
MANAGER_LOCK="$STATE_DIR/manager.lock"
if ! mkdir "$MANAGER_LOCK" 2>/dev/null; then
    existing_pid=$(cat "$STATE_DIR/manager.pid" 2>/dev/null || true)
    if [ -n "$existing_pid" ] && [ -r "/proc/$existing_pid/cmdline" ] && tr '\000' ' ' < "/proc/$existing_pid/cmdline" | grep -q "$MANAGER_DIR/manager.sh"; then
        exit 33
    fi
    rm -rf "$MANAGER_LOCK"
    mkdir "$MANAGER_LOCK" 2>/dev/null || exit 33
fi
printf '%s\n' "$$" > "$STATE_DIR/manager.pid"
trap 'rm -f "$STATE_DIR/manager.pid"; rmdir "$MANAGER_LOCK" 2>/dev/null || true' EXIT
trap 'exit 0' HUP INT TERM

[ -r "$AUTH_TOKEN_FILE" ] || exit 31
auth_token=$(cat "$AUTH_TOKEN_FILE")
echo "$auth_token" | grep -Eq '^[a-f0-9]{64}$' || exit 32

field() {
    key=$1
    tab=$(printf '\t')
    sed -n "s/^${key}${tab}//p" "$COMMAND_FILE" | head -n 1
}

app_state() {
    if [ ! -d "$APP_DIR" ]; then
        printf '%s' missing
    elif [ -f "$APP_DIR/state/player.pid" ]; then
        pid=$(cat "$APP_DIR/state/player.pid" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then printf '%s' running; else printf '%s' stopped; fi
    else
        printf '%s' stopped
    fi
}

app_version() {
    if [ -r "$APP_DIR/VERSION" ]; then
        head -n 1 "$APP_DIR/VERSION" | tr -cd 'A-Za-z0-9._-'
    elif [ -r "$APP_DIR/config.sh" ]; then
        sed -n 's/^APP_VERSION=//p' "$APP_DIR/config.sh" | head -n 1 | tr -cd 'A-Za-z0-9._-'
    fi
}

post_status() {
    command_id=$1
    action=$2
    result=$3
    detail=$(printf '%s' "$4" | tr '\t\r\n' '   ' | cut -c 1-180)
    {
        printf '# kindle-photoframe-status-v1\n'
        printf 'device\t%s\n' "$DEVICE_ID"
        [ -z "$command_id" ] || printf 'commandId\t%s\n' "$command_id"
        printf 'action\t%s\n' "$action"
        printf 'result\t%s\n' "$result"
        printf 'appState\t%s\n' "$(app_state)"
        printf 'appVersion\t%s\n' "$(app_version)"
        printf 'detail\t%s\n' "$detail"
    } > "$STATUS_FILE"
    curl -fsS --connect-timeout 10 --max-time 30 \
        -H "Authorization: Bearer $auth_token" \
        -H 'Content-Type: text/tab-separated-values' \
        --data-binary "@$STATUS_FILE" "$SERVER_URL/v1/control/status" >/dev/null 2>&1 || true
}

collect_diagnostics() {
    command_id=$1
    diagnostic_dir="$STATE_DIR/diagnostic-$command_id"
    archive="$STATE_DIR/diagnostic-$command_id.tar.gz"
    tar_file="$STATE_DIR/diagnostic-$command_id.tar"
    rm -rf "$diagnostic_dir" "$archive" "$tar_file"
    mkdir -p "$diagnostic_dir/logs"
    {
        printf 'collectedAt='; date -u '+%Y-%m-%dT%H:%M:%SZ'
        printf 'device=%s\n' "$DEVICE_ID"
        printf 'appState=%s\n' "$(app_state)"
        printf 'appVersion=%s\n' "$(app_version)"
        printf 'frontlight='; lipc-get-prop -i com.lab126.powerd flIntensity 2>&1 || true
        printf 'cvmPids='; pidof cvm 2>&1 || true
        printf 'uptime='; uptime 2>&1 || true
        uname -a 2>&1 || true
        df -h "$KINDLE_ROOT" 2>&1 || true
    } > "$diagnostic_dir/summary.txt"
    for prop in battLevel battStateInfo battTemperature isCharging state status preventScreenSaver flAuto flIntensity flMaxIntensity; do
        printf '%s\t' "$prop" >> "$diagnostic_dir/powerd-properties.tsv"
        lipc-get-prop com.lab126.powerd "$prop" >> "$diagnostic_dir/powerd-properties.tsv" 2>&1 || true
    done
    for prop in fsrkeypadEnable fsrkeypadNextEnable fsrkeypadPrevEnable; do
        printf '%s\t' "$prop" >> "$diagnostic_dir/deviced-properties.tsv"
        lipc-get-prop com.lab126.deviced "$prop" >> "$diagnostic_dir/deviced-properties.tsv" 2>&1 || true
    done
    ps > "$diagnostic_dir/processes.txt" 2>&1 || true
    [ ! -f "$APP_DIR/state/frontlight-status.tsv" ] || cp "$APP_DIR/state/frontlight-status.tsv" "$diagnostic_dir/frontlight-status.tsv"
    for name in player buttons sync input-suppression manual-start manual-stop frontlight pagepress-mode ui-runtime; do
        [ ! -f "$APP_DIR/state/$name.log" ] || tail -n 400 "$APP_DIR/state/$name.log" > "$diagnostic_dir/logs/$name.log" 2>&1
    done
    for name in x-events.bin pagepress-events.bin; do
        [ ! -f "$APP_DIR/state/$name" ] || cp "$APP_DIR/state/$name" "$diagnostic_dir/logs/$name"
    done
    [ ! -f "$STATE_DIR/manager.log" ] || tail -n 400 "$STATE_DIR/manager.log" > "$diagnostic_dir/logs/manager.log" 2>&1
    (cd "$diagnostic_dir" && tar -cf "$tar_file" .) || return 81
    gzip -f "$tar_file" || return 81
    bytes=$(wc -c < "$archive" | tr -d ' ')
    [ "$bytes" -le 1048576 ] || return 82
    curl -fsS --connect-timeout 10 --max-time 60 \
        -H "Authorization: Bearer $auth_token" \
        -H 'Content-Type: application/gzip' \
        --data-binary "@$archive" "$SERVER_URL/v1/control/diagnostics/$command_id" >/dev/null 2>&1 || return 83
    rm -rf "$diagnostic_dir" "$archive"
    return 0
}

available_kib() {
    df -k "$KINDLE_ROOT" 2>/dev/null | awk 'NR == 2 { print $4 }' | tr -cd '0-9'
}

cleanup_storage() {
    before_kib=$(available_kib)
    case "$before_kib" in ''|*[!0-9]*) return 84 ;; esac

    # These are rollback copies from earlier wireless updates. The active
    # application and its authentication files live outside this directory.
    rm -rf "$BACKUP_DIR"/* || return 85

    # Failed or interrupted commands may leave unpacked archives behind.
    rm -rf "$STATE_DIR"/update-* "$STATE_DIR"/diagnostic-* || return 86

    removed_cache=0
    playlist="$APP_DIR/state/playlist"
    if [ -s "$playlist" ] && [ -d "$APP_DIR/cache" ]; then
        for cached in "$APP_DIR/cache"/*; do
            [ -f "$cached" ] || continue
            if ! grep -F -x -q "$cached" "$playlist"; then
                rm -f "$cached" || return 87
                removed_cache=$((removed_cache + 1))
            fi
        done
    fi
    sync

    after_kib=$(available_kib)
    case "$after_kib" in ''|*[!0-9]*) return 88 ;; esac
    reclaimed_kib=$((after_kib - before_kib))
    [ "$reclaimed_kib" -ge 0 ] || reclaimed_kib=0
    CLEANUP_DETAIL="Reclaimed ${reclaimed_kib} KiB; removed ${removed_cache} stale cached photos; ${after_kib} KiB available"
}

stop_app() {
    [ ! -f "$APP_DIR/stop.sh" ] || sh "$APP_DIR/stop.sh" >/dev/null 2>&1 || true
}

start_app() {
    [ -f "$APP_DIR/start.sh" ] || return 1
    sh "$APP_DIR/start.sh" >/dev/null 2>&1
}

pause_app_for_update() {
    touch "$APP_DIR/state/maintenance-restart"
    if [ -f "$APP_DIR/state/player.pid" ]; then
        pid=$(cat "$APP_DIR/state/player.pid" 2>/dev/null || true)
        if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' < "/proc/$pid/cmdline" | grep -q "$APP_DIR/player.sh"; then
            kill "$pid" 2>/dev/null || true
            waited=0
            while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
                sleep 1
                waited=$((waited + 1))
            done
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    if [ -r "$APP_DIR/state/frontlight.pid" ]; then
        frontlight_pid=$(cat "$APP_DIR/state/frontlight.pid" 2>/dev/null || true)
        [ -z "$frontlight_pid" ] || kill "$frontlight_pid" 2>/dev/null || true
    fi
    killall kindle-xcontrols kindle-evgrab-cat >/dev/null 2>&1 || true
    rm -f "$APP_DIR/state/player.pid" "$APP_DIR/state/buttons.pid" "$APP_DIR/state/frontlight.pid"
    rm -f "$APP_DIR/state/navigation-command" "$APP_DIR/state/exit-requested" "$APP_DIR/state/touch-command"
    rm -f "$APP_DIR/state/controls-ready" "$APP_DIR/state/photo-controls-armed" "$APP_DIR/state/maintenance-restart"
    rmdir "$APP_DIR/state/player.lock" 2>/dev/null || true
}

apply_update() {
    command_id=$1
    sha=$2
    bytes=$3
    path=$4
    echo "$sha" | grep -Eq '^[a-f0-9]{64}$' || return 41
    echo "$bytes" | grep -Eq '^[0-9]+$' || return 42
    echo "$path" | grep -Eq '^/v1/control/packages/[a-f0-9]{64}\.tar\.gz$' || return 43
    [ "$path" = "/v1/control/packages/$sha.tar.gz" ] || return 44
    package="$STATE_DIR/update-$command_id-$$.tar.gz"
    staging="$STATE_DIR/update-$command_id-$$"
    rm -rf "$staging"
    mkdir -p "$staging"
    curl -fsS --connect-timeout 10 --max-time 180 -H "Authorization: Bearer $auth_token" "$SERVER_URL$path" -o "$package" || return 45
    [ "$(wc -c < "$package" | tr -d ' ')" = "$bytes" ] || return 46
    [ "$(sha256sum "$package" | awk '{print $1}')" = "$sha" ] || return 47
    gzip -dc "$package" | tar -xf - -C "$staging" || return 48
    head -n 1 "$staging/manifest.tsv" | grep -q '^# kindle-photoframe-update-v1$' || return 49
    tab=$(printf '\t')
    while IFS="$tab" read -r file_sha file_bytes relative; do
        case "$file_sha" in \#*|'') continue ;; esac
        echo "$file_sha" | grep -Eq '^[a-f0-9]{64}$' || return 50
        echo "$file_bytes" | grep -Eq '^[0-9]+$' || return 51
        case "$relative" in
            *..*|/*|*[!A-Za-z0-9._/\ -]*) return 52 ;;
            kindle-photoframe/*|kindle-manager/*|documents/'Photoframe Start.sh'|documents/'Photoframe Exit.sh') ;;
            *) return 53 ;;
        esac
        source="$staging/payload/$relative"
        [ -f "$source" ] || return 54
        [ "$(wc -c < "$source" | tr -d ' ')" = "$file_bytes" ] || return 55
        [ "$(sha256sum "$source" | awk '{print $1}')" = "$file_sha" ] || return 56
    done < "$staging/manifest.tsv"

    was_running=no
    [ "$(app_state)" = running ] && was_running=yes
    # Keep the Kindle in frame mode while updating. A full stop restores the
    # native UI, which exports /mnt/us over USB when a charging cable is left
    # connected and freezes the update halfway through.
    [ "$was_running" != yes ] || pause_app_for_update
    backup="$BACKUP_DIR/$command_id"
    mkdir -p "$backup/kindle-photoframe" "$backup/kindle-manager"
    if [ -d "$APP_DIR" ]; then
        for source in "$APP_DIR"/*; do
            [ -f "$source" ] || continue
            cp "$source" "$backup/kindle-photoframe/" || return 57
        done
    fi
    for name in config.sh manager.sh start.sh supervisor.sh; do
        [ ! -f "$MANAGER_DIR/$name" ] || cp "$MANAGER_DIR/$name" "$backup/kindle-manager/$name" || return 57
    done
    [ ! -f "$DOCUMENTS_DIR/Photoframe Start.sh" ] || cp -p "$DOCUMENTS_DIR/Photoframe Start.sh" "$backup/Photoframe Start.sh"
    [ ! -f "$DOCUMENTS_DIR/Photoframe Exit.sh" ] || cp -p "$DOCUMENTS_DIR/Photoframe Exit.sh" "$backup/Photoframe Exit.sh"
    mkdir -p "$APP_DIR" "$DOCUMENTS_DIR" "$MANAGER_DIR"
    while IFS="$tab" read -r file_sha file_bytes relative; do
        case "$file_sha" in \#*|'') continue ;; esac
        source="$staging/payload/$relative"
        target="$KINDLE_ROOT/$relative"
        mkdir -p "$(dirname "$target")" || return 58
        cp "$source" "$target" || return 59
    done < "$staging/manifest.tsv"
    chmod +x "$APP_DIR"/*.sh "$MANAGER_DIR"/*.sh "$APP_DIR/kindle-evgrab-cat" "$APP_DIR/kindle-xcontrols" 2>/dev/null || true
    rm -rf "$staging" "$package"
    [ "$was_running" != yes ] || start_app || return 61
    return 0
}

execute_command() {
    command_id=$(field id)
    action=$(field action)
    expires=$(field expires)
    echo "$command_id" | grep -Eq '^[a-f0-9-]{36}$' || return 70
    echo "$expires" | grep -Eq '^[0-9]+$' || return 71
    now=$(date +%s)
    [ "$expires" -ge "$now" ] || return 72
    [ "$(cat "$LAST_COMMAND_FILE" 2>/dev/null || true)" != "$command_id" ] || return 0
    post_status "$command_id" "$action" running 'Command received'
    command_detail='Command completed'
    case "$action" in
        restart) stop_app; rm -f "$APP_DIR/disabled"; start_app || return 73 ;;
        disable) stop_app ;;
        enable) rm -f "$APP_DIR/disabled"; start_app || return 74 ;;
        update) apply_update "$command_id" "$(field packageSha256)" "$(field packageBytes)" "$(field packagePath)" || return $? ;;
        diagnose) collect_diagnostics "$command_id" || return $? ;;
        cleanup)
            cleanup_storage || return $?
            command_detail=$CLEANUP_DETAIL
            ;;
        uninstall)
            stop_app
            backup="$BACKUP_DIR/uninstalled-$command_id"
            mkdir -p "$backup"
            [ ! -d "$APP_DIR" ] || mv "$APP_DIR" "$backup/kindle-photoframe"
            [ ! -f "$DOCUMENTS_DIR/Photoframe Start.sh" ] || mv "$DOCUMENTS_DIR/Photoframe Start.sh" "$backup/Photoframe Start.sh"
            [ ! -f "$DOCUMENTS_DIR/Photoframe Exit.sh" ] || mv "$DOCUMENTS_DIR/Photoframe Exit.sh" "$backup/Photoframe Exit.sh"
            ;;
        *) return 75 ;;
    esac
    printf '%s\n' "$command_id" > "$LAST_COMMAND_FILE"
    case "$action" in restart|enable|update) sleep 3 ;; esac
    post_status "$command_id" "$action" ok "$command_detail"
}

last_heartbeat=0
while :; do
    if curl -fsS --connect-timeout 10 --max-time 30 -H "Authorization: Bearer $auth_token" "$SERVER_URL/v1/control/command" -o "$COMMAND_FILE"; then
        if head -n 1 "$COMMAND_FILE" | grep -q '^# kindle-photoframe-control-v1$'; then
            action=$(field action)
            if [ "$action" != none ]; then
                execute_command
                code=$?
                if [ "$code" -ne 0 ]; then
                    post_status "$(field id)" "$action" error "Command failed with code $code"
                fi
            fi
        fi
    fi
    now=$(date +%s)
    if [ $((now - last_heartbeat)) -ge "$HEARTBEAT_SECONDS" ]; then
        post_status '' heartbeat ok 'Wireless manager is online'
        last_heartbeat=$now
    fi
    sleep "$POLL_SECONDS"
done
