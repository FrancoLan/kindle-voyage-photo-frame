#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh
if [ -r "$STATE_DIR/frontlight.pid" ]; then
    frontlight_pid=$(cat "$STATE_DIR/frontlight.pid" 2>/dev/null || true)
    [ -z "$frontlight_pid" ] || kill "$frontlight_pid" 2>/dev/null || true
fi
rm -f "$STATE_DIR/frontlight.pid"
sh "$BASE_DIR/frontlight.sh" restore >/dev/null 2>&1 || true
sh "$BASE_DIR/pagepress-mode.sh" restore

if [ -f "$STATE_DIR/prevent-screen-saver.previous" ]; then
    previous=$(cat "$STATE_DIR/prevent-screen-saver.previous" 2>/dev/null || printf '0')
    lipc-set-prop com.lab126.powerd preventScreenSaver "$previous" >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/prevent-screen-saver.previous"
fi
if [ -f "$STATE_DIR/framework-was-running" ]; then
    start framework >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/framework-was-running"
    sleep 2
fi
if [ -f "$STATE_DIR/pillow-was-running" ]; then
    start pillow >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/pillow-was-running"
fi
FRAMEBUFFER_BACKUP=/var/tmp/kindle-photoframe-home.fb
if [ -f "$STATE_DIR/framebuffer-saved" ] && [ -r "$FRAMEBUFFER_BACKUP" ]; then
    cat "$FRAMEBUFFER_BACKUP" > /dev/fb0 2>/dev/null || true
    /usr/sbin/eips -s w=1072,h=1448 -f >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/framebuffer-saved" "$FRAMEBUFFER_BACKUP"
fi
export DISPLAY=${DISPLAY:-:0}
if [ -r "$STATE_DIR/xinput-pagepress-id" ] && command -v xinput >/dev/null 2>&1; then
    pagepress_xid=$(cat "$STATE_DIR/xinput-pagepress-id" 2>/dev/null || true)
    [ -z "$pagepress_xid" ] || xinput set-prop "$pagepress_xid" 'Device Enabled' 1 >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/xinput-pagepress-id"
fi
if [ -f "$STATE_DIR/xmodmap-suppressed" ] && command -v xmodmap >/dev/null 2>&1; then
    while IFS= read -r mapping; do
        [ -z "$mapping" ] || xmodmap -e "$mapping" >/dev/null 2>&1 || true
    done < "$STATE_DIR/xmodmap-pagepress.original"
    rm -f "$STATE_DIR/xmodmap-suppressed" "$STATE_DIR/xmodmap-pagepress.original"
fi
if [ -f "$STATE_DIR/cvm-paused" ]; then
    killall -CONT cvm >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/cvm-paused"
fi
if [ -f "$STATE_DIR/awesome-paused" ]; then
    killall -CONT awesome >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/awesome-paused"
fi
if [ -f "$STATE_DIR/pillow-hidden" ]; then
    lipc-set-prop com.lab126.pillow disableEnablePillow enable >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/pillow-hidden"
fi
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1 || true
sleep 1
lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId":"default_status_bar","function":"nativeBridge.showMe();"}' >/dev/null 2>&1 || true

echo "Kindle UI restore requested."
