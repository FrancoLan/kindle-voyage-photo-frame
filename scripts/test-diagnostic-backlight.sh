#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

for value in brightness actual_brightness max_brightness bl_power; do
    grep -Fq "/sys/class/backlight/max77696-bl/$value" implementation/kindle-manager/manager.sh
done
echo "Backlight hardware diagnostic coverage checks passed."
