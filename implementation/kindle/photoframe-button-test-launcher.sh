# Name: Photoframe Button Test
# Author: Kindle Photoframe Project
# DontUseFBInk

BASE_DIR=/mnt/us/kindle-photoframe
mkdir -p "$BASE_DIR/state"
nohup sh "$BASE_DIR/diagnose-buttons.sh" > "$BASE_DIR/state/button-test.log" 2>&1 &
exit 0
