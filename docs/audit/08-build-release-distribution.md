# 08 — Build, Signing, Auto-Update & Publishing Pipeline

How `alt-tab-free` (a fork of `lwouis/alt-tab-macos`) is actually built, versioned, signed,
notarized, shipped, and auto-updated. This section is written for the republish-as-free goal:
every place the pipeline still points at the **original upstream / paywall vendor** (`lwouis`,
`alt-tab.app`, AppCenter, the upstream Developer ID and Sparkle key) is enumerated at the end.

---

## 1. How to build locally

There is no Makefile / wrapper — builds are raw `xcodebuild` invocations over
`alt-tab-macos.xcodeproj`. There are exactly **three schemes** (`alt-tab-macos.xcodeproj/xcshareddata/xcschemes/`):
`Debug.xcscheme`, `Release.xcscheme`, `Test.xcscheme`.

### Debug build (everyday dev loop)
`ai/build.sh:3-7`:
```
xcodebuild -project alt-tab-macos.xcodeproj -scheme Debug -configuration Debug -derivedDataPath DerivedData
```
- Per `AGENTS.md` the sanctioned workflow is "copy commands from `ai/build.sh` and run them" — never drive Xcode interactively.
- Run the built app: `ai/run.sh:3` runs `DerivedData/Build/Products/Debug/AltTab.app/Contents/MacOS/AltTab --logs=debug --benchmark showUi 3`.
- Profile: `ai/profile.sh` records a 20s Time Profiler trace via `xcrun xctrace` and exports it to XML.

### Release build (what CI ships)
`scripts/build_app.sh:5`:
```
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData | scripts/xcbeautify
```
Release products land in `DerivedData/Build/Products/Release` (`XCODE_BUILD_PATH` env, `ci_cd.yml:17`).

### Build configuration (xcconfig layering)
Build settings live in `config/*.xcconfig`, attached to the project via `baseConfigurationReference`
entries in `alt-tab-macos.xcodeproj/project.pbxproj` (lines ~2429–2562). The layering:

- `config/base.xcconfig` — shared identity & build settings. Key values:
  - `PRODUCT_NAME = AltTab` (`base.xcconfig:3`)
  - `PRODUCT_BUNDLE_IDENTIFIER = com.lwouis.alt-tab-macos` (`base.xcconfig:4`) **[upstream identity — see §7]**
  - `MACOSX_DEPLOYMENT_TARGET = 10.13` (`base.xcconfig:5`); `SWIFT_VERSION = 5.8` (`:6`)
  - `INFOPLIST_FILE = Info.plist`, `CODE_SIGN_ENTITLEMENTS = alt_tab_macos.entitlements` (`:8-9`)
  - `ENABLE_HARDENED_RUNTIME = YES` (`:12`, required for notarization)
  - `DOMAIN = alt-tab.app` and `API_DOMAIN = alt-tab.app/api` (`:20-21`) **[upstream domains — see §7]**
- `config/debug.xcconfig` — `#include "base.xcconfig"`, then `CODE_SIGN_IDENTITY = Local Self-Signed` (`:5`), `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG` (`:6`), `OTHER_CODE_SIGN_FLAGS = --timestamp=none` (`:8`). Ends with `#include? "local.xcconfig"` (`:13`).
- `config/release.xcconfig` — `#include "base.xcconfig"`, then `CODE_SIGN_IDENTITY = Developer ID Application: Louis Pontoise (QXD7GW8FHY)` (`:5`) **[upstream Developer ID — see §7]**, `OTHER_CODE_SIGN_FLAGS = --timestamp --deep --options runtime` (`:7`, for notarization), wholemodule + `-O` + ThinLTO + full stripping (`:8-18`). Ends with `#include? "local.xcconfig"` (`:21`).
- `config/test-base.xcconfig` / `test-debug.xcconfig` / `test-release.xcconfig` — for the Test scheme; signing disabled (`CODE_SIGNING_REQUIRED = NO`, `CODE_SIGNING_ALLOWED = NO`, `test-base.xcconfig:6-7`), `ONLY_ACTIVE_ARCH = YES`.

`config/local.xcconfig` is **not committed** (referenced via `#include?`, so optional). It is the
per-developer / CI override channel for `CODE_SIGN_IDENTITY`, `APPCENTER_SECRET`, `CURRENT_PROJECT_VERSION`,
`DOMAIN`, `API_DOMAIN`. The pbxproj has a stale `local.xcconfig` file reference (`project.pbxproj:458`)
but it is *not* set as a `baseConfigurationReference` — the `#include?` in debug/release is what loads it.

### `DEVELOPMENT_TEAM` is empty at build time
In `project.pbxproj` the app target sets `DEVELOPMENT_TEAM = "${TEAM_ID}"` (lines 2462, 2520, 2554),
but **`TEAM_ID` is never defined** anywhere (not in any xcconfig, not in CI env). It therefore
expands to empty, so signing is driven purely by `CODE_SIGN_IDENTITY`. The CI's `APPLE_TEAM_ID`
secret is used *only* by `notarytool` (`package_and_notarize_release.sh:17`), not by `xcodebuild`.
The Debug target explicitly sets `DEVELOPMENT_TEAM = ""` (`project.pbxproj:2562`). Net effect:
Release is signed with whatever identity `release.xcconfig` (or a `local.xcconfig` override) names.

### Local Release signing without the upstream cert
`scripts/codesign/setup_local.sh` generates a throwaway self-signed cert and imports it into the
main keychain (calls `generate_selfsigned_certificate.sh` → `import_certificate_into_main_keychain.sh`).
This lets a developer who lacks the `Developer ID Application: Louis Pontoise` cert still produce a
signed-but-not-notarizable Release (typically combined with a `local.xcconfig` overriding
`CODE_SIGN_IDENTITY`).

### Tooling prerequisites
- **Xcode 26.0.1** pinned in CI (`ci_cd.yml:45`: `sudo xcode-select -s /Applications/Xcode_26.0.1.app/...`).
- **Node** (16 in CI, `package.json` `engines` says `>=18`) for `commitlint`, `semantic-release`, `swiftformat.js`, `ts-node`.
- **Python 3.6** (`Pipfile`) only for asset/l10n tooling (`fonttools`, `googletrans`), not the app build.
- Bundled binaries in `scripts/`: `xcbeautify` (6.5 MB), `notarytool` (17 MB), `assets/createicns`; and `vendor/Sparkle/bin/sign_update`.

---

## 2. Versioning & release cutting (semantic-release)

Releases are fully automated from Conventional Commits on `master`; there is **no manual version
bump**. `package.json` `version` (`1.0.0`) is irrelevant — the app version is computed by semantic-release.

### Commit linting → version derivation
- `commitlint.config.js` extends `@commitlint/config-conventional`. CI enforces it across the pushed range: `npx commitlint --from "$GITHUB_EVENT_BEFORE" --to "$GITHUB_EVENT_AFTER"` (`ci_cd.yml:48`).
- `release.config.js` configures `@semantic-release/commit-analyzer` (angular preset) with extra `releaseRules` so `perf/docs/style/refactor/test/chore/ci` all force at least a **patch** bump (`release.config.js:6-14`). `feat` → minor, breaking → major (defaults).
- `scripts/determine_next_version.sh:5-8` runs `npx semantic-release --dry-run`, greps "The next release version is …", and writes the bare version (e.g. `11.3.0`) to `VERSION.txt` (the `$VERSION_FILE`, `ci_cd.yml:18`). `VERSION.txt` is **not committed** — it is a CI-only scratch file consumed by later steps.

### Version injection into the app
`scripts/replace_environment_variables_in_app.sh:7-11` writes a fresh `config/local.xcconfig`:
```
CURRENT_PROJECT_VERSION = <contents of VERSION.txt>
APPCENTER_SECRET = $APPCENTER_SECRET
```
`Info.plist` consumes `$(CURRENT_PROJECT_VERSION)` for both `CFBundleShortVersionString` and
`CFBundleVersion` (`Info.plist:26-29`), and `$(APPCENTER_SECRET)` for `AppCenterSecret` (`Info.plist:73-74`).

### Changelog, tag & GitHub Release
- `npx semantic-release` (`ci_cd.yml:59`) runs the full plugin chain in `release.config.js`: generates release notes → updates `changelog.md` (`@semantic-release/changelog`) → commits `changelog.md`, `appcast.xml`, `README.md` back to the repo (`@semantic-release/git`), and creates the git tag.
- `scripts/extract_latest_changelog.sh` writes `tag_name=v<version>` and the top changelog block to `$GITHUB_OUTPUT` (`:6-9`).
- `softprops/action-gh-release@v3` (`ci_cd.yml:62-66`) publishes the GitHub Release with that tag/body and attaches `DerivedData/Build/Products/Release/*.zip`.
- `changelog.md` is already populated with upstream history; entries link to `github.com/lwouis/alt-tab-macos/...` (e.g. `changelog.md:1`). The most recent committed release is **11.3.0** (matches `git log`).

---

## 3. Code signing & notarization

### Signing
- Release is signed by Xcode using `CODE_SIGN_IDENTITY = Developer ID Application: Louis Pontoise (QXD7GW8FHY)` (`release.xcconfig:5`) with hardened runtime + secure timestamp (`base.xcconfig:12`, `release.xcconfig:7`).
- The signing cert reaches CI via a base64 P12 secret: `scripts/codesign/setup_ci_master.sh:8` decodes `$APPLE_P12_CERTIFICATE` to `codesign.p12`, then `import_certificate_into_new_keychain.sh` creates/unlocks a dedicated `alt-tab-macos.keychain`, imports the P12 for `/usr/bin/codesign`, and runs `security set-key-partition-list` (`import_certificate_into_new_keychain.sh:12-19`).
- `setup_ci_pr.sh` (used on PRs, not wired into the current `master`-only workflow) generates a self-signed cert instead — PRs build but cannot notarize.

### Entitlements
`alt_tab_macos.entitlements`: `app-sandbox = false` (it needs Accessibility/Screen Recording) and
`com.apple.security.cs.disable-library-validation = true` (to load the embedded Sparkle/AppCenter
frameworks under hardened runtime).

### Sparkle framework re-sealing (build phase)
`scripts/copy_sparkle_helpers.sh` is a "Copy Sparkle Helpers" build phase that runs after Embed
Frameworks and before Xcode's final code sign. It copies the prebuilt `Updater.app` + `Autoupdate`
into `Sparkle.framework/Versions/A/`, mirrors SPM-generated resources, rewrites the framework
`CFBundleIdentifier` to `org.sparkle-project.Sparkle`, then **re-signs** the framework with
`EXPANDED_CODE_SIGN_IDENTITY`/`CODE_SIGN_IDENTITY` (final lines of the script). The `Updater.app`/
`Autoupdate` helpers are pre-signed with the maintainer's Developer ID at vendor time
(`vendor/scripts/update_sparkle.sh`).

### Notarization (`scripts/package_and_notarize_release.sh`)
1. `ditto -c -k --keepParent AltTab.app AltTab-<version>.zip` (`:11`).
2. Submit to Apple: `scripts/notarytool submit --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" <zip> --wait --timeout 15m` (`:14-19`). Exits non-zero unless status is `Accepted` (`:22`).
3. `xcrun stapler staple AltTab.app` (`:25`) then re-zips the stapled app over the same name (`:26`). That stapled zip is the GitHub Release asset and the Sparkle download.

### Keychain / identity invariant (from `AGENTS.md`)
The app's Developer ID, TeamID, and bundle ID must stay stable across builds: Keychain items
(license keys) are tied to the code signature. Changing any one orphans every user's stored
license. **For the free fork this is the reason §7 matters** — but since the fork is *removing*
the license/Keychain layer entirely, the invariant's coupling concern goes away once the `src/pro`
license code is gone (no Keychain license to orphan). The identity still must change because the
upstream Developer ID cannot be used.

---

## 4. Auto-update (Sparkle)

The app embeds **Sparkle 2.9.1** (`vendor/Sparkle/UPSTREAM`), vendored as source via SPM plus
prebuilt helper apps.

### Wiring in code
- `src/App.swift:407-413` builds an `SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: App.sparkleDelegate!, ...)` and calls `startUpdater()` 30s after launch.
- `src/vendors/SparkleDelegate.swift:26-28` supplies the feed URL: `feedURLString → Endpoints.appcastUrl`.
- `src/api/Endpoints.swift`: `website = "https://\(domain)"` where `domain` is read from the `Domain` Info.plist key (`Endpoints.swift:4,6`); `appcastUrl = "\(website)/appcast.xml"` (`:7`). With `DOMAIN = alt-tab.app` that resolves to **`https://alt-tab.app/appcast.xml`** **[upstream feed — see §7]**.
- `feedParameters` (`SparkleDelegate.swift:30-38`) appends `version`, `macos`, `arch`, `lang` query params to the feed request.
- **Tier-aware appcast:** `src/pro/license/LicenseCookie.swift` writes a `license` cookie (`pro`/`proExpired`/empty) on the `alt-tab.app` domain so the appcast server can tailor responses per license tier (`LicenseCookie.swift:3,9-21`). This is paywall-coupled and goes away with `src/pro` removal.
- Update preferences are toggled in `src/events/UserDefaultsEvents.swift`, `src/events/PreferencesEvents.swift:85-86`, and `src/preferences/settings-window/tabs/GeneralTab.swift:100-101`. `Info.plist:63-66` sets `SUEnableAutomaticChecks = true`, `SUScheduledCheckInterval = 604800` (weekly).

### EdDSA signing
- The **public** EdDSA key is baked into `Info.plist:61-62`: `SUPublicEDKey = 2e9SQOBoaKElchSa/4QDli/nvYkyuDNfynfzBF6vJK4=` **[upstream key — see §7]**.
- The **private** key lives only in CI as `$SPARKLE_ED_PRIVATE_KEY`. `scripts/update_appcast.sh:9` signs each zip with `vendor/Sparkle/bin/sign_update -s $SPARKLE_ED_PRIVATE_KEY <zip>` and embeds the `sparkle:edSignature` + `length` into a new `<item>`.

### Appcast file (`appcast.xml`)
- RSS 2.0 with Sparkle namespace; `<title>alt-tab-macos</title>`. 3876 lines, newest item first (currently 11.3.0).
- `scripts/update_appcast.sh:11-26` builds an `ITEM.txt` block and `sed`-inserts it right after the `</language>` tag. Each `<enclosure url=...>` points at **`https://github.com/lwouis/alt-tab-macos/releases/download/v<version>/AltTab-<version>.zip`** (`update_appcast.sh:18`) **[upstream download host — see §7]**, and the release-notes link is **`https://alt-tab.app/changelog-bare`** (`:16`) **[upstream — see §7]**.
- `appcast.xml` is committed back to the repo by semantic-release (`release.config.js:21-26`). The *file* is what Sparkle fetches from `alt-tab.app/appcast.xml`, so the hosting website serves this committed file.

### Distribution surface summary
The download artifacts live on **GitHub Releases of `lwouis/alt-tab-macos`** (per the appcast
enclosure URLs and the `update_readme_and_website.sh` API calls), and the appcast/release-notes are
served from the **`alt-tab.app`** website. The website itself is a *separate* repo
(`lwouis/alt-tab-website`, see §6).

---

## 5. Crash reporting & symbols (Microsoft AppCenter)

- The app subclasses `AppCenterApplication` (`Info.plist:36-37` `NSPrincipalClass`; `src/App.swift:7`). `src/vendors/AppCenterCrashes.swift:20` calls `AppCenter.start(withAppSecret: Secrets.appCenterSecret, services: [Crashes.self])`. The secret is read from the `AppCenterSecret` Info.plist key (`src/api/Secrets.swift:6`), injected from `$APPCENTER_SECRET` (`replace_environment_variables_in_app.sh:9`).
- Network is gated off unless a crash is actually sent (`AppCenterCrashes.swift:13-14, 49`).
- AppCenter is vendored (4.3.0 + PLCrashReporter 1.11.1, `vendor/scripts/update_appcenter.sh`).
- **dSYM upload:** `scripts/upload_symbols_to_appcenter.sh` zips and uploads `AltTab.app.dSYM` and `Sparkle.framework.dSYM` to `https://api.appcenter.ms/v0.1/apps/alt-tab-macos/alt-tab-macos` (`:4-7`) using `$APPCENTER_TOKEN`. **[upstream AppCenter account — see §7]**

> NOTE: Microsoft App Center is being retired (Microsoft announced March 31 2025 EoL). Even
> independent of the fork, this crash-reporting path is dead-ending and is a candidate for removal,
> not just re-pointing.

---

## 6. CI/CD workflow (`.github/workflows/ci_cd.yml`)

Single workflow, single `build` job, triggered only on **push to `master`** (`ci_cd.yml:1-4`),
runs on `macos-15`, environment `production` (`:22-23`). Step order (`:38-69`):

1. `actions/checkout@v6` with computed `fetch-depth` (commits + 30, `:28-40`) — needs history for commitlint/semantic-release.
2. `actions/setup-node@v6` (node 16) + `npm ci` (`:41-47`).
3. `npx commitlint --from <before> --to <after>` (`:48`).
4. `scripts/ensure_generated_files_are_up_to_date.sh` (`:49`) — runs l10n extraction and fails if it produced a diff (`git diff-files --exit-code`).
5. `scripts/determine_next_version.sh` (`:50`) → `VERSION.txt`.
6. `scripts/replace_environment_variables_in_app.sh` (`:51`) → `config/local.xcconfig`.
7. `scripts/codesign/setup_ci_master.sh` (`:52`) — import Developer ID P12.
8. `scripts/run_tests.sh` (`:53`) — `xcodebuild test -scheme Test -configuration Release`.
9. `scripts/build_app.sh` (`:54`) — Release build.
10. `scripts/package_and_notarize_release.sh` (`:55`) — zip + notarize + staple.
11. `scripts/upload_symbols_to_appcenter.sh` (`:56`) — dSYMs → AppCenter.
12. `scripts/update_appcast.sh` (`:57`) — sign zip + prepend appcast item.
13. `scripts/update_readme_and_website.sh` (`:58`) — refresh README stats SVG + contributors.
14. `npx semantic-release` (`:59`) — changelog/tag/commit-back.
15. `extract_latest_changelog.sh` (`:60-61`) → release notes.
16. `softprops/action-gh-release@v3` (`:62-66`) — publish GitHub Release + attach `*.zip`.
17. `scripts/update_website.sh` (`:67-69`) — `gh api repos/lwouis/alt-tab-website/dispatches -f event_type=update-website`, authed with `$WEBSITE_DISPATCH_TOKEN` (`update_website.sh:5`). **[upstream website repo — see §7]**

### CI secrets / env (`ci_cd.yml:5-19`)
`GITHUB_TOKEN`, `APPCENTER_SECRET`, `APPCENTER_TOKEN`, `APPLE_ID`, `APPLE_PASSWORD`,
`APPLE_TEAM_ID`, `APPLE_P12_CERTIFICATE` (base64 Developer ID P12), `SPARKLE_ED_PRIVATE_KEY`,
`WEBSITE_DISPATCH_TOKEN`. Plus computed `BUILD_DIR`, `XCODE_BUILD_PATH=DerivedData/Build/Products/Release`,
`VERSION_FILE=VERSION.txt`, `APP_NAME=AltTab`.

`scripts/update_readme_and_website.sh` hits `https://api.github.com/repos/lwouis/alt-tab-macos/...`
for contributors / star / download counts (`:10`) — another hardcoded upstream slug.

`.github/FUNDING.yml` points at upstream donation channels (`github: lwouis`, `patreon: alt_tab_macos`,
`ko_fi: alt_tab`, a PayPal button id). Cosmetic, but fork-specific.

---

## 7. CRITICAL — identities / URLs / secrets a fork MUST change or remove

Everything below still targets the **original upstream / paywall vendor**. A republished free fork
must change (C) or remove (R) each item. Build will not *break* if these are left as-is (it will
build and sign with whatever cert is present), but the app would phone home to upstream, fail to
update from the fork's own releases, and attempt to notarize/sign under the upstream account.

| # | What | Where (file:line) | Current value | Action |
|---|------|-------------------|---------------|--------|
| 1 | **Bundle ID** | `config/base.xcconfig:4` (+ unit-tests id `project.pbxproj:2477,2542`; mocks `src/_test-support/Mocks.swift:133`) | `com.lwouis.alt-tab-macos` | **C** — set fork's reverse-DNS id (e.g. `com.koftwentytwo.alt-tab-free`). |
| 2 | **Developer ID signing cert** | `config/release.xcconfig:5` | `Developer ID Application: Louis Pontoise (QXD7GW8FHY)` | **C** — fork's own Developer ID Application cert + TeamID. |
| 3 | **Signing P12 secret** | `ci_cd.yml:12` / `setup_ci_master.sh` | `$APPLE_P12_CERTIFICATE` | **C** — replace with fork's exported Developer ID P12. |
| 4 | **Notarization Apple account** | `ci_cd.yml:9-11`; `package_and_notarize_release.sh:15-18` | `$APPLE_ID` / `$APPLE_PASSWORD` / `$APPLE_TEAM_ID` | **C** — fork's Apple ID + app-specific password + TeamID. |
| 5 | **Sparkle public EdDSA key** | `Info.plist:62` | `2e9SQOBoaKElchSa/4QDli/nvYkyuDNfynfzBF6vJK4=` | **C** — generate a NEW EdDSA keypair (`generate_keys`); put public half here. |
| 6 | **Sparkle private EdDSA key** | `ci_cd.yml:13`; `update_appcast.sh:9` | `$SPARKLE_ED_PRIVATE_KEY` | **C** — fork's new private key. Must match #5 or updates won't verify. |
| 7 | **Appcast feed domain** | `config/base.xcconfig:20` (`DOMAIN`) → `Endpoints.swift:6-7` | `alt-tab.app` → `https://alt-tab.app/appcast.xml` | **C** — fork's domain, OR repoint feed at fork's GitHub-hosted appcast. |
| 8 | **API domain (license + feedback)** | `config/base.xcconfig:21` (`API_DOMAIN`) → `Endpoints.swift:5,11-12` | `alt-tab.app/api` → `https://alt-tab.app/api/v1/license`, `.../v1/feedback` | **R** — license API is paywall; remove with `src/pro`. Feedback endpoint must be repointed or removed. |
| 9 | **Appcast download URL** | `update_appcast.sh:18` | `https://github.com/lwouis/alt-tab-macos/releases/download/v<v>/...` | **C** — fork's GitHub releases URL (`KofTwentyTwo/alt-tab-free`). |
| 10 | **Appcast release-notes link** | `update_appcast.sh:16`; existing items in `appcast.xml` | `https://alt-tab.app/changelog-bare` | **C/R** — fork URL or drop the link. |
| 11 | **License tier cookie** | `src/pro/license/LicenseCookie.swift` | cookie on `alt-tab.app` | **R** — remove with paywall. |
| 12 | **Website dispatch repo + token** | `update_website.sh:5`; `ci_cd.yml:69` | `lwouis/alt-tab-website` + `$WEBSITE_DISPATCH_TOKEN` | **R/C** — fork has no upstream website; remove this CI step or repoint. |
| 13 | **README stats / contributors API** | `update_readme_and_website.sh:10` | `api.github.com/repos/lwouis/alt-tab-macos` | **C/R** — fork slug, or drop the step. |
| 14 | **AppCenter app + secret** | `update_symbols`→`upload_symbols_to_appcenter.sh:4-7`; `ci_cd.yml:7-8`; `Info.plist:73`; `Secrets.swift:6` | `apps/alt-tab-macos/alt-tab-macos`, `$APPCENTER_SECRET`, `$APPCENTER_TOKEN` | **R** — AppCenter is EoL; remove crash-reporting + the upload step (or repoint to a fork-owned analytics-free build). |
| 15 | **`App.repository`** | `src/App.swift:16` | `https://github.com/lwouis/alt-tab-macos` | **C** — fork repo URL (used in About/links). |
| 16 | **GitHub Release target** | implicit via `GITHUB_TOKEN` repo + appcast URLs | upstream releases | **C** — fork publishes to its own repo; ensure appcast URLs (#9) match. |
| 17 | **FUNDING.yml** | `.github/FUNDING.yml` | upstream Patreon/Ko-fi/PayPal/github sponsor | **C/R** — fork's funding or remove. |
| 18 | **Vendored Developer-ID-signed Sparkle helpers** | `vendor/Sparkle/Helpers/Updater.app`, `Autoupdate` (re-signed by `copy_sparkle_helpers.sh`) | signed with maintainer Developer ID at vendor time | **C** — re-vendor/re-sign with fork's Developer ID, else `--deep --strict` verify may flag mismatched seals once the app id changes. |

### Notes for the removal plan
- Items **8, 11, 14** (license API, license cookie, AppCenter) are *removals* that should fall out
  naturally when `src/pro/` and the AppCenter vendor wiring are stripped — they are not just
  re-pointing.
- Items **1, 2, 3, 4, 5, 6** are the hard prerequisites to ship a notarized, self-updating fork:
  without a new Developer ID + a new Sparkle EdDSA keypair the fork can neither notarize nor sign
  its own updates. The `AGENTS.md` Keychain-orphaning concern is **moot** for the free fork because
  the license/Keychain code is being removed — there is no stored license to orphan.
- The `appcast.xml` already in the repo contains ~3876 lines of upstream EdDSA-signed enclosures
  pointing at upstream releases. A clean fork should **truncate/regenerate** it (old entries are
  signed by the upstream private key #6 and reference upstream downloads #9), otherwise existing
  AltTab users' Sparkle could see fork updates or vice-versa.
- `DEVELOPMENT_TEAM = "${TEAM_ID}"` (undefined) is harmless today but should be set to the fork's
  TeamID (or left empty with explicit `CODE_SIGN_IDENTITY`) for clarity.
