# Cross-device parity

The Kindle Voyage and BOOX N96 editions share one product specification. Shared photo-frame behavior must be designed, implemented, tested, and documented for both devices by default.

The following behavior stays aligned:

- One iCloud Shared Album and content manifest.
- A newly randomized 10–20 minute automatic interval for every photo.
- Locality and capture-local time overlays.
- Face-priority framing and full-image fallback when people cannot fit safely.
- Darkened edge-sampled fill for unused canvas areas, with black as the fallback and no default white letterbox.
- Verified offline caching and stale-render cleanup.
- Authenticated LAN management, minimal diagnostics, and integrity-checked updates.

Hardware-specific implementations may differ: the Kindle uses FBInk, PagePress, jailbreak scripts, and Voyage frontlight controls; the BOOX uses an Android Activity, Android input, and the system package installer. A plain N96 has no official frontlight equivalent.

Hardware differences must not silently change the user-visible result. Any intentional behavior difference requires explicit user approval before implementation and must be recorded in both repositories' handover documentation.
