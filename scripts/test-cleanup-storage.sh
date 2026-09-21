#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/kindle-voyage-cleanup-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

KINDLE_ROOT="$TEST_DIR/kindle"
MANAGER_DIR="$KINDLE_ROOT/kindle-manager"
STATE_DIR="$MANAGER_DIR/state"
BACKUP_DIR="$MANAGER_DIR/backups"
APP_DIR="$KINDLE_ROOT/kindle-photoframe"
mkdir -p "$BACKUP_DIR/old-update" "$STATE_DIR/update-old/payload" "$STATE_DIR/diagnostic-old" "$APP_DIR/cache" "$APP_DIR/state"
printf 'backup\n' > "$BACKUP_DIR/old-update/file"
printf 'staging\n' > "$STATE_DIR/update-old/payload/file"
printf 'diagnostic\n' > "$STATE_DIR/diagnostic-old/file"
printf 'keep\n' > "$APP_DIR/cache/keep.png"
printf 'remove\n' > "$APP_DIR/cache/stale.png"
printf '%s\n' "$APP_DIR/cache/keep.png" > "$APP_DIR/state/playlist"
printf 'config\n' > "$APP_DIR/config.sh"
printf 'token\n' > "$APP_DIR/auth-token"

sed -n '/^available_kib()/,/^stop_app()/p' "$ROOT/implementation/kindle-manager/manager.sh" | sed '$d' > "$TEST_DIR/functions.sh"
. "$TEST_DIR/functions.sh"
cleanup_storage

[ ! -e "$BACKUP_DIR/old-update" ]
[ ! -e "$STATE_DIR/update-old" ]
[ ! -e "$STATE_DIR/diagnostic-old" ]
[ -f "$APP_DIR/cache/keep.png" ]
[ ! -e "$APP_DIR/cache/stale.png" ]
[ -f "$APP_DIR/config.sh" ]
[ -f "$APP_DIR/auth-token" ]
case "$CLEANUP_DETAIL" in *'removed 1 stale cached photos'*) ;; *) exit 1 ;; esac

echo "Storage cleanup checks passed."
