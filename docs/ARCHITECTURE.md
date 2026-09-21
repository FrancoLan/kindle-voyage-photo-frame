# Architecture

## Mac components

- `icloud-source.mjs` resolves the public share and reads all photo records.
- `sync.mjs` downloads each source image, extracts capture metadata, asks MapKit for a locality, renders a 1072×1448 grayscale PNG, and publishes a SHA-256 manifest.
- `metadata-overlay.swift` draws the place and capture time at the lower-right edge.
- `reverse-geocode.swift` converts coordinates into a human-readable locality with Apple MapKit.
- `server.mjs` serves manifests, images, commands, update archives, status, and diagnostic uploads.
- `manage.mjs` creates authenticated commands and reproducible update archives.

The server and sync process are macOS LaunchAgents. Rendered assets, token, commands, and status live below `~/Library/Application Support/KindleVoyagePhotoFrame/data` and are excluded from Git.

## Kindle components

- `player.sh` owns the slideshow lifecycle and restores the native UI on exit.
- `sync.sh` verifies the manifest, byte length, path, and SHA-256 of every cached image.
- `kindle-xcontrols` translates Voyage X11 PagePress and touch events into simple commands.
- `buttons.sh` routes those commands and watches the hardware power button.
- `frontlight.sh` applies the day/night schedule and restores the user's prior settings on exit.
- `manager.sh` polls for authenticated management commands and uploads status.
- `supervisor.sh` keeps one manager process alive without starting the photo frame itself.

The two ARM helper binaries are included so installation does not require an ARM toolchain. Their source and deterministic builder are in `implementation/kindle/native`.

## Data flow

1. The Mac sync process creates content-addressed PNG files and a manifest every 10 minutes.
2. The Kindle downloads only missing or changed files and retains them in `/mnt/us/kindle-photoframe/cache`.
3. The player copies the current playlist before rendering, so a background sync cannot alter the list mid-cycle.
4. When a new manifest completes, the player reloads the playlist and shows the first updated photo.

PagePress changes draw immediately with a non-flashing GC16 update. The player keeps the cleanup deadline in its main event loop; another manual change replaces that deadline, so a stale timer cannot refresh an older photo. If the same photo remains visible for two minutes, FBInk performs a flashing full-screen GC16 refresh against the existing framebuffer. The 30-minute automatic transition uses flashing GC16 immediately.

## Wireless control

The Kindle polls `/v1/control/command`. Each command has a UUID, expiry, and action. The manager stores the last completed UUID to make command processing idempotent. Update archives include a manifest of every allowed destination, size, and SHA-256 hash. Paths outside the application, manager, and two launch documents are rejected.

Diagnostics are capped at 1 MiB and contain application logs, selected power/device properties, process state, disk use, and system version. They do not include the authentication token.

The cleanup command is deliberately limited to manager rollback directories, interrupted command staging paths, and image-cache files absent from the active playlist. It never traverses the Kindle library or removes the active application, configuration, token, or current playlist.

## Authentication boundary

All HTTP routes require `Authorization: Bearer <token>`, including health and images. The token is generated from 32 random bytes and copied to the Kindle during USB installation. The protocol uses HTTP because the intended boundary is a trusted private LAN; keep port 8787 behind the router firewall and do not expose it to the internet.
