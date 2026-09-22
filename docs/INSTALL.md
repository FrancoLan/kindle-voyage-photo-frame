# Installation

## 1. Prepare the Kindle

The tested device is a Kindle Voyage on firmware 5.13.6. It was prepared with:

- [WinterBreak2 v1.1.0](https://github.com/KindleModding/Winterbreak2/releases/tag/v1.1.0)
- KindleForge/KPM 0.2.2 for document script launching
- [FBInk](https://github.com/NiLuJe/FBInk) 1.25.0 at `/mnt/us/libkh/bin/fbink`

Follow the current instructions from each upstream project. Jailbreak steps depend on the Kindle model and firmware and are deliberately not copied into this repository.

Before continuing, confirm that your Kindle appears as a USB volume with a `documents` directory and that FBInk exists at the expected path.

## 2. Prepare the Mac

Install Node.js and Apple's command line tools:

```sh
node --version
swiftc --version
```

In Photos, create or choose a Shared Album and enable **Public Website**. Copy the generated `https://photos.icloud.com/shared/album/...` URL. Anyone with that URL can view the shared album, so use an album created for the frame.

Clone this repository, then make a private config file:

```sh
git clone https://github.com/FrancoLan/kindle-voyage-photo-frame.git
cd kindle-voyage-photo-frame
cp implementation/mac/config.example.json config.local.json
```

Edit only `publicAlbumURL` at first. `listenHost` must remain `0.0.0.0` for the Kindle to reach the service.

Run:

```sh
./scripts/install-mac.sh ./config.local.json
```

The installer:

- compiles the two Swift helpers locally;
- installs runtime files below `~/Library/Application Support/KindleVoyagePhotoFrame`;
- creates a random 256-bit server token with mode `0600`;
- installs a persistent server and a 10-minute sync job in `~/Library/LaunchAgents`;
- runs the initial photo sync.

Give the Mac a stable DHCP reservation in your router. Find its current Wi-Fi address with:

```sh
ipconfig getifaddr en0
```

If your Mac uses another interface, `networksetup -listallhardwareports` shows the device name.

## 3. Install on the Kindle

Connect the Kindle by USB and wait for `/Volumes/Kindle` to appear. Replace the sample address below with the Mac's LAN address:

```sh
./scripts/install-kindle.sh http://192.168.1.10:8787 /Volumes/Kindle
diskutil eject /Volumes/Kindle
```

The installer copies the player, wireless manager, launch documents, native Voyage input helpers, and the shared authentication token. After the Kindle returns to its home screen, open **Photoframe Start**.

The first start needs the Mac server so the Kindle can download at least one image. Later starts can use the cached photos.

## 4. Check the installation

On the Mac:

```sh
RUNTIME="$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime"
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" status
```

Within about five minutes, status should show the Kindle, `appState: running`, and the version from `implementation/kindle/VERSION`.

Test both PagePress sides, a screen tap followed by cancel, and a screen tap followed by exit. Start the frame again from **Photoframe Start**.

## Configuration

Device settings live in `implementation/kindle/config.sh` and are copied during installation:

| Setting | Default | Meaning |
| --- | ---: | --- |
| `INTERVAL_MIN_SECONDS` | `600` | Minimum automatic photo interval |
| `INTERVAL_MAX_SECONDS` | `1200` | Maximum automatic photo interval |
| `MANUAL_FULL_REFRESH_DELAY_SECONDS` | `120` | Delay before a manual change receives a full cleanup refresh |
| `DAY_START_HOUR` | `7` | Start automatic frontlight |
| `NIGHT_START_HOUR` | `22` | Turn frontlight off |
| `DAY_FRONTLIGHT_LEVEL` | `4` | Fallback level before auto mode adjusts |
| `FRONTLIGHT_CHECK_SECONDS` | `60` | Schedule check interval |

Change these in your clone and rerun `scripts/install-kindle.sh` over USB. Wireless updates preserve the device's local configuration.

## Updating

Pull the latest repository version, reinstall the Mac runtime, then publish a wireless update:

```sh
git pull
./scripts/install-mac.sh ./config.local.json
RUNTIME="$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime"
node "$RUNTIME/manage.mjs" "$RUNTIME/config.json" update
```

The Kindle verifies the update archive size and SHA-256 hash before applying it. It keeps a local backup of the files replaced by each update.
