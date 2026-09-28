#!/bin/sh

set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$ROOT/implementation/kindle-manager/manager.sh"

grep -Fq 'frontlight-test)' "$MANAGER"
grep -Fq 'frontlight_test || return $?' "$MANAGER"
grep -Fq 'command_action=$(field action)' "$MANAGER"
grep -Fq 'case "$command_action" in' "$MANAGER"
grep -Fq "printf '4\\n' > \"\$power_path\"" "$MANAGER"
grep -Fq 'sleep 5' "$MANAGER"
grep -Fq "printf '%s\\n' \"\$original\" > \"\$power_path\"" "$MANAGER"
grep -Fq 'actual_brightness before=%s pulse=%s after=%s' "$MANAGER"

echo "Fixed five-second frontlight pulse and restoration checks passed."
