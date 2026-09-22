#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh
mkdir -p "$STATE_DIR"
SYNC_LOCK="$STATE_DIR/sync.lock"
if ! mkdir "$SYNC_LOCK" 2>/dev/null; then
    # A completed background sync may outlive the player. Never overlap it.
    owner=$(cat "$SYNC_LOCK/pid" 2>/dev/null || true)
    case "$owner" in ''|*[!0-9]*) exit 0 ;; esac
    kill -0 "$owner" 2>/dev/null && exit 0
    rm -f "$SYNC_LOCK/pid"
    rmdir "$SYNC_LOCK" 2>/dev/null || exit 0
    mkdir "$SYNC_LOCK" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" > "$SYNC_LOCK/pid"
cleanup_sync() {
    [ -z "${manifest_tmp:-}" ] || rm -f "$manifest_tmp"
    [ -z "${playlist_tmp:-}" ] || rm -f "$playlist_tmp"
    rm -f "$CACHE_DIR"/*.download.$$ "$SYNC_LOCK/pid"
    rmdir "$SYNC_LOCK" 2>/dev/null || true
}
trap cleanup_sync EXIT
trap 'exit 1' HUP INT TERM

[ -n "${SERVER_URL:-}" ] || { echo "SERVER_URL is not configured" >&2; exit 20; }
[ -r "$AUTH_TOKEN_FILE" ] || { echo "Authentication token is missing" >&2; exit 31; }
auth_token=$(cat "$AUTH_TOKEN_FILE")
echo "$auth_token" | grep -Eq '^[a-f0-9]{64}$' || exit 32
mkdir -p "$CACHE_DIR" "$STATE_DIR"
manifest_tmp="$STATE_DIR/manifest.tmp.$$"
playlist_tmp="$STATE_DIR/playlist.tmp.$$"

curl -fsS --connect-timeout 10 --max-time 30 -H "Authorization: Bearer $auth_token" "$SERVER_URL/v1/manifest" -o "$manifest_tmp" || exit 21
head -n 1 "$manifest_tmp" | grep -q '^# kindle-photoframe-manifest-v1' || exit 22
: > "$playlist_tmp"

tab=$(printf '\t')
while IFS="$tab" read -r sha bytes path; do
    case "$sha" in \#*|'') continue ;; esac
    echo "$sha" | grep -Eq '^[a-f0-9]{64}$' || exit 23
    echo "$bytes" | grep -Eq '^[0-9]+$' || exit 24
    echo "$path" | grep -Eq '^/v1/images/[a-f0-9]{64}\.png$' || exit 25
    [ "$path" = "/v1/images/$sha.png" ] || exit 26
    target="$CACHE_DIR/$sha.png"
    if [ ! -f "$target" ] || [ "$(wc -c < "$target" | tr -d ' ')" != "$bytes" ] || [ "$(sha256sum "$target" | awk '{print $1}')" != "$sha" ]; then
        temp="$CACHE_DIR/$sha.png.download.$$"
        curl -fsS --connect-timeout 10 --max-time 120 -H "Authorization: Bearer $auth_token" "$SERVER_URL$path" -o "$temp" || exit 27
        [ "$(wc -c < "$temp" | tr -d ' ')" = "$bytes" ] || exit 28
        [ "$(sha256sum "$temp" | awk '{print $1}')" = "$sha" ] || exit 29
        mv "$temp" "$target"
    fi
    printf '%s\n' "$target" >> "$playlist_tmp"
done < "$manifest_tmp"

[ -s "$playlist_tmp" ] || exit 30
mv "$playlist_tmp" "$STATE_DIR/playlist"
mv "$manifest_tmp" "$STATE_DIR/manifest.tsv"
for cached in "$CACHE_DIR"/*.png; do
    [ -f "$cached" ] || continue
    if ! grep -F -x -q "$cached" "$STATE_DIR/playlist"; then
        rm -f "$cached" || exit 33
    fi
done
touch "$STATE_DIR/sync-complete"
echo "Photoframe cache synchronized."
