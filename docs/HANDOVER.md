# Maintenance handover

Updated 2026-10-05. This describes the last verified deployment; query fresh status before treating any device as online. Earlier investigation history remains available in Git history. Private deployment records are not included.

## Current release and verification

- Release [v0.4.11](https://github.com/FrancoLan/kindle-voyage-photo-frame/releases/tag/v0.4.11) is published from `main`, with a source ZIP and SHA-256 checksum. PR #5 merged as `b4bc19f`.
- BOOX companion [v1.2.6](https://github.com/FrancoLan/boox-n96-photo-frame/releases/tag/v1.2.6) includes battery diagnostics and primary/backup endpoint selection; its APK uses the original deployment signing key.
- Complete project checks and CI passed, including 11 Node regressions and shell fallback cases. Physical tests verified all four charging shortcut directions, background and locked-session shutdown, charging samples, backup communication after Ethernet removal, and return to the primary after reconnection.
- Final dual-interface settings have not been reboot-tested. Router address reservations must be verified separately; an unanswered ping does not prove an address is reserved.

## Runtime and device behavior

The Mac synchronizes the shared album every minute. Both clients keep offline caches, show photos for a random 10–20 minutes, prioritize newly synchronized photos once, then resume their previous order. Shared rendering includes a single EXIF orientation transform, face-aware framing, dark edge-colored fill, location/local capture time with weekdays, and restrained shadow lifting.

Kindle uses FBInk and native input helpers. PagePress bars move forward and dots backward. Touch opens an exit confirmation; the power key exits. Start/Exit launchers remain on the home screen. Kindle requires Photoframe Start after boot; do not enable unverified automatic startup.

Kindle performs a full refresh ten seconds after quick manual navigation. BOOX performs its firmware full refresh about 100 ms after drawing. Kindle frontlight switches off below the low-light threshold and restores automatic mode above the high threshold; an uninitialized hysteresis-band session starts dark. These device-specific differences are recorded in [CROSS_DEVICE_PARITY.md](CROSS_DEVICE_PARITY.md).

The deployed Mac runtime can differ from a fresh public installer in directory and LaunchAgent names. Identify the existing runtime before installing; avoid duplicate services. Keep the Mac powered on, logged in, networked and awake. Locking is supported; restarting with FileVault still requires unlocking and login.

## Network fallback

- Ethernet and Wi-Fi must use different stable LAN addresses. Put Ethernet first in the service order and verify router reservations/exclusions.
- Mac `listenHosts` contains only the explicit addresses. `bind-interfaces.mjs` checks assigned addresses every ten seconds, removes vanished listeners and recreates them after reconnection. Authentication remains required; an unauthenticated HTTP 401 means the endpoint is reachable.
- Both Kindle configuration files use `SERVER_URL` for the primary and optional `SERVER_FALLBACK_URL` for the backup. Deploy the helper alongside management and sync scripts; keep the future update package source aligned.
- Each cycle probes an authenticated manifest, prefers the primary, uses the backup on failure, and retries the primary on later cycles. Offline caches remain usable if both fail.
- Validate with new device reports and server-side `localAddress`, after physical cable removal and again after reconnection. Historical heartbeats cannot prove current connectivity. Other Mac services require their own fallback support.

## Charging and logs

The shared controller turns a verified HomeKit plug on strictly below 40% and off strictly above 80%; boundaries and the interval preserve state. It checks every minute, rejects telemetry older than ten minutes, and reasserts a successful command at most every ten minutes. Configuration defaults to disabled until shortcuts are verified. See [CHARGING.md](CHARGING.md).

Separate private JSONL files record second-precision UTC/local timestamps, battery and source report times. Command completion/failure is distinct from an observed charging transition. Charging samples require fresh readings every five minutes; missing telemetry produces an unavailable event. Manual plug actions are observed only on subsequent device reports, so their exact physical action time is unknown.

Background command timeouts were fixed by closing subprocess stdin; do not assume lock-screen incompatibility. The charging LaunchAgent is a periodic task: a successful exit between runs is healthy. Preserve its state and active lock rather than deleting them to force repeated actions.

## Maintenance and recovery

Query `status` first, checking `receivedAt`, `appState`, battery and `localAddress`; queue one `diagnose` when fresh evidence is needed and wait for its UUID instead of repeatedly replacing pending commands. Check network/listeners, server errors, diagnostics, then charging errors and per-device logs.

Before deployment, retain configuration, tokens, device scripts, runtime files and logs in a private backup with checksums. On FAT-mounted devices copy contents and verify readback; metadata-copy failures can leave partial updates. Safely eject before starting the frame. Restore only necessary files, preserve current endpoint configuration, and align the future update source. A USB user-file backup is not a system recovery image.

Use short-lived branches and PRs into `main`; run the complete `scripts/check.sh`, CI and relevant physical tests before release. Keep shared behavior aligned through linked BOOX PRs; obtain approval for new user-visible differences. Do not force-push `main` or move release tags.

Never publish private configuration, album links, credentials, photos, diagnostic/battery logs, device identifiers or signing keys. Do not modify iCloud originals or leave unauthenticated maintenance services running. Update current sections directly; preserve detailed history in Git or private records rather than appending conflicting current-state summaries.

GitHub documentation, PR titles/descriptions and release notes use English. Private local handovers may use the operator’s preferred language.
