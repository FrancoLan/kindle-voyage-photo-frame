# Maintenance handover

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
