# Kindle Voyage Photo Frame

Turn a jailbroken Kindle Voyage into a Wi-Fi photo frame backed by an iCloud Shared Album and a Mac mini.

The Mac downloads the album, crops each photo for the Voyage's 1072×1448 screen, adds the photo's local place and time when available, converts it to grayscale, and serves a signed manifest over the local network. The Kindle keeps a verified local cache, so the slideshow continues when the Mac is asleep or disconnected.

> **Project status:** personal project released for experimentation. The current build has been tested on one Kindle Voyage running firmware 5.13.6 and one Apple silicon Mac. Other Kindle models and firmware versions are untested.

## Features

- Syncs static photos from a public iCloud Shared Album every 10 minutes.
- Stores photos on the Kindle for offline playback.
- Fits and center-crops images for the Voyage screen.
- Uses Apple MapKit to show a locality such as `Marrickville` or `Arncliffe`, including international place names.
- Shows the capture time in the photo's recorded time zone.
- Uses either PagePress side on the Voyage for previous/next.
- Opens an exit confirmation after a screen tap; tap left to cancel or right to exit.
- Advances automatically every 30 minutes.
- Enables automatic frontlight from 07:00 to 22:00 and turns the frontlight off overnight.
- Supports authenticated wireless status, restart, update, diagnostics, disable, and uninstall commands on the LAN.

## How it works

```mermaid
flowchart LR
    A[iCloud Shared Album] -->|HTTPS| B[Mac sync and renderer]
    B --> C[Authenticated LAN server]
    C -->|Wi-Fi| D[Kindle cache and player]
    D --> E[E Ink display]
```

The album share key and server token stay on your Mac and Kindle. Images and update files require a 256-bit bearer token. The server is intended only for a trusted home network.

## Requirements

- A Kindle Voyage that is already jailbroken and can launch document scripts.
- [FBInk](https://github.com/NiLuJe/FBInk) installed at `/mnt/us/libkh/bin/fbink`.
- A Mac that remains on the same Wi-Fi network as the Kindle when new photos should sync.
- macOS with Node.js and the Xcode Command Line Tools (`swiftc`).
- A public iCloud Shared Album link.

This repository does not include a jailbreak. See [Installation](docs/INSTALL.md) for the tested setup and upstream links.

## Quick start

1. Clone the repository and create a local configuration:

   ```sh
   cp implementation/mac/config.example.json config.local.json
   ```

2. Replace `publicAlbumURL` in `config.local.json` with your iCloud Shared Album link.

3. Install the Mac services:

   ```sh
   ./scripts/install-mac.sh ./config.local.json
   ```

4. Find the Mac's stable LAN address, connect the Kindle over USB, and install the device files:

   ```sh
   ./scripts/install-kindle.sh http://192.168.1.10:8787 /Volumes/Kindle
   diskutil eject /Volumes/Kindle
   ```

5. On the Kindle, open **Photoframe Start** from the library.

Read [Installation](docs/INSTALL.md) before installing on a device you rely on.

## Controls

| Input | Action |
| --- | --- |
| Left PagePress | Previous photo |
| Right PagePress | Next photo |
| Tap the photo | Show exit confirmation |
| Confirmation: tap left / left PagePress | Cancel |
| Confirmation: tap right / right PagePress | Exit to the Kindle home screen |
| Power button | Exit immediately |

The **Photoframe Exit** document remains as a recovery path if touch input is unavailable.

## Wireless management

Commands are written by the Mac and picked up by the Kindle manager, normally within 60 seconds:

```sh
RUNTIME="$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime"
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" status
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" restart
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" update
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" diagnose
```

See [Architecture](docs/ARCHITECTURE.md) for the update and authentication design, and [Troubleshooting](docs/TROUBLESHOOTING.md) for logs and recovery.

## Known limitations

- The iCloud Shared Album reader uses Apple's public web client endpoints, which are not a documented developer API and may change.
- New photos require the Mac services to be running. Existing cached photos continue without the Mac.
- Automatic launch after a Kindle reboot is not installed; open **Photoframe Start** again.
- The renderer is fixed to the Kindle Voyage resolution.
- Photo comments are not displayed.

## License

[MIT](LICENSE). See [Third-party software](THIRD_PARTY.md) for dependencies and upstream projects.
