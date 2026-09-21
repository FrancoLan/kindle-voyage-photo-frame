#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh

image=${1:-}
if [ -z "$image" ] || [ ! -f "$image" ]; then
    echo "usage: $0 /absolute/path/to/image" >&2
    exit 2
fi
if [ ! -x "$FBINK" ]; then
    echo "FBInk is missing: $FBINK" >&2
    exit 3
fi

mkdir -p "$STATE_DIR"
if "$FBINK" -c -f -i "$image"; then
    tmp="$STATE_DIR/current.tmp.$$"
    printf '%s\n' "$image" > "$tmp"
    mv "$tmp" "$STATE_DIR/current"
    exit 0
fi

echo "FBInk failed to render: $image" >&2
exit 4

