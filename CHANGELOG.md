# Changelog

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
