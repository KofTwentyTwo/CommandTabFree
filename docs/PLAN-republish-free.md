# Plan: Republish a Fully-Free, Paywall-Free AltTab Fork

> **Status:** actionable plan derived from the deep-audit sections in `docs/audit/01-*.md … 09-*.md` and the completeness-critic verdict. Read those sections for full per-file detail; this document is the execution plan that sits on top of them.
>
> **Scope reminder (from `AGENTS.md`):** pure Swift 5.8, no SwiftUI, no Interface Builder. Compile-check after every change with `ai/build.sh`.

---

## A. Licensing & Ethics (read this first — it constrains everything below)

### What the license actually is

- AltTab is **GPL-3.0** (`LICENCE.md` — verbatim GNU GPL v3, "Copyright (C) 2007 Free Software Foundation").
- The paywall overlay (everything under `src/pro/`, plus the integration call-sites in `src/App.swift`, `src/Menubar.swift`, `src/preferences/…`) was added **upstream by the original author lwouis in a single commit** `9147a4a8 "feat: introducing alt-tab pro!"` (v11.0.0, 2026-04-05) — see audit section 09. Because it was added on top of GPL-3.0 code and links against it, the paywall code is itself a **derivative work and therefore also GPL-3.0**. There is no separately-licensed proprietary blob here.
- **Consequence:** GPL-3.0 explicitly grants you the right to modify and redistribute, *including removing the gating*. You may delete the paywall and ship the result.

### What you MUST do (GPL-3.0 obligations)

1. **Offer the complete modified source under GPL-3.0.** Keep `LICENCE.md` as-is. Publish your fork's full source (you already are — public GitHub repo).
2. **Preserve upstream copyright and attribution.** Do **not** remove copyright headers, the GPL notice, `LICENCE.md`, or `docs/contributors.md` / `docs/acknowledgments.md`. Keep a clear "based on AltTab by Louis Pontoise (lwouis/alt-tab-macos), GPL-3.0" statement in your README and About box.
3. **State your changes.** GPL §5(a): mark the files you changed and the dates. A `CHANGELOG`/`NOTICE` entry ("forked from v11.x; removed the Pro/trial/license system; all features unlocked") satisfies this.
4. **Pass the same freedoms downstream.** Your fork must remain GPL-3.0 — you cannot re-close it.

### What you MUST NOT do

- **Do not claim original authorship.** This is a fork; credit lwouis prominently.
- **Do not strip the GPL or attribution** (see above) — that would terminate your license under GPL §8.
- **Do not reuse the original's trademarks / app name / icon / branding in a confusing way.** "AltTab", the AltTab icon, and the `alt-tab.app` brand are the upstream project's identity. Copyright license ≠ trademark license. **Rename the app and replace the icon** (see Section D). Shipping a binary still called "AltTab" with the same icon but a different signer invites both trademark confusion and user-trust problems.
- **Do not impersonate the paywalled product's identity.** Do **not** reuse the upstream **Developer ID** (`Developer ID Application: Louis Pontoise (QXD7GW8FHY)`, `config/release.xcconfig:5`) — you cannot sign with it and must not try. Do **not** reuse the bundle id `com.lwouis.alt-tab-macos`, the Sparkle public key, the `alt-tab.app` license/feedback/appcast endpoints, or the AppCenter app slug. These are operationally tied to lwouis's accounts and you do not control them.
- **Do not point your auto-updater at upstream's appcast / GitHub release downloads** — that would cross-feed updates between the two products and is both a technical and an identity problem.

**Net:** removing the gating and republishing is *legal and in the spirit of GPL-3.0*. The hard requirements are (a) keep it open under GPL-3.0 with attribution, and (b) ship under a **new identity** (name, icon, bundle id, Developer ID, update feed, endpoints).

---

## B. Removal Strategies & Recommendation

### Strategy 1 — "Surgical force-unlock" (smallest diff)

Make the gate always open and neutralize the nag scheduler, leaving the paywall code physically present but inert.

- `LicenseManager.isProLocked` → always `false`; `isProAvailable` → always `true` (audit 03/04: gate lives at `src/pro/license/LicenseManager.swift:67-72`). Hardcode `state = .pro`.
- `ProFeature.attemptUse()` becomes a pass-through (`src/pro/ProFeature.swift:74-83`).
- `PreferenceDefinition.read()` returns the stored value unconditionally (`src/preferences/PreferenceDefinition.swift:32-44`); defaults already hold the Pro values (audit 03), so features unlock with no default changes.
- Stub `ProTransitionManager.onSwitcherShown/onSwitcherDismissed/onAppLaunchComplete` to no-ops to kill nags (`src/App.swift:78,328,429`).

**Pros:** ~10–20 line diff, lowest compile risk, fastest, no Xcode-project surgery.
**Cons:** Dead paywall code ships in the binary; **live remote/telemetry references remain** — license API client, `LicenseCookie` writing a tier cookie to `alt-tab.app` on every state change (`src/App.swift:451`), `RemoteLicenseClient` POSTs (`src/pro/license/RemoteLicenseClient.swift`), machine-fingerprint code (`src/pro/license/MachineFingerprint.swift`). For a *genuine free republish* this is unacceptable: it still phones the upstream paywall backend and leaks a per-machine fingerprint. Also still ships under the upstream identity unless you separately do Section D. **Not recommended as the end state.**

### Strategy 2 — "Full excision" (delete `src/pro/` and untangle) **← RECOMMENDED**

Delete the entire `src/pro/` tree, remove every integration call-site, rewrite the gated preference getters to read raw values, remove the upsell UI from `App.swift` / `Menubar.swift` / `SettingsWindow.swift`, drop the license/cookie/fingerprint network code, fix the Xcode project file and the tests.

**Pros:** Truly free; no dead paywall code; no license API, no tier cookie, no machine fingerprint, no Day-X nag windows. The binary is honestly "all features, no strings."
**Cons:** Larger, riskier change touching ~35 source files plus `alt-tab-macos.xcodeproj/project.pbxproj` (~102 in-Sources entries) and several test files. Build-break risks are real and enumerated in Section C/E.

### Strategy 3 — "Rebase onto pre-paywall / current upstream" (cleanest of all, different shape)

Take **upstream `lwouis/alt-tab-macos`** at a point you want (either pre-paywall `v10.12.0` = commit `317a485b`, or current `master` *minus* the `src/pro/` commit) and cherry-pick only the genuinely-free fork features you care about.

**Pros:** You never have to extract the paywall from this snapshot at all — you start from a clean, paywall-free tree (pre-v11) or a tree where you simply never merge the Pro commit. Lowest *long-term* maintenance because you track upstream directly.
**Cons:** audit 09 confirms this repo has **zero fork-owner commits** — every commit is lwouis or `semantic-release-bot`. So there are effectively **no unique fork features to carry over**; the only delta from upstream *is* the paywall. Rebasing on `v10.12.0` loses all post-v11 fixes unless cherry-picked; rebasing on current upstream-minus-Pro is essentially Strategy 2 done via git topology instead of file deletion. It also still requires the full Section D re-identity work.

### Recommendation

**Adopt Strategy 2 (full excision) as the deliverable, but use Strategy 1 as an intermediate checkpoint.** Concretely:

1. First land Strategy 1 (force-unlock) as a *temporary* commit so you have a known-good, fully-unlocked, compiling build to A/B against.
2. Then perform the full excision on top of it, verifying the build stays green at each phase (Section C).
3. Do Section D (re-identity) in the same release.

Strategy 3 is the right call **only** if you would rather track upstream long-term and re-apply removal as a maintained patch set — given there are no unique fork features, that is a reasonable alternative, but it does not save the re-identity work and loses the newer fixes if you go to `v10.12.0`. For a one-shot "free AltTab" republish from *this* snapshot, full excision is the most honest result and keeps the current v11.x fixes.

---

## C. Step-by-Step Execution (Strategy 2, full excision)

> **Golden rule:** after **every** numbered step, run `ai/build.sh` (Debug) and do not proceed until it compiles. Deleting `src/pro/` before its consumers are rewritten is a guaranteed hard break (the completeness critic lists the exact symbols). The ordering below removes *consumers first*, then the *toolkit*, then the *files*, then the *Xcode refs*, then the *tests*.

### Phase 0 — Safety net

- Branch off `master`. Optionally land the Strategy-1 force-unlock commit first (Section B) to get a fully-unlocked baseline you can diff behavior against.
- Confirm the Debug build is green before touching anything: `ai/build.sh`.

### Phase 1 — Open the gates in place (no deletions yet)

Goal: make every feature live and stop all nags while all Pro symbols still exist, so the build stays green.

1. `src/pro/ProFeature.swift:74-83` — `attemptUse()` returns `true` unconditionally (remove the `isFreePassSessionActive` short-circuit at `:76` and the `attemptHardGatedFeature` call at `:79`).
2. `src/preferences/PreferenceDefinition.swift:32-44` — `read()` returns the stored value unconditionally (drop the free-pass and isProLocked branches).
3. `src/preferences/Preferences.swift` — verify the three gated getters (`:129` appearanceStyle, `:130` appearanceSize, `:155` shortcutStyle) and the three index-0 overrides (`:313, :319, :330`) now return Pro values; defaults already hold them (audit 03).
4. `src/preferences/settings-window/tabs/controls/ControlsTab.swift:589-592` — remove the 1-shortcut cap; `:515` remove the `index>=1` Pro badge.

**Verify:** build green; manually confirm extra shortcuts, in-switcher search, App-Icons/Titles styles, and Auto size all work (audit 06 lists these four advertised features).

### Phase 2 — Sever the App.swift wiring

Edit `src/App.swift`, removing only the Pro lines (audit 01/05 enumerate them):

5. Remove the trial-nag hooks: `:78` (`onSwitcherDismissed`), `:328` (`onSwitcherShown`), `:428` (`onAction = ProPromptHost.shared.dispatch`), `:429` (`onAppLaunchComplete`).
6. Remove the license callback block `:448-460` (`onBeforeProUnlock`, the `onStateChanged` fan-out, and `LicenseManager.shared.initialize()`). Keep `resetPreferencesDependentComponents` (`:51-53`) — it is used elsewhere; only drop the Pro caller. Drop the `proLockStateDidChangeNotification` post (`:458`).
7. Remove the custom-URL activation handler wholesale: `application(_:open:)` + `handleCustomUrl` (`:465-490`) — it exists only for `alttab://activate`.
8. Remove the menubar action selectors/methods: `:25-27` selectors, `:111-121` (`upgradeToPro`, `openAccount`; **decide** whether to keep `supportProject` — it is a donation link, not paywall, audit 01/07).
9. Simplify first-launch: `willShowDay1WelcomeOnAppLaunch` (`:205-208`) and the deferral observer (`:210-220`) reference `Day1WelcomeLetterWindow` and `hasSeenWelcome`. Replace with an unconditional `showAndCenterSettingsWindowOnFirstLaunch`. **Risk (audit 01):** if you delete the welcome window but leave the `willClose` observer, Settings never shows on first launch — remove both together.

**Verify:** build green. `App.swift` now references no `ProTransitionManager`/`LicenseManager`/`ProPromptHost` symbols.

### Phase 3 — Strip the Menubar upsell

Edit `src/Menubar.swift` (audit 07):

10. Delete the 3 license item vars (`:8-10`), the Get-Pro / My-Account / (optionally Support) item adds (`:46-49`), the `UpgradeMenuItemView` assignment (`:47`), and the `refreshLicenseMenuItems` call (`:50`).
11. Delete `refreshLicenseMenuItems` (`:84-107`) and `toggleUpgradeMenuItem` (`:109-118`).
12. Delete the `UpgradeMenuItemView` class (`:235-390`) — its only consumer was `:47`. **Note (critic):** `updateContent(_ state: LicenseState)` (`:357`) hard-depends on the `LicenseState` enum; it dies with this class, which is what lets you delete `LicenseState` later.
13. Delete `badgeDotLayer` (`:187`) and `updateBadgeDotOverlay` (`:202-227`), and remove its call inside `loadPreferredIcon` (`:196`). This severs Menubar's dependency on `ProTransitionManager.shouldShowBadgeDot`.
14. In `menuWillOpen` (`:392-399`) drop `LicenseManager.shared.refreshState()` (`:396`) but **keep** `refreshPermissionCallout()` (`:397`) — non-pro.
15. `showPopoverFromMenubar` (`:229-232`) becomes dead once Day-X popovers go; remove it. **Keep** `menubarIconCallback` (`:155-164`) — also used by PreferencesEvents/QAMenu.

**Verify:** build green. The menu now matches the upstream non-pro item set (Show / Settings / Updates / Permissions / About / Feedback / Quit).

### Phase 4 — Strip Settings-window license entanglement (the critic's biggest miss)

Edit `src/preferences/settings-window/SettingsWindow.swift` (completeness critic):

16. Delete the `UpgradeButton` class (`:133-214`, a `ProGradientButton` subclass reading `LicenseManager.state`/`.isLifetimeVariant`/`.customerEmail`).
17. Delete the `upgradeButton` instance (`:303`) and its state (`:308-311` `upgradeContentView`/`isShowingUpgradeView`/`upgradeViewBottomConstraint`).
18. Delete `setupUpgradeButton` + constraints + `upgradeButtonClicked` (`:401, :503, :507-526`).
19. Delete `showUpgradeView`/`hideUpgradeView` (`:1066, :1122-1161`) which embed `UpgradeTab.initTab`.
20. Delete `refreshUpgradeButton` (`:1163-1165`) — was called from `App.swift:454` (removed in Phase 2) and `UpgradeTab:214`.
21. In `windowDidBecomeKey` (`:1243-1254`) remove `LicenseManager.refreshState` + `UpgradeTab.refreshStatus` + `playShineAnimation`; in `windowWillClose` remove `UpgradeTab.cleanup` (`:1266`).
22. Remove `refreshEmailTooltip` / `hasSecondLine` license reads (`:196, :206-207`).
23. Remove the settings-search "Pro" registration (`:679-680`, registers `ProBadgeView` → "Pro" string).

Edit `src/preferences/settings-window/SidebarList.swift` (critic):

24. Remove `private var proBadge: ProBadgeView?` (`:93`) and `setProBadge` (`:244-258`).

Edit the tabs (audit 03):

25. `AppearanceTab.swift` — remove the `proLockStateDidChange` observer (`:414-419`), the `proGatedAppearanceStyleIndices` args (`:462, :700-703`), the `ProBadge.attach` calls (`:463, :481, :575, :688-698`), the `wrapShortcutStyleProLockIntercept` (`:585-598`) and `wrapAppearanceSizeProLockIntercept` (`:662-679`), and `refreshProLockUi` (`:705+`).
26. `ShortcutEditor.swift` — remove `proGatedIndices` args (`:429, :437, :449, :459`) and the locked intercepts (`:599-607, :705-711`).
27. `ControlsTab.swift` — remove the `proLockStateDidChange` observer (`:141`) (cap + badge already removed in Phase 1).
28. `ShortcutsWhenActiveSheet.swift` — remove the ProBadge on search / lock-search rows (`:25, :51, :54, :63-69`).
29. `LabelAndControl.swift` — remove the `proGatedIndices` param and the `isProLocked` intercept from `makeImageRadioButtons` (`:74-116`, esp. `:78, :86-92`).
30. `src/events/PreferencesEvents.swift:62-64` — delete the "bounce a Pro-valued write to the Upgrade tab" block (depends on `ProFeature.isStoredValuePro`).

**Verify:** build green. No file outside `src/pro/` now references `ProBadgeView`, `ProGradientButton`, `ProGradient`, `LicenseManager`, `LicenseState`, `ProTransitionManager`, `ProFeature`, `UpgradeTab`, or `proLockStateDidChangeNotification`. Grep to confirm:
```
grep -rn -e ProBadgeView -e ProGradient -e LicenseManager -e LicenseState \
  -e ProTransitionManager -e ProFeature -e UpgradeTab -e proLockStateDidChange \
  --include=*.swift src | grep -v '^src/pro/'
```
This grep returning empty (modulo the test files handled in Phase 7) is the gate for Phase 5.

### Phase 5 — Rewrite gated preference getters to be self-contained, then prepare deletion

31. `src/preferences/Preferences.swift` — rewrite the 3 gated getters (`:129, :130, :155`) and the 3 index-0 override branches (`:313, :319, :330`) to read raw values via `CachedUserDefaults.macroPref(...)` instead of `ProGatedPreferences.*.read()`. Remove `overrideRememberedKey` + the `ProTransitionState.setInt` cleanup in `removeOverride` (`:282-298`).
32. `src/preferences/PreferencesMigrations.swift:20` — remove the `ProTransitionState.markFreshInstallIfUnknown` call (the only paywall coupling in migrations).
33. (Optional, in-place-upgrade only) If you ship under the **same** bundle id, add a one-time migration that copies any `proTransition.remembered*` indices back to the base keys before you stop reading them, else users who passed trial expiry on the paywalled build silently lose their prior Pro selections (audit 03 risk). **If you ship a new bundle id (recommended, Section D), this is moot** — clean UserDefaults domain.

**Verify:** build green. `src/pro/` is now referenced only by itself + tests.

### Phase 6 — Delete `src/pro/` and fix telemetry/endpoints

34. Delete the entire `src/pro/` directory (verified contents):
    - `src/pro/license/` — `Clock.swift`, `Keychain.swift`, `LicenseAPI.swift`, `LicenseCookie.swift`, `LicenseManager.swift`, `LicenseManagerSpecs.md`, `LicenseManagerTests.swift`, `LicenseState.swift`, `MachineFingerprint.swift`, `RemoteLicenseClient.swift`
    - `src/pro/scheduling/` — all `Day*.swift` (Day1/4/12/15×3/21/35), `ProTransitionManager.swift`, `ProTransitionManagerTestable.swift`, `ProTransitionScheduler.swift`, `ProTransitionState.swift`, `ProTransitionTests.swift`, `ProTransitionSpecs.md`
    - `src/pro/ui/` — `ProBadgeView.swift`, `ProBadgeViewSegmentTests.swift`, `ProBadgeViewSegmentSpecs.md`, `ProGradientButton.swift`, `ProPromptHeader.swift`, `ProPromptHost.swift`, `ProPromptPopover.swift`, `ProPromptWindow.swift`, `UsageStatHeroView.swift`
    - `src/pro/ProFeature.swift`, `src/pro/ProConversionCopy.swift`, `src/pro/ProFeatureCopy.swift`
35. Delete `src/preferences/PreferenceDefinition.swift` entirely (the gate engine; getters were rewritten in Phase 5).
36. Delete the Upgrade tab `src/preferences/settings-window/tabs/UpgradeTab.swift` (it contains `ProHeroButton: ProGradientButton` at `:493`, the `usageHero`/`heroButton` plumbing `:5-6, :37-38, :160-161`, and the full `activateLicense`/`deactivateLicense`/`deactivateInstance` + `LicenseAPIError.seatLimitExceeded` UI `:322-405` — critic). Remove it from the Settings tab list/registration.
37. **Endpoints/cookie/fingerprint** (`src/api/Endpoints.swift`): remove `checkoutUrl` (`:9`), `accountUrl` (`:10`), `licenseApiBaseUrl` (`:11`). Keep `appcastUrl` and `supportUrl`; keep or repoint `feedbackUrl` (`:12`) per Section D. The `LicenseCookie`, `RemoteLicenseClient`, `MachineFingerprint` files are already gone with `src/pro/license/`.
38. **`UsageStats`** (`src/util/UsageStats.swift`, `UsageStatsTestable.swift`, `UsageStatsMessageTests.swift`): local-only, no network (audit 09). Its only *paywall* consumers were `ProConversionCopy`/`UsageStatHeroView`, now deleted. You may keep it (the neutral `App.swift` recording / AboutTab display still compile) or delete it; deleting also requires removing `UsageStatsMessageTests.swift` from the test target.
39. **QA/Debug menu** `src/debug/QAMenu.swift:170-241` (audit 05): directly instantiates every Day-X window and pokes manager flags. Remove those manual triggers/resets or the DEBUG build won't compile.
40. **DebugProfile** `src/secondary-windows/DebugProfile.swift:17` reads `LicenseManager.shared.state.debugProfileLabel` (the extension lived at `src/pro/license/LicenseState.swift:14`). Since DebugProfile feeds the (kept) Feedback report, **hand-edit** — drop the License line, do not delete the file (critic).
41. **AppCenter telemetry** (audit 08/09) — remove it (most privacy-aligned for a free build; AppCenter is also EoL):
    - delete `src/vendors/AppCenterCrashes.swift` and references in `src/App.swift` (`import`/`AppCenterApplication` superclass at `App.swift:7`/start call).
    - **Principal class break (critic):** `Info.plist:36-37` `NSPrincipalClass = AppCenterApplication`, the `class App: AppCenterApplication` superclass, and `alt-tab-macos-Bridging-Header.h:1` import are coupled. Replace the superclass with `NSApplication` and set `NSPrincipalClass` to `NSApplication` (or your own subclass), and remove the bridging-header import — or the app won't launch *and* won't compile.
    - remove `Secrets.appCenterSecret` usage (`src/api/Secrets.swift`), `Info.plist` `AppCenterSecret`/forwarder keys, and the `Package.swift` AppCenter deps.
    - keep `DebugProfile.make()` if Feedback stays (it is shared); only the crash-attachment call site goes away.

**Verify:** build green.

### Phase 7 — Xcode project file + tests (the mechanical part — do not skip)

42. **`alt-tab-macos.xcodeproj/project.pbxproj`** (critic): every deleted file has a `PBXBuildFile` + `PBXFileReference` + `PBXGroup` child + `PBXSourcesBuildPhase` membership (~102 in-Sources pro entries; app phase ~line 1830, test phase ~1902; `PreferenceDefinition.swift` at ~1979). Note **`Clock`, `Keychain`, `LicenseAPI`, `MachineFingerprint`, `ProTransitionManagerTestable` have TWO build-file UUIDs (app + test)** — remove **both**. Any file deleted on disk but still referenced makes the project fail to parse/link. The cleanest way to do this safely is to let Xcode reconcile, but since `AGENTS.md` says don't develop in Xcode, edit `project.pbxproj` by hand and verify with `xcodebuild -list` / `ai/build.sh` after.
43. **Tests** (critic): remove/repair test-target members that reference vanished symbols — `LicenseManagerTests`, `ProTransitionTests`, `ProTransitionManagerTestable`, `ProBadgeViewSegmentTests`, and (if you deleted UsageStats) `UsageStatsMessageTests`. In `src/_test-support/Mocks.swift` remove the `ProBadgeView` Symbols stub and the `ShortcutStylePreference` mock, and update the hardcoded bundle id (`Mocks.swift:133`, `com.lwouis.alt-tab-macos`) to the new id. `PreferencesMigrationsTests.swift:356` has a *self-contained local stub* `ProTransitionState` (won't break on deletion), but the real `PreferencesMigrations.swift:20` call you removed in Phase 5 is what mattered.

**Verify:** Test scheme passes:
```
scripts/run_tests.sh    # Test scheme, Release config (audit 08)
```

### Phase 8 — Final compile + behavior pass

44. `ai/build.sh` (Debug) green; `scripts/build_app.sh` (Release scheme) green; `scripts/run_tests.sh` green.
45. Manual smoke test (Section E checklist): permissions flow, switcher show/hide, all four previously-Pro features, multiple shortcuts, Settings opens with no Upgrade tab / no Get-Pro item / no badge dot, no `alttab://` handler, no network call to `alt-tab.app/api`.

---

## D. Re-Identity & Publish

> Per `AGENTS.md`, app identity (Developer ID, TeamID, bundle id) and Keychain items are coupled to the code signature. **For the free build this invariant is effectively MOOT (audit 08/09):** once `src/pro/license/Keychain.swift` is deleted there are no stored license items to orphan, so rebranding the bundle id is safe. But the identity change itself is **mandatory** — you cannot sign with upstream's Developer ID.

### Identity

- **Bundle id:** change `com.lwouis.alt-tab-macos` → your reverse-DNS (e.g. `app.koftwentytwo.alt-tab-free`). Locations: `config/base.xcconfig:4`; unit-test bundle id in `project.pbxproj:2477/2542`; hardcoded `Mocks.swift:133`.
- **App name / `PRODUCT_NAME`:** rename away from "AltTab" (trademark — Section A). Update `config/base.xcconfig`, README, and the About box (`App.repository`, `src/App.swift:16`).
- **Icon:** replace the AltTab icon with your own (trademark + brand identity).
- **TeamID / Developer ID:** `DEVELOPMENT_TEAM = "${TEAM_ID}"` currently expands to empty; signing is driven by `CODE_SIGN_IDENTITY` (`config/release.xcconfig:5`) = the upstream `Developer ID Application: Louis Pontoise (QXD7GW8FHY)`. **Replace with your own Developer ID Application cert + TeamID.** The CI cert secret `$APPLE_P12_CERTIFICATE` (`scripts/codesign/setup_ci_master.sh`) must be your P12. Notarization Apple-ID/password/team (`ci_cd.yml:9-11`, `scripts/package_and_notarize_release.sh`) must be your account.

### Auto-update (Sparkle) — must repoint or you can't ship updates

- Feed URL `Endpoints.appcastUrl` = `https://<DOMAIN>/appcast.xml`, `DOMAIN=alt-tab.app` (`config/base.xcconfig:20`). **Repoint `DOMAIN`** to a host you control, or serve the committed `appcast.xml` from your own GitHub Pages / raw URL.
- **Generate a NEW Sparkle EdDSA keypair.** Replace `SUPublicEDKey` (`Info.plist:62`, currently `2e9SQOBoaKElchSa/4QDli/nvYkyuDNfynfzBF6vJK4=`) and the CI signing secret `$SPARKLE_ED_PRIVATE_KEY` (`update_appcast.sh:9`). Public and private **must match** or updates fail verification. You cannot reuse lwouis's key (you don't have the private half anyway).
- **Truncate/regenerate `appcast.xml`** (~3876 lines). Existing items are signed by upstream's private key and point at `github.com/lwouis/alt-tab-macos/releases/...` (`update_appcast.sh:18`). Leaving them risks cross-feeding updates between the two products — start a fresh feed for your fork's own releases.
- Re-vendor/re-sign `vendor/Sparkle/Helpers/Updater.app` + `Autoupdate` with **your** Developer ID (`copy_sparkle_helpers.sh` re-seals with `CODE_SIGN_IDENTITY`); a mismatch trips `codesign --verify --deep --strict`.

### Remove the license API + telemetry endpoints

- License API (`Endpoints.licenseApiBaseUrl`, `RemoteLicenseClient`) and the per-tier `LicenseCookie` are deleted in Phase 6 — confirm no remaining reference to `alt-tab.app/api/v1/license`.
- **AppCenter** removed in Phase 6 (Step 41). Decide explicitly: remove entirely (recommended) vs repoint to a self-owned AppCenter app (note: AppCenter is EoL, so removal is the durable choice).
- **Feedback** (`Endpoints.feedbackUrl` → `alt-tab.app/api/v1/feedback`, used `FeedbackWindow.swift:445`): its server turns the POST into a GitHub issue on **lwouis's** repo and is **not in this repo**. Either stand up your own endpoint and repoint, or remove the in-app feedback submitter. This is a *product decision*, flagged in audit 08/09.
- **Website repository-dispatch** (`update_website.sh:5` → `lwouis/alt-tab-website`, `$WEBSITE_DISPATCH_TOKEN`, `ci_cd.yml:67-69`) and the README-stats step hitting `api.github.com/repos/lwouis/alt-tab-macos` (`update_readme_and_website.sh:10`) must be removed or repointed to your repo. Update `.github/FUNDING.yml`.

### Distribution channel & notarization

- **Recommended:** GitHub Releases of *your* fork + Sparkle feed served from your domain or GitHub Pages. This mirrors the existing pipeline with minimal change once the URLs/keys above are yours.
- **Alternatively / additionally:** a Homebrew cask (`brew install --cask <your-fork>`), which still requires a notarized, stapled `.zip`/`.app`.
- **Notarization is mandatory** for Gatekeeper on modern macOS regardless of channel: sign with your Developer ID → `notarytool` submit (bundled `scripts/notarytool`, `scripts/package_and_notarize_release.sh`) with **your** `$APPLE_ID`/`$APPLE_PASSWORD`/`$APPLE_TEAM_ID` → `xcrun stapler staple` → re-zip.
- **Versioning:** releases are 100% `semantic-release` from Conventional Commits on `master` (`determine_next_version.sh` → CI-only `VERSION.txt` → `Info.plist`). `package.json` `1.0.0` is irrelevant. Your fork can keep this as-is once the secrets/URLs are yours, or reset the version line for a clean v1.

**Gating prerequisite (audit 08 open question):** you need your own Apple Developer account (Developer ID Application cert + notarization credentials) and a domain (or GitHub Pages) for the appcast + your own Sparkle EdDSA keypair **before** the first signed, self-updating release is possible.

---

## E. Risks, Testing, and Phased Checklist

### Top build-break risks (from the completeness critic — fix the consumer before deleting the type)

- **`LicenseState` enum** is referenced by non-pro `Menubar.swift:357` (`updateContent` param) and `DebugProfile.swift:17` (`.debugProfileLabel`). Handle in Phase 3/6 before deleting `src/pro/license/LicenseState.swift`.
- **`LicenseManager` singleton** is read by non-obvious non-pro sites: `SettingsWindow.swift:162,164,167,196,206-207,1246` and `UpgradeTab.swift:220-405`. All removed in Phase 4/6.
- **`ProGradientButton`** is the **superclass** of `UpgradeButton` (`SettingsWindow.swift:133`) and `ProHeroButton` (`UpgradeTab.swift:493`); `Menubar.swift:247` uses `ProGradient.makeLayer()`. Delete all subclasses/usages (Phase 3/4/6) before deleting the toolkit.
- **`ProBadgeView`** referenced by `SidebarList.swift:93,254`, `SettingsWindow.swift:679`, Appearance/Controls/ShortcutsWhenActiveSheet. Remove all (Phase 4) before deleting it.
- **`ProGatedPreferences`/`PreferenceDefinition.swift`** feeds `Preferences.swift:129,130,155` getters and is a **unit-test-target member** (`project.pbxproj:1979`) — a broken getter fails *app and test* compile. Rewrite getters (Phase 5) before deleting.
- **App superclass / principal class** (`App.swift:7`, bridging header, `Info.plist:36-37`) — removing AppCenter without replacing the principal class means the app won't launch *and* won't compile (Phase 6, Step 41).
- **`Day1WelcomeLetterWindow`** referenced in non-pro `App.swift:213`; the first-launch deferral observer (`:194-218`) must be simplified to always show Settings (Phase 2, Step 9) or compile breaks.
- **`project.pbxproj` integrity** — ~102 in-Sources entries + fileRef/group entries per deleted file; dual app+test UUIDs on Clock/Keychain/LicenseAPI/MachineFingerprint/ProTransitionManagerTestable must **both** go (Phase 7).

### Behavioral / product risks

- **In-place upgrade data loss** (audit 03): if you keep the same bundle id, users past trial-expiry have downgraded stored prefs with the Pro index parked in `proTransition.remembered*` (in the `<bundleId>.license` UserDefaults suite). After removal nothing restores them. **Mitigation:** ship a new bundle id (clean domain) — recommended — or add the one-time restore migration in Phase 5, Step 33.
- **Orphaned UserDefaults / Keychain** (audit 04/05): with a new bundle id there is nothing to orphan; with the same id, old `proTransition.*` / `trialStartDate` keys are harmless once no code reads them.
- **Sparkle key mismatch** breaks updates silently for end users — verify the public/private EdDSA pair before first release.
- **Trademark/identity** (Section A): shipping as "AltTab" with the AltTab icon is the highest *non-build* risk — rename + re-icon.

### Testing matrix

- **Unit:** `scripts/run_tests.sh` (Test scheme) green after Phase 7. The pure kernels (`SelectionResolver`, `SearchModeResolver`, `WindowFilterResolver`, `WindowOrderResolver`) never touched pro code (audit 02) and should pass unchanged — a good signal that gate removal didn't perturb core logic.
- **Debug build:** `ai/build.sh` green after **every** phase (the discipline that catches the consumer-before-type breaks).
- **Release build:** `scripts/build_app.sh` green before packaging.
- **Manual smoke (post-Phase 8):**
  1. Fresh launch → Accessibility + Screen-Recording permission flow → switcher panels appear (phase-A → phase-B handoff, audit 01).
  2. Alt-Tab show/hide/cycle; selection + hover; window focus.
  3. All four previously-Pro features work: App-Icons/Titles appearance style, Auto size, in-switcher search, lock-search, and **>1 keyboard shortcut**.
  4. Settings: no Upgrade tab, no Get-Pro menu item, no trial subtitle, no orange badge dot, no Pro badges on Appearance/Controls rows.
  5. No `alttab://` URL handler registered (and removed from `Info.plist` URL scheme).
  6. Network check (e.g. Little Snitch / `nettop`): **no** request to `alt-tab.app/api/v1/license` and **no** tier cookie; appcast points at *your* host.
  7. Auto-update: a test appcast item signed with your EdDSA key updates successfully.

### Phased checklist

- [ ] Phase 0 — branch; baseline build green; (optional) land Strategy-1 force-unlock checkpoint.
- [ ] Phase 1 — gates open in place (`ProFeature`, `PreferenceDefinition.read`, shortcut cap); build green.
- [ ] Phase 2 — `App.swift` wiring severed (hooks, license block, custom-URL, selectors, first-launch); build green.
- [ ] Phase 3 — `Menubar.swift` upsell stripped (items, `UpgradeMenuItemView`, badge dot, `refreshState`); build green.
- [ ] Phase 4 — `SettingsWindow`/`SidebarList`/tabs/`PreferencesEvents` license + ProBadge plumbing removed; grep gate empty; build green.
- [ ] Phase 5 — `Preferences.swift` getters read raw values; `PreferencesMigrations:20` removed; (optional) restore migration; build green.
- [ ] Phase 6 — delete `src/pro/` + `PreferenceDefinition.swift` + `UpgradeTab.swift`; fix `Endpoints`, `DebugProfile`, `QAMenu`, AppCenter/principal class; build green.
- [ ] Phase 7 — `project.pbxproj` entries removed (incl. dual app+test UUIDs); tests/Mocks repaired; `scripts/run_tests.sh` green.
- [ ] Phase 8 — Release build green; manual smoke pass.
- [ ] Re-identity (D) — new bundle id, name, icon, Developer ID, Sparkle EdDSA keypair + repointed feed, removed license/AppCenter, repointed/removed feedback + website dispatch + FUNDING.
- [ ] Publish — signed, notarized, stapled `.app`/`.zip` via your GitHub Releases + your appcast (and/or Homebrew cask).
- [ ] Compliance (A) — `LICENCE.md` intact, attribution + "based on lwouis/alt-tab-macos, GPL-3.0" in README/About, changes noted, fork remains GPL-3.0.

---

### Appendix — reference: audit sections

| # | File | Topic |
|---|------|-------|
| 01 | `docs/audit/01-core-architecture.md` | App lifecycle, App.swift/Menubar.swift spine touchpoints |
| 02 | `docs/audit/02-switcher-ui.md` | Switcher gates (`ProFeature.attemptUse` call sites) |
| 03 | `docs/audit/03-preferences-and-gating.md` | `PreferenceDefinition`/`ProGatedPreferences`, `isProLocked` |
| 04 | `docs/audit/04-license-subsystem.md` | `LicenseManager`/`RemoteLicenseClient`/Keychain |
| 05 | `docs/audit/05-trial-nag-scheduling.md` | `ProTransitionManager` Day1→Day35 scheduler |
| 06 | `docs/audit/06-profeature-and-copy.md` | `ProFeature` cases + marketing copy |
| 07 | `docs/audit/07-pro-ui-and-menubar.md` | `src/pro/ui/` toolkit + Menubar integration |
| 08 | `docs/audit/08-build-release-distribution.md` | xcconfig, signing, Sparkle, CI |
| 09 | `docs/audit/09-telemetry-and-upstream.md` | AppCenter, network surfaces, upstream relationship |
