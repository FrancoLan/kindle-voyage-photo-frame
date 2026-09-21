# Name: Photoframe Test
# Author: Kindle Photoframe Project
# DontUseFBInk

BASE_DIR=/mnt/us/kindle-photoframe
if sh "$BASE_DIR/sync.sh" > "$BASE_DIR/state/manual-test.log" 2>&1; then
    sh "$BASE_DIR/start.sh" >> "$BASE_DIR/state/manual-test.log" 2>&1
else
    printf 'Sync failed. Inspect %s/state/manual-test.log in kTerm.\n' "$BASE_DIR" >> "$BASE_DIR/state/manual-test.log"
fi
