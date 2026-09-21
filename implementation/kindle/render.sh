#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh

image=${1:-}
mode=${2:-full}
if [ -z "$image" ] || [ ! -f "$image" ]; then
    echo "usage: $0 /absolute/path/to/image" >&2
    exit 2
fi
if [ ! -x "$FBINK" ]; then
    echo "FBInk is missing: $FBINK" >&2
    exit 3
fi

mkdir -p "$STATE_DIR"
case "$mode" in
    quick)
        # A non-flashing GC16 update keeps PagePress navigation responsive
        # while preserving the grayscale detail of a photo.
        "$FBINK" -c -W GC16 -i "$image"
        status=$?
        ;;
    full)
        # Flashing GC16 is the high-fidelity path used for timed changes.
        "$FBINK" -c -f -W GC16 -w -i "$image"
        status=$?
        ;;
    refresh)
        # The framebuffer already contains the current image. Refresh it in
        # place to clear ghosting without decoding and drawing it again.
        "$FBINK" -f -W GC16 -w -s
        status=$?
        ;;
    *)
        echo "unknown refresh mode: $mode" >&2
        exit 5
        ;;
esac

if [ "$status" -eq 0 ]; then
    [ "$mode" = refresh ] && exit 0
    tmp="$STATE_DIR/current.tmp.$$"
    printf '%s\n' "$image" > "$tmp"
    mv "$tmp" "$STATE_DIR/current"
    exit 0
fi

echo "FBInk failed to render $image in $mode mode" >&2
exit 4
