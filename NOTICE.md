# NOTICE — Statement of Changes (GPL-3.0 §5(a))

This file carries the prominent notice, required by GNU GPL v3.0 §5(a), that this work
has been modified, and gives the relevant date. It is a **living document**: whenever a
sync from upstream changes this fork's modification surface, update the change list and
the date below (see `docs/PLAN-maintained-fork.md` §6.2).

**Forked from:** [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos) v11.3.0,
© Louis Pontoise, licensed GPL-3.0.

**Modified by:** the CommandTabFree fork. This fork neutralizes the AltTab Pro paywall so that
all features are free.

**Date of modification:** 2026-06-10.

**License:** CommandTabFree is released under the **GNU General Public License v3.0**, the same
license as upstream. The full license text is in [`LICENCE.md`](LICENCE.md), which is kept
byte-for-byte identical to upstream and is never edited.

## Changes made in this fork

- **`LicenseManager.computeState`** (`src/pro/license/LicenseManager.swift`) — forced to
  return `.pro`, opening every Pro feature gate. This is the single live license-state
  producer, so this one change unlocks all paywalled features.
- **`LicenseCookie.syncLicenseCookie`** (`src/pro/license/LicenseCookie.swift`) — made a
  no-op, so no license cookie is written to the upstream domain.
- **`AppCenterCrash.init`** (`src/vendors/AppCenterCrashes.swift`) — telemetry disabled;
  AppCenter is never started.
- **`App.handleCustomUrl`** (`src/App.swift`) — the `activate` deep-link handler is
  disabled, so a crafted `…://activate?license_key=…` URL can no longer POST the machine
  hardware fingerprint to a license backend.

The upstream copyright, contributor credits (`docs/contributors.md`), and third-party
acknowledgments (`docs/acknowledgments.md`) are retained unchanged.
