#!/bin/sh

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    echo "usage: ./scripts/install-kindle.sh http://MAC_LAN_IP:8787 [/Volumes/Kindle] [/path/to/runtime/config.json]" >&2
    exit 1
fi

SERVER_URL=${1%/}
MOUNT=${2:-/Volumes/Kindle}
RUNTIME_CONFIG=${3:-$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime/config.json}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

case "$SERVER_URL" in http://*:*) ;; *) echo "Server URL must look like http://192.168.1.10:8787" >&2; exit 1 ;; esac
[ -d "$MOUNT/documents" ] || { echo "Kindle USB volume not found at $MOUNT" >&2; exit 1; }
[ -f "$RUNTIME_CONFIG" ] || { echo "Runtime config not found: $RUNTIME_CONFIG" >&2; exit 1; }
TOKEN_FILE=$(node -e 'const fs=require("fs"); const c=JSON.parse(fs.readFileSync(process.argv[1])); process.stdout.write(c.authTokenFile)' "$RUNTIME_CONFIG")
[ -s "$TOKEN_FILE" ] || { echo "Server token not found: $TOKEN_FILE" >&2; exit 1; }

mkdir -p "$MOUNT/kindle-photoframe" "$MOUNT/kindle-manager"
cp -R "$REPO_ROOT/implementation/kindle/." "$MOUNT/kindle-photoframe/"
cp -R "$REPO_ROOT/implementation/kindle-manager/." "$MOUNT/kindle-manager/"
cp "$REPO_ROOT/implementation/kindle/photoframe-start-launcher.sh" "$MOUNT/documents/Photoframe Start.sh"
cp "$REPO_ROOT/implementation/kindle/photoframe-stop-launcher.sh" "$MOUNT/documents/Photoframe Exit.sh"

sed -i '' "s|^SERVER_URL=.*|SERVER_URL=$SERVER_URL|" "$MOUNT/kindle-photoframe/config.sh"
sed -i '' "s|^SERVER_URL=.*|SERVER_URL=\${SERVER_URL:-$SERVER_URL}|" "$MOUNT/kindle-manager/config.sh"
cp "$TOKEN_FILE" "$MOUNT/kindle-photoframe/auth-token"
cp "$TOKEN_FILE" "$MOUNT/kindle-manager/auth-token"
chmod +x "$MOUNT"/kindle-photoframe/*.sh "$MOUNT"/kindle-photoframe/kindle-xcontrols "$MOUNT"/kindle-photoframe/kindle-evgrab-cat "$MOUNT"/kindle-manager/*.sh
sync

echo "Kindle files installed at $MOUNT."
echo "Eject it with: diskutil eject '$MOUNT'"
echo "Then open Photoframe Start from the Kindle library."
