# Maintenance handover

## 2026-09-28 ambient-frontlight follow-up (deployed; dark-room visual check pending)

- A live diagnosis after the user restarted the frame read 84 lux and reported `hold-auto`, `flAuto=1`, and `flIntensity=24` (maximum). With the previous 60/100 lux thresholds, a fresh session in the hysteresis band defaulted to automatic light. This explains why the frontlight remained on in the user's dim room; the earlier `bl_power`/brightness mismatch was not sufficient by itself to identify the cause.
- The fix raises the off/on thresholds to 100/150 lux, records whether the current session is holding automatic mode, and makes an uninitialized session in the band start dark. Values in the band then preserve the chosen state. The policy regression test covers 84 lux, cold-start behavior, and both hysteresis directions.
- Full `./scripts/check.sh` and PR #2's `Project checks` passed. PR #2 was merged as `46c7da4` and deployed wirelessly. After waking the device and starting the frame, a diagnostic at 2026-09-28 12:24:42 UTC confirmed `appState=running`, the installed 100/150 lux thresholds, and frontlight script SHA-256 `2e0c6e13c5b58a36415278739799fc940b1e82da9e1e5afb58ad2ae37e185c33`, matching the merged implementation.
- The live sensor read 258 lux, with policy `bright`, `flAuto=1`, `flIntensity=4/24`, and `bl_power=0`, consistent with the bright-side policy. Low-light shutoff and the user's visual confirmation remain pending. The device's unchanged legacy version string does not identify this update; use the script hash and thresholds instead.

## Repository workflow

- `main` is the deployable and release branch. Do not develop directly on it.
- Use a short-lived `fix/*`, `feat/*`, or `chore/*` branch for every change, including documentation, and open a pull request back to `main`.
- The required `Project checks` job runs on pinned macOS 26 and executes `git diff --check` plus the repository's complete `./scripts/check.sh` suite.
- Pull requests do not replace device testing. Changes to PagePress, touch handling, frontlight policy, rendering, synchronization, updates, installation, or recovery must be verified on the Kindle Voyage before release.
- Keep shared behavior aligned with the BOOX repository. A cross-device change should use linked pull requests in both repositories; document any intentional divergence in `docs/CROSS_DEVICE_PARITY.md`.
- Create immutable version tags and GitHub Releases only from merged, verified `main`. Never move an existing release tag.
- For an urgent device outage, an administrator may bypass branch protection to restore service, but must immediately reconcile the exact tested change through a `hotfix/*` pull request.

## CI boundary

CI validates shell and JavaScript syntax, the Python helper, renderer behavior, orientation, cleanup, frontlight policy, diagnostic behavior, Swift compilation, and privacy checks. It cannot validate the Kindle display, ambient-light sensor, PagePress hardware, Wi-Fi behavior, or deployed signing/authentication state.
