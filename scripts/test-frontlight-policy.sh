#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kindle-frontlight-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

MOCK_STATE="$TMP/mock-state"
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_STATE" "$MOCK_BIN"
printf '%s\n' 6 > "$MOCK_STATE/flIntensity"
printf '%s\n' 0 > "$MOCK_STATE/flAuto"
printf '%s\n' 20 > "$MOCK_STATE/alsLux"
printf '%s\n' "BASE_DIR=$TMP/device" "STATE_DIR=$TMP/device/state" \
    'FRONTLIGHT_DARK_LUX=60' 'FRONTLIGHT_BRIGHT_LUX=100' \
    'FRONTLIGHT_DEFAULT_LEVEL=4' 'FRONTLIGHT_CHECK_SECONDS=60' \
    > "$TMP/config.sh"

cat > "$MOCK_BIN/lipc-get-prop" <<'MOCK'
#!/bin/sh
cat "$MOCK_STATE/$3"
MOCK
cat > "$MOCK_BIN/lipc-set-prop" <<'MOCK'
#!/bin/sh
printf '%s\n' "$4" > "$MOCK_STATE/$3"
MOCK
chmod +x "$MOCK_BIN/lipc-get-prop" "$MOCK_BIN/lipc-set-prop"

apply() {
    PATH="$MOCK_BIN:$PATH" MOCK_STATE="$MOCK_STATE" \
        KINDLE_PHOTOFRAME_CONFIG="$TMP/config.sh" \
        sh "$ROOT/implementation/kindle/frontlight.sh" apply
}
assert_value() {
    actual=$(cat "$MOCK_STATE/$1")
    [ "$actual" = "$2" ] || { echo "$1 expected $2, got $actual" >&2; exit 1; }
}

apply
assert_value flIntensity 0
[ -f "$TMP/device/state/frontlight-forced-off" ]

printf '%s\n' 80 > "$MOCK_STATE/alsLux"
apply
assert_value flIntensity 0
[ -f "$TMP/device/state/frontlight-forced-off" ]

printf '%s\n' 150 > "$MOCK_STATE/alsLux"
apply
assert_value flIntensity 6
assert_value flAuto 1
[ ! -f "$TMP/device/state/frontlight-forced-off" ]

printf '%s\n' invalid > "$MOCK_STATE/alsLux"
apply
assert_value flIntensity 6
assert_value flAuto 1

PATH="$MOCK_BIN:$PATH" MOCK_STATE="$MOCK_STATE" \
    KINDLE_PHOTOFRAME_CONFIG="$TMP/config.sh" \
    sh "$ROOT/implementation/kindle/frontlight.sh" restore
assert_value flIntensity 6
assert_value flAuto 0

printf '%s\n' 0 > "$MOCK_STATE/flIntensity"
printf '%s\n' 0 > "$MOCK_STATE/flAuto"
printf '%s\n' 75 > "$MOCK_STATE/alsLux"
apply
assert_value flIntensity 4
assert_value flAuto 1

echo "Frontlight ambient-light policy checks passed."
