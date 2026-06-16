# SESSION-STATE — CommandTabFree (de-paywalled AltTab fork)

_Updated 2026-06-16. `master` carries the fork; the **full CI/CD publishing pipeline + auto-update are LIVE** — signed + notarized **v100.2.0** released (Gatekeeper-accepted), Sparkle feed served on GitHub Pages. Homebrew tap live._

## ✅ SIGNED + NOTARIZED RELEASE LIVE

The complete release pipeline ran green end-to-end (run `27643432063`, commit `2f9fac17`): cert import → **signed** `build_app.sh` (Developer ID **`James Maes (2X834TJ5MA)`**) → notarize + staple → appcast→gh-pages → semantic-release → GitHub Release. **[v100.1.0](https://github.com/KofTwentyTwo/CommandTabFree/releases/tag/v100.1.0)** is published; the downloaded asset verifies `spctl` = "accepted, source=Notarized Developer ID" and `stapler validate` passes (offline-clean, no quarantine prompt). Non-release pushes stay green via the ad-hoc `build_app.sh` path (run `27634828800`).

**How signing is wired:** `config/local.xcconfig` sets `CODE_SIGN_IDENTITY` + `CODE_SIGN_STYLE = Manual` + `TEAM_ID 2X834TJ5MA`; the vendored Sparkle helpers (`vendor/Sparkle/Helpers/*`) are committed **re-signed** under the same Developer ID; `setup_ci_master.sh` imports the cert with an optional `APPLE_P12_PASSWORD`. The release secrets (`APPLE_P12_CERTIFICATE`/`APPLE_P12_PASSWORD`/`APPLE_ID`/`APPLE_PASSWORD`/`APPLE_TEAM_ID` + `SPARKLE_ED_PRIVATE_KEY`) are set in the `production` env. Getting here also required two CI fixes earlier this session: `d1e1b296` (regenerate base `Localizable.strings` to clear the genstrings gate) and `6070f0cb` (ad-hoc build until the cert existed).

**Auto-update is LIVE (shipped in v100.2.0):** `DOMAIN = koftwentytwo.github.io/CommandTabFree`, `SUEnableAutomaticChecks = true`, the in-tree `appcast.xml` skeleton removed + gitignored. GitHub Pages serves `https://koftwentytwo.github.io/CommandTabFree/appcast.xml` (gh-pages branch, published by `update_appcast.sh`); the feed carries v100.1.0 + v100.2.0 enclosures. A kof22.com custom domain can be added later (GitHub redirects the github.io URL — no broken builds). **Homebrew cask** bumped to v100.2.0 + quarantine-strip postflight dropped (`KofTwentyTwo/homebrew-tap`). **Release-gate decoupled:** the sign/notarize/release apparatus is gated on a `will-release` signal (empty `VERSION.txt` ⇒ no release), so docs/ci pushes build+test without cutting a release or needing `[skip ci]` (ci_cd.yml).

**Remaining (owner-gated, NOT automatable):**
- **Upstream-sync**: provision `SYNC_BOT_TOKEN` + an external `repository_dispatch` cron; re-wire the `.fork-sync-state` cursor advance into the sync-merge flow (recording the UPSTREAM tag). `.fork-sync-state` = `v11.3.0`; the 3 sync labels exist.
- **(Optional)** kof22.com custom domain for the appcast (one DNS CNAME → `koftwentytwo.github.io`).

**Repo facts:** GitHub = `KofTwentyTwo/CommandTabFree` (local dir `~/Git.Local/kof22/alt-tab-free`, SSH remote). Latest release **v100.2.0** (signed + notarized + auto-updating). ⌘⇥ icon FINAL. Owner-gated checklist: `docs/TODO.md`.


## What this is
`KofTwentyTwo/CommandTabFree` is a fork of **AltTab** (`lwouis/alt-tab-macos`, GPL-3.0) that neutralizes the v11 Pro paywall so all features are free, rebranded **CommandTabFree**. Strategy: thin, merge-stable patch tracking upstream forever (`docs/PLAN-maintained-fork.md`).

## ✅ DONE
- De-paywall + anti-relock tests + frozen identity (`com.koftwentytwo.commandtabfree`) + brand sweep + ⌘⇥ icon (final) — all on **`master`** (was `depaywall-free`, fast-forward merged, HEAD `c7d2d968`, pushed to origin; source is public for GPL §6).
- **Sparkle EdDSA keypair generated.** Public key in `Info.plist` (`SUPublicEDKey`); private key in 1Password item **"CommandTabFree-Sparkle-EdDSA"** + GitHub Actions secret `SPARKLE_ED_PRIVATE_KEY` (env `production`); keychain account `commandtabfree`. `SUEnableAutomaticChecks=false` until a real appcast host exists. This fixed the launch-time "updater failed to start" alert.
- **Public release v100.0.3** (pre-release, **unsigned / not notarized**, universal x86_64+arm64) — ⌘⇥ menu-bar icon, redesigned About (KofTwentyTwo identity + AltTab attribution links), and a **full l10n rebrand** (product name → CommandTabFree across base/en + all ~20 translated languages; upstream attribution kept). Earlier v100.0.0/v100.0.1/v100.0.2 superseded.
- **Homebrew tap live:** `brew install --cask koftwentytwo/tap/commandtabfree` (`KofTwentyTwo/homebrew-tap` → `Casks/commandtabfree.rb`). Cask strips the quarantine (postflight `xattr`) — was needed for the unsigned v100.0.x; now that v100.1.0 is notarized, drop that postflight and bump the cask.
- **CI/CD wired** (GitHub Actions), **fully green on push** (run `27634828800`, commit `6070f0cb`). Passing: Guard A/B/C, commitlint, generated-files gate, version compute, `run_tests.sh`, ad-hoc `build_app.sh`. The sign/notarize/appcast/semantic-release/gh-release tail is gated on a `release-gate` step that **auto-activates** when `APPLE_*` secrets are added — secrets were added 2026-06-16 and the **full tail is now proven** (signed+notarized **v100.1.0**, run `27643432063`). Fixed this session (2026-06-16): regenerated base `Localizable.strings` to clear the genstrings gate; build ad-hoc until the owner provisions the Apple cert (was inheriting upstream's Developer ID → exit 65). Earlier this session: Guard B grep now matches the shipped `guard false else { return .pro }` patch (was checking the PLAN's never-shipped `if false`/`alt-tab-free [depaywall]` form); `update_appcast.sh` → `--ed-key-file`; commitlint sync-merge `ignores`; dropped upstream-only scripts (AppCenter/website); commit headers must be ≤72 chars. Full status: `docs/CICD-STATUS.md`.
- **Local daily driver installed:** `/Applications/CommandTabFree.app` = **Release** build (no QA menu) signed with the `Local Self-Signed` cert (stable signature → no TCC re-grant loop). Remaining: user grants Accessibility + Screen Recording on first launch.

### Build recipes (verified this session)
- **Local (stable, no QA menu):** `xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData CURRENT_PROJECT_VERSION=<v> CODE_SIGN_IDENTITY="Local Self-Signed" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" OTHER_CODE_SIGN_FLAGS="--timestamp=none" CODE_SIGNING_ALLOWED=YES` (needs `scripts/codesign/setup_local.sh` cert first; user runs it — keychain/admin prompt).
- **Public artifact (ad-hoc):** same recipe but `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`. Zip with `ditto -c -k --sequesterRsrc --keepParent`.
- **GOTCHA — do NOT pass `-configuration Release`.** With `-scheme Release` it splits SPM package outputs and breaks clean-build module-map generation (`build/GeneratedModuleMaps/*.modulemap not found`, then "unable to resolve module Cocoa/Sparkle/..."). Use the scheme only (matches `scripts/build_app.sh`). A failed build can corrupt `build/`; recover with `rm -rf build DerivedData` then rebuild.

## ⏳ NEXT (owner-gated — `docs/EXECUTION-STATUS.md` §3)
- **Apple Developer ID** (long pole): set `CODE_SIGN_IDENTITY` in `config/local.xcconfig`, re-sign Sparkle helpers, notarize → re-release signed/notarized, then drop the cask's quarantine postflight.
- **Real DOMAIN/appcast** (kof22.com ready): replace `fork.invalid` in `local.xcconfig`, serve `/appcast.xml`, flip `SUEnableAutomaticChecks` back on.
- **Wire CI:** `update_appcast.sh` uses the deprecated `sign_update -s` — switch to `--ed-key-file` (or `--account commandtabfree`) for the new key; create `sync`/`conflict`/`chokepoint-refresh` labels; external cron for `upstream_sync.yml`.
## Gotchas
- Bundle id FROZEN (`com.koftwentytwo.commandtabfree`); keychain/UserDefaults suites derive from it.
- Don't `git revert 9147a4a8` (mixes paywall with a 1869-file reorg).
- Fork version line starts at **v100.0.0** (avoids collision with upstream tags merged into `master`).
- `aws`: use `AWS_PROFILE=kingsrook_root_admin aws …` (the `--profile` flag fails on the local wrapper).
