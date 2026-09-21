#!/bin/sh

set -eu

if [ "$(uname -s)" != Darwin ]; then
    echo "This installer requires macOS." >&2
    exit 1
fi
if [ "$#" -ne 1 ]; then
    echo "usage: ./scripts/install-mac.sh /path/to/config.json" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CONFIG_INPUT=$(CDPATH= cd -- "$(dirname -- "$1")" && printf '%s/%s\n' "$PWD" "$(basename -- "$1")")
NODE=$(command -v node || true)
SWIFTC=$(command -v swiftc || true)
[ -n "$NODE" ] || { echo "Node.js is required." >&2; exit 1; }
[ -n "$SWIFTC" ] || { echo "The Xcode Command Line Tools (swiftc) are required." >&2; exit 1; }

SUPPORT="$HOME/Library/Application Support/KindleVoyagePhotoFrame"
RUNTIME="$SUPPORT/runtime"
STAGING="$SUPPORT/runtime.installing.$$"
DATA="$SUPPORT/data"
LOGS="$HOME/Library/Logs/KindleVoyagePhotoFrame"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
SERVER_LABEL=io.github.francolan.kindle-voyage-photo-frame.server
SYNC_LABEL=io.github.francolan.kindle-voyage-photo-frame.sync

mkdir -p "$SUPPORT" "$DATA" "$LOGS" "$LAUNCH_AGENTS"
rm -rf "$STAGING"
mkdir -p "$STAGING/package-source/implementation/kindle" "$STAGING/package-source/implementation/kindle-manager"
cp "$REPO_ROOT"/implementation/mac/*.mjs "$STAGING/"
cp "$REPO_ROOT"/implementation/mac/*.swift "$STAGING/"
cp -R "$REPO_ROOT/implementation/kindle/." "$STAGING/package-source/implementation/kindle/"
cp -R "$REPO_ROOT/implementation/kindle-manager/." "$STAGING/package-source/implementation/kindle-manager/"
CLANG_MODULE_CACHE_PATH="$STAGING/module-cache" "$SWIFTC" "$STAGING/metadata-overlay.swift" -o "$STAGING/metadata-overlay"
CLANG_MODULE_CACHE_PATH="$STAGING/module-cache" "$SWIFTC" -parse-as-library "$STAGING/reverse-geocode.swift" -o "$STAGING/reverse-geocode"
rm -rf "$STAGING/module-cache"

launchctl bootout "gui/$UID/$SERVER_LABEL" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID/$SYNC_LABEL" >/dev/null 2>&1 || true
rm -rf "$RUNTIME"
mv "$STAGING" "$RUNTIME"

"$NODE" "$SCRIPT_DIR/configure-runtime.mjs" \
    "$CONFIG_INPUT" "$RUNTIME/config.json" "$SUPPORT" "$RUNTIME" "$DATA" \
    "$RUNTIME/package-source" "$NODE" "$LOGS" \
    "$REPO_ROOT/implementation/mac/launchagents" "$LAUNCH_AGENTS"

SERVER_PLIST="$LAUNCH_AGENTS/$SERVER_LABEL.plist"
SYNC_PLIST="$LAUNCH_AGENTS/$SYNC_LABEL.plist"
plutil -lint "$SERVER_PLIST" "$SYNC_PLIST" >/dev/null
launchctl bootstrap "gui/$UID" "$SERVER_PLIST"
launchctl bootstrap "gui/$UID" "$SYNC_PLIST"
launchctl kickstart -k "gui/$UID/$SERVER_LABEL"
launchctl kickstart -k "gui/$UID/$SYNC_LABEL"

attempt=0
while [ ! -s "$DATA/server-token" ] && [ "$attempt" -lt 20 ]; do
    sleep 1
    attempt=$((attempt + 1))
done
[ -s "$DATA/server-token" ] || { echo "Server token was not created; inspect $LOGS/server.error.log" >&2; exit 1; }

echo "Mac services installed."
echo "Runtime config: $RUNTIME/config.json"
echo "Logs: $LOGS"
echo "Next: connect the Kindle by USB and run scripts/install-kindle.sh."
