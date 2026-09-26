#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

grep -q '^MANUAL_FULL_REFRESH_DELAY_SECONDS=10$' implementation/kindle/config.sh
grep -q '^manual_full_refresh_delay=.*:-10}' implementation/kindle/player.sh
echo "Deferred full-refresh delay checks passed (10 seconds)."
