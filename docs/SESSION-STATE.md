# SESSION-STATE — CommandTabFree (de-paywalled AltTab fork)

_Updated 2026-06-16. `master` carries the fork; **push CI is fully green** (gate + tests + ad-hoc build; release tail skips until owner secrets). Public pre-release **v100.0.3** live; Homebrew tap live._

## ✅ CI GREEN — remaining work is owner-gated only

**Push CI is fully green** as of 2026-06-16 (run `27634828800`, commit `6070f0cb`). Every owner-secret-independent step passes — Guard A/B/C, commitlint, the genstrings generated-files gate, version compute, `run_tests.sh`, and an **ad-hoc** `build_app.sh`. The entire release tail (notarize / appcast / semantic-release / gh-release / sync-state advance) SKIPS cleanly until the owner adds the Apple/Sparkle secrets — by design (CICD-STATUS bucket A).

Two fixes landed this session:
1. **`fix(l10n)` `d1e1b296`** — regenerated the base `resources/l10n/Localizable.strings` from source. It had drifted after the About redesign + brand sweep; the gate regenerates via `genstrings` and diffs (the file is a pure generated mirror — keys ARE the English source literals, so it can't be hand-branded). The diff was verified byte-for-byte against CI's own Xcode 26.0.1 genstrings output before pushing. Attribution preserved (it's in the source, not hand-edited). Dead paywall strings stay upstream-branded (merge-surface minimal).
2. **`fix(ci)` `6070f0cb`** — the Release build was inheriting upstream's Developer ID (`Developer ID Application: Louis Pontoise (QXD7GW8FHY)`, in `config/release.xcconfig:5`) and failing on CI with exit 65 (no such cert). `build_app.sh` now forwards xcodebuild overrides (`"$@"`), and `ci_cd.yml` builds **ad-hoc** (`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO OTHER_CODE_SIGN_FLAGS=--timestamp=none`) when the release gate is not signing-ready. Auto-switches to signed when the owner provisions the cert AND sets the fork Developer ID in `config/local.xcconfig` (currently commented, lines 45-50).

**Owner-gated next steps (NOT automatable; details in EXECUTION-STATUS §3.3–3.5 + CICD-STATUS.md bucket C):** Apple Developer ID → `APPLE_P12_CERTIFICATE`/`APPLE_ID`/`APPLE_PASSWORD`/`APPLE_TEAM_ID` in the `production` env (unblocks signed+notarized releases) **and** set `CODE_SIGN_IDENTITY` in `config/local.xcconfig`; real `DOMAIN`/appcast host to replace `fork.invalid`; `SYNC_BOT_TOKEN` (auto upstream-sync PRs); external cron for `upstream_sync.yml`. The 3 sync labels (`sync`/`conflict`/`chokepoint-refresh`) were created this session. Already set: `SPARKLE_ED_PRIVATE_KEY` + `production` env + Sparkle public key in Info.plist.

**Repo facts:** GitHub = `KofTwentyTwo/CommandTabFree` (renamed from alt-tab-free; local dir is still `~/Git.Local/kof22/alt-tab-free`, SSH remote points at CommandTabFree). Latest release v100.0.3 (zip + dmg). ⌘⇥ app/menu-bar icon is FINAL (owner-approved). master HEAD `6070f0cb`, working tree clean.


## What this is
`KofTwentyTwo/CommandTabFree` is a fork of **AltTab** (`lwouis/alt-tab-macos`, GPL-3.0) that neutralizes the v11 Pro paywall so all features are free, rebranded **CommandTabFree**. Strategy: thin, merge-stable patch tracking upstream forever (`docs/PLAN-maintained-fork.md`).

## ✅ DONE
- De-paywall + anti-relock tests + frozen identity (`com.koftwentytwo.commandtabfree`) + brand sweep + ⌘⇥ icon (final) — all on **`master`** (was `depaywall-free`, fast-forward merged, HEAD `c7d2d968`, pushed to origin; source is public for GPL §6).
- **Sparkle EdDSA keypair generated.** Public key in `Info.plist` (`SUPublicEDKey`); private key in 1Password item **"CommandTabFree-Sparkle-EdDSA"** + GitHub Actions secret `SPARKLE_ED_PRIVATE_KEY` (env `production`); keychain account `commandtabfree`. `SUEnableAutomaticChecks=false` until a real appcast host exists. This fixed the launch-time "updater failed to start" alert.
- **Public release v100.0.3** (pre-release, **unsigned / not notarized**, universal x86_64+arm64) — ⌘⇥ menu-bar icon, redesigned About (KofTwentyTwo identity + AltTab attribution links), and a **full l10n rebrand** (product name → CommandTabFree across base/en + all ~20 translated languages; upstream attribution kept). Earlier v100.0.0/v100.0.1/v100.0.2 superseded.
- **Homebrew tap live:** `brew install --cask koftwentytwo/tap/commandtabfree` (`KofTwentyTwo/homebrew-tap` → `Casks/commandtabfree.rb`). Cask strips the quarantine (postflight `xattr`) for the unsigned app.
- **CI/CD wired** (GitHub Actions), **fully green on push** (run `27634828800`, commit `6070f0cb`). Passing: Guard A/B/C, commitlint, generated-files gate, version compute, `run_tests.sh`, ad-hoc `build_app.sh`. The sign/notarize/appcast/semantic-release/gh-release tail is gated on a `release-gate` step that **auto-activates** when `APPLE_*` secrets are added (so missing secrets SKIP, not fail). Fixed this session (2026-06-16): regenerated base `Localizable.strings` to clear the genstrings gate; build ad-hoc until the owner provisions the Apple cert (was inheriting upstream's Developer ID → exit 65). Earlier this session: Guard B grep now matches the shipped `guard false else { return .pro }` patch (was checking the PLAN's never-shipped `if false`/`alt-tab-free [depaywall]` form); `update_appcast.sh` → `--ed-key-file`; commitlint sync-merge `ignores`; dropped upstream-only scripts (AppCenter/website); commit headers must be ≤72 chars. Full status: `docs/CICD-STATUS.md`.
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
