# Name: Photoframe Start
# Author: Kindle Photoframe Project
# DontUseFBInk

BASE_DIR=/mnt/us/kindle-photoframe
mkdir -p "$BASE_DIR/state"
[ ! -f /mnt/us/kindle-manager/start.sh ] || sh /mnt/us/kindle-manager/start.sh >/dev/null 2>&1 || true
nohup sh -c 'sleep 5; sh /mnt/us/kindle-photoframe/start.sh' > "$BASE_DIR/state/manual-start.log" 2>&1 &
exit 0
