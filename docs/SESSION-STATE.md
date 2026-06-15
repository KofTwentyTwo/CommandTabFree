# SESSION-STATE — CommandTabFree (de-paywalled AltTab fork)

_Updated 2026-06-15. `master` now carries the fork (merged + pushed). Public pre-release **v100.0.3** live; Homebrew tap live._

## What this is
`KofTwentyTwo/alt-tab-free` is a fork of **AltTab** (`lwouis/alt-tab-macos`, GPL-3.0) that neutralizes the v11 Pro paywall so all features are free, rebranded **CommandTabFree**. Strategy: thin, merge-stable patch tracking upstream forever (`docs/PLAN-maintained-fork.md`).

## ✅ DONE
- De-paywall + anti-relock tests + frozen identity (`com.koftwentytwo.commandtabfree`) + brand sweep + placeholder icon — all on **`master`** (was `depaywall-free`, fast-forward merged, HEAD `c7d2d968`, pushed to origin; source is public for GPL §6).
- **Sparkle EdDSA keypair generated.** Public key in `Info.plist` (`SUPublicEDKey`); private key in 1Password item **"CommandTabFree-Sparkle-EdDSA"** + GitHub Actions secret `SPARKLE_ED_PRIVATE_KEY` (env `production`); keychain account `commandtabfree`. `SUEnableAutomaticChecks=false` until a real appcast host exists. This fixed the launch-time "updater failed to start" alert.
- **Public release v100.0.3** (pre-release, **unsigned / not notarized**, universal x86_64+arm64) — ⌘⇥ menu-bar icon, redesigned About (KofTwentyTwo identity + AltTab attribution links), and a **full l10n rebrand** (product name → CommandTabFree across base/en + all ~20 translated languages; upstream attribution kept). Earlier v100.0.0/v100.0.1/v100.0.2 superseded.
- **Homebrew tap live:** `brew install --cask koftwentytwo/tap/commandtabfree` (`KofTwentyTwo/homebrew-tap` → `Casks/commandtabfree.rb`). Cask strips the quarantine (postflight `xattr`) for the unsigned app.
- **Local daily driver installed:** `/Applications/CommandTabFree.app` = **Release** build (no QA menu) signed with the `Local Self-Signed` cert (stable signature → no TCC re-grant loop). Remaining: user grants Accessibility + Screen Recording on first launch.

### Build recipes (verified this session)
- **Local (stable, no QA menu):** `xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData CURRENT_PROJECT_VERSION=<v> CODE_SIGN_IDENTITY="Local Self-Signed" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" OTHER_CODE_SIGN_FLAGS="--timestamp=none" CODE_SIGNING_ALLOWED=YES` (needs `scripts/codesign/setup_local.sh` cert first; user runs it — keychain/admin prompt).
- **Public artifact (ad-hoc):** same recipe but `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`. Zip with `ditto -c -k --sequesterRsrc --keepParent`.
- **GOTCHA — do NOT pass `-configuration Release`.** With `-scheme Release` it splits SPM package outputs and breaks clean-build module-map generation (`build/GeneratedModuleMaps/*.modulemap not found`, then "unable to resolve module Cocoa/Sparkle/..."). Use the scheme only (matches `scripts/build_app.sh`). A failed build can corrupt `build/`; recover with `rm -rf build DerivedData` then rebuild.

## ⏳ NEXT (owner-gated — `docs/EXECUTION-STATUS.md` §3)
- **Apple Developer ID** (long pole): set `CODE_SIGN_IDENTITY` in `config/local.xcconfig`, re-sign Sparkle helpers, notarize → re-release signed/notarized, then drop the cask's quarantine postflight.
- **Real DOMAIN/appcast** (kof22.com ready): replace `fork.invalid` in `local.xcconfig`, serve `/appcast.xml`, flip `SUEnableAutomaticChecks` back on.
- **Wire CI:** `update_appcast.sh` uses the deprecated `sign_update -s` — switch to `--ed-key-file` (or `--account commandtabfree`) for the new key; create `sync`/`conflict`/`chokepoint-refresh` labels; external cron for `upstream_sync.yml`.
- **Real icon artwork** (replace placeholder).

## Gotchas
- Bundle id FROZEN (`com.koftwentytwo.commandtabfree`); keychain/UserDefaults suites derive from it.
- Don't `git revert 9147a4a8` (mixes paywall with a 1869-file reorg).
- Fork version line starts at **v100.0.0** (avoids collision with upstream tags merged into `master`).
- `aws`: use `AWS_PROFILE=kingsrook_root_admin aws …` (the `--profile` flag fails on the local wrapper).
