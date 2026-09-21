#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/kindle-voyage-render-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p "$TEST_DIR/state"
touch "$TEST_DIR/photo.png"

cat > "$TEST_DIR/fbink" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FBINK_CALLS"
EOF
chmod +x "$TEST_DIR/fbink"

cat > "$TEST_DIR/config.sh" <<EOF
BASE_DIR="$TEST_DIR"
STATE_DIR="$TEST_DIR/state"
FBINK="$TEST_DIR/fbink"
EOF
sed 's|^\. /mnt/us/kindle-photoframe/config.sh$|. "$TEST_CONFIG"|' \
    "$ROOT/implementation/kindle/render.sh" > "$TEST_DIR/render.sh"
chmod +x "$TEST_DIR/render.sh"
export TEST_CONFIG="$TEST_DIR/config.sh"
export FBINK_CALLS="$TEST_DIR/calls"

"$TEST_DIR/render.sh" "$TEST_DIR/photo.png" quick
"$TEST_DIR/render.sh" "$TEST_DIR/photo.png" full
"$TEST_DIR/render.sh" "$TEST_DIR/photo.png" refresh

[ "$(sed -n '1p' "$FBINK_CALLS")" = "-c -W GC16 -i $TEST_DIR/photo.png" ]
[ "$(sed -n '2p' "$FBINK_CALLS")" = "-c -f -W GC16 -w -i $TEST_DIR/photo.png" ]
[ "$(sed -n '3p' "$FBINK_CALLS")" = "-f -W GC16 -w -s" ]
[ "$(wc -l < "$FBINK_CALLS" | tr -d ' ')" = 3 ]
[ "$(cat "$TEST_DIR/state/current")" = "$TEST_DIR/photo.png" ]

echo "Render mode checks passed."
