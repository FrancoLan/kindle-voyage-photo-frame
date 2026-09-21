# Name: Photoframe Exit
# Author: Kindle Photoframe Project
# DontUseFBInk

BASE_DIR=/mnt/us/kindle-photoframe
mkdir -p "$BASE_DIR/state"
sh "$BASE_DIR/stop.sh" > "$BASE_DIR/state/manual-stop.log" 2>&1
