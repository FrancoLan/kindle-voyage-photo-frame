# Changelog

## Unreleased

- Reduce the deferred full-screen cleanup refresh after manual Kindle photo changes from 120 seconds to 10 seconds; automatic changes still use an immediate full refresh.
- Prevent portrait-photo orientation regressions by applying EXIF orientation once in ImageIO; remove the redundant pre-rotation step and invalidate v9 render caches.
- Add a pipeline regression check that rejects double rotation.

## Unreleased

- Apply a gentle shadow-lift curve only to photos with a very dark luminance median and sufficient highlight range; leave normal/high-contrast images unchanged.
- Deployed to the Mac renderer on 2026-09-27; regenerated and published all 44 shared photos as manifest `4c78d24e6f4712b6` for Kindle and BOOX.

## 0.4.9 — 2026-09-26

- Check the ambient-light sensor every five seconds and only write state when the frontlight policy changes.

## 0.4.8 — 2026-09-26

- Set the low-light cutoff to 60 lux based on the Voyage sensor reading in the user's current environment.

## 0.4.7 — 2026-09-26

- Ensure a single ambient-light watcher is active and recover automatic brightness in the hysteresis band if the prior schedule left the light off.

## 0.4.6 — 2026-09-26

- Use 50/100 lux off/on thresholds for the Voyage ambient-light sensor, with hysteresis between them.

## 0.4.5 — 2026-09-26

- Turn the frontlight off at low ambient light and restore automatic brightness when the room is bright, using the Voyage ambient-light sensor instead of a time schedule.

## 0.4.4 — 2026-09-26

- Apply JPEG EXIF rotation before rendering shared-album photos, so portrait images remain upright on Kindle and BOOX.

## 0.4.3 — 2026-09-26

- Check for new shared-album photos every minute during playback and refresh the screen only when the playlist changes.

## 0.4.2 — 2026-09-26

- Play newly synchronized photos immediately, then resume the existing playlist sequence.

## 0.4.1 — 2026-09-23

- Made successful Kindle synchronization automatically remove cached renderings absent from the new manifest, matching BOOX behavior.

## 0.4.0 — 2026-09-23

- Added face-priority framing and full-image fallback for groups that cannot fit safely in a portrait crop.
- Replaced white full-image margins with darkened colors sampled from adjacent photo edges; black remains the fallback.
- Added an explicit parity policy with the BOOX N96 edition.

## 0.3.0 — 2026-09-22

- Randomized each automatic photo interval between 10 and 20 minutes.
- Added scoped wireless storage cleanup.
- Added staged fast/manual and full cleanup E Ink refresh behavior.
