# Troubleshooting

## The first photo does not appear

Check the Mac jobs and logs:

```sh
launchctl print "gui/$UID/io.github.francolan.kindle-voyage-photo-frame.server"
launchctl print "gui/$UID/io.github.francolan.kindle-voyage-photo-frame.sync"
tail -n 100 "$HOME/Library/Logs/KindleVoyagePhotoFrame/sync.error.log"
tail -n 100 "$HOME/Library/Logs/KindleVoyagePhotoFrame/server.error.log"
```

Confirm that the public album contains a static photo and that the Mac can reach iCloud. Live Photos are rendered from their still-image resource.

## New photos do not arrive

The Mac sync runs every 10 minutes. The Kindle checks for photos when the frame starts and after cycling through the current playlist. Run the Mac sync immediately with:

```sh
RUNTIME="$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime"
node "$RUNTIME/sync.mjs" "$RUNTIME/config.json"
```

Then request a restart, or wait for the Kindle to finish its current cycle:

```sh
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" restart
```

## The Kindle is offline in status

Confirm that both devices are on the same Wi-Fi network, the Mac is awake, and the address in both Kindle config files still matches the Mac. A router DHCP reservation prevents the address from changing.

On the Mac, verify that port 8787 is listening:

```sh
lsof -nP -iTCP:8787 -sTCP:LISTEN
```

If the Mac firewall prompts for Node.js access, allow incoming connections on the private network.

## PagePress or touch does not work

This input helper is specific to the Kindle Voyage. First collect diagnostics:

```sh
RUNTIME="$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime"
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" diagnose
```

The resulting archive appears in `~/Library/Application Support/KindleVoyagePhotoFrame/data/control/diagnostics`. Check `logs/x-events.bin`, `logs/buttons.log`, and the device-property files.

## The Kindle USB prompt does not appear

While the frame is active, it deliberately holds the native UI out of the foreground. Exit photo mode first, wait for the home screen, then reconnect USB. If touch is unavailable, open **Photoframe Exit** or press the power button once.

## Recover over USB

Exit photo mode, connect USB, and rerun `scripts/install-kindle.sh`. It replaces program files and preserves the image cache and application state directories.

## Clear a pending management command

```sh
RUNTIME="$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime"
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" clear
```

Use this when a command should no longer be picked up by a Kindle that has been offline.
