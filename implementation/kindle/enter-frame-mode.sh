#!/bin/sh

set -u
. /mnt/us/kindle-photoframe/config.sh
mkdir -p "$STATE_DIR"
sh "$BASE_DIR/frontlight.sh" save

# USB drive mode can stop the Kindle Java framework. Xorg stays alive in that
# state, so the X11 helper can acquire its grabs while still receiving no real
# touch or Voyage PagePress events. Ensure cvm is back before creating the
# frame controls.
UI_RUNTIME_LOG="$STATE_DIR/ui-runtime.log"
if ! pidof cvm >/dev/null 2>&1; then
    echo "cvm missing; starting framework." >> "$UI_RUNTIME_LOG"
    start framework >> "$UI_RUNTIME_LOG" 2>&1 || true
    framework_wait=0
    while ! pidof cvm >/dev/null 2>&1 && [ "$framework_wait" -lt 15 ]; do
        sleep 1
        framework_wait=$((framework_wait + 1))
    done
fi
if pidof cvm > "$STATE_DIR/cvm.pid" 2>/dev/null; then
    echo "cvm ready: $(cat "$STATE_DIR/cvm.pid")" >> "$UI_RUNTIME_LOG"
else
    echo "WARNING: cvm did not start within 15 seconds." >> "$UI_RUNTIME_LOG"
fi

if [ ! -f "$STATE_DIR/prevent-screen-saver.previous" ]; then
    lipc-get-prop com.lab126.powerd preventScreenSaver > "$STATE_DIR/prevent-screen-saver.previous" 2>/dev/null || printf '0\n' > "$STATE_DIR/prevent-screen-saver.previous"
fi
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true

FRAMEBUFFER_BACKUP=/var/tmp/kindle-photoframe-home.fb
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >/dev/null 2>&1 || true
lipc-set-prop com.lab126.pillow interrogatePillow '{"pillowId":"default_status_bar","function":"nativeBridge.showMe();"}' >/dev/null 2>&1 || true
sleep 1
if dd if=/dev/fb0 of="$FRAMEBUFFER_BACKUP" bs=1088 count=1448 2>/dev/null; then
    touch "$STATE_DIR/framebuffer-saved"
fi
if lipc-set-prop com.lab126.pillow disableEnablePillow disable >/dev/null 2>&1; then
    touch "$STATE_DIR/pillow-hidden"
fi

INPUT_LOG="$STATE_DIR/input-suppression.log"
: > "$INPUT_LOG"
echo "PagePress suppression is provided by the EVIOCGRAB input helper." >> "$INPUT_LOG"

echo "Frame mode entered."
