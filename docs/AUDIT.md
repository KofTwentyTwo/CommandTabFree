# alt-tab-free — Master Paywall Audit

> **Purpose.** This is the authoritative, read-this-first overview of the codebase, the paywall grafted onto it, and the complete surface that must be removed to ship a fully-free build. It summarizes nine deep-dive sections under [`docs/audit/`](audit/) and the completeness review; follow the links for line-by-line detail.
>
> **Audit date / commit basis:** repo at `master` (HEAD `9fadf36b`, v11.3.0). All `file:line` references are against this snapshot.
>
> **Status legend:** **KEEP** = legitimate app, must survive · **CUT** = paywall, remove · **REWRITE** = touched by both, hand-edit · **FLAG** = owner decision.

---

## 1. What this project is, and the licensing position

**alt-tab-free** ([github.com/KofTwentyTwo/alt-tab-free](https://github.com/KofTwentyTwo/alt-tab-free)) is a re-host of the popular open-source macOS window switcher **AltTab** ([github.com/lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos)). It is a pure Swift 5.8 AppKit application — no SwiftUI, no Interface Builder (per [`AGENTS.md`](../AGENTS.md)).

### It is not a diverged fork — it is upstream + a paywall commit

Git history shows every recent commit is authored by upstream author `lwouis` (34/40) or `semantic-release-bot` (6/40); **zero commits by the alt-tab-free owner**. The entire paywall was introduced upstream in a single commit `9147a4a8` *"feat: introducing alt-tab pro!"* (v11.0.0, 2026-04-05), a 1869-file change that also did a large repo-wide folder reorg. `src/pro/` did not exist before it and has only ever been touched by 3 commits. All branding is still upstream's: bundle id `com.lwouis.alt-tab-macos`, name AltTab, domain `alt-tab.app`, repo `lwouis/alt-tab-macos`, Sparkle `SUPublicEDKey`, AppCenter secret. (See [`09-telemetry-and-upstream.md`](audit/09-telemetry-and-upstream.md).)

### Licensing: republishing a free build is permitted, with one obligation

The project is **GPL-3.0** ([`LICENCE.md`](../LICENCE.md):1 — *"GNU GENERAL PUBLIC LICENSE Version 3"*). Under GPL-3 you may modify and redistribute, including a build with all paywall code removed. **The obligation:** you must offer the complete corresponding source of your modified version under GPL-3 to your users (typically by publishing the fork's repo). The GPL-3 copyright string in `Info.plist:20-21` is correct and must stay. The paywall itself was GPL-3 code upstream, so its removal carries no additional license burden.

> **Strategic alternative (owner decision).** Because upstream is alive and GPL-3, rebasing the free build on the **pre-paywall upstream tag v10.12.0** (commit `317a485b`) yields the same unlocked feature set with no paywall to extract, at the cost of losing post-v11 fixes unless cherry-picked. The rest of this document assumes **in-place removal** from the current v11.x snapshot.

---

## 2. High-level architecture (the legitimate app)

This is the app that survives removal. Deep dive: [`01-core-architecture.md`](audit/01-core-architecture.md), [`02-switcher-ui.md`](audit/02-switcher-ui.md).

### Startup (two-phase, permission-gated)

- Entry point is top-level code in [`src/main.swift`](../src/main.swift) (**not** `@main`/`@NSApplicationMain`): CLI fast-path → signal/exception handlers → `App.shared.run()` (`main.swift:23`). `main.swift` is paywall-free.
- `App` (`src/App.swift:7`) subclasses `AppCenterApplication` (this is *why* removing AppCenter touches the principal class — see §5) and is its own `NSApplicationDelegate`.
- **Phase A** — `applicationDidFinishLaunching` (`App.swift:435-463`): wires logging, Preferences, the license callbacks, and starts a permission-polling timer.
- **Phase B** — `App.continueAppLaunchAfterPermissionsAreGranted` (`App.swift:383-431`): invoked **once** from `SystemPermissions.checkPermissionsPreStartup` (`SystemPermissions.swift:77`) only after Accessibility + Screen-Recording permissions pass. It creates the background threads/queues, switcher panels, menubar, main menu, and installs every macOS hook.
- The **phase-A → phase-B handoff is the critical launch path and is paywall-free.**

### macOS integration hooks (all paywall-free)

- Keyboard: `cghid` CGEvent tap + Carbon `RegisterEventHotKey` (`KeyboardEvents.swift:104-152`).
- Windows: AX observers with refcon-encoded `(pid,wid)` identity (`AccessibilityEvents.swift`), dispatched through a bounded retry executor (`AXCallScheduler.swift`).
- App lifecycle: KVO on `NSWorkspace.runningApplications` (`RunningApplicationsEvents.swift:6-10`).
- Threading owned by `BackgroundWork` (dedicated CFRunLoop threads + bounded operation queues, ~45-thread budget). **`src/macos/` and `BackgroundWork` contain zero License/Pro references** (grep-verified).

### Switcher UI

Event-driven: each `Window` subscribes to AX notifications → `Windows.findOrCreate` (`Windows.swift:390`), gated by `WindowDiscriminator.isActualWindow`, into the canonical `Windows.list`. Pure unit-tested kernels (`SelectionResolver`, `SearchModeResolver`, `WindowFilterResolver`, `WindowOrderResolver`) are separated from imperative wrappers and **never call pro code** — gating is passed in as a `Bool`. Rendering is a static `TilesView` engine with a 20-`TileView` recycled pool (`TilesView.swift:35`); focus uses private SkyLight APIs (`Window.swift:245-288`).

### Preferences

Everything stored as strings in `UserDefaults.standard`, macro (enum) prefs as stringified `CaseIterable` index, read through `CachedUserDefaults`, written through `Preferences.set` firing one `PreferencesEvents.preferenceChanged` hook. The **core preferences plumbing is paywall-independent** — only the feature-gating layer on top is paywall (see §3).

### Build / release / update

Raw `xcodebuild` over `alt-tab-macos.xcodeproj` (3 schemes), settings layered via `config/*.xcconfig`. Releases are fully automated by `semantic-release` on push to master. Signed with upstream Developer ID *Louis Pontoise (QXD7GW8FHY)*, notarized via bundled `notarytool`. Auto-update via embedded **Sparkle 2.9.1**, feed `https://alt-tab.app/appcast.xml`, EdDSA-signed. Crash reporting via Microsoft **AppCenter** (Crashes module only; opt-in; EoL). Deep dive: [`08-build-release-distribution.md`](audit/08-build-release-distribution.md), [`09-telemetry-and-upstream.md`](audit/09-telemetry-and-upstream.md).

---

## 3. The paywall, anatomized

The paywall lives **almost entirely under [`src/pro/`](../src/pro/)** and is grafted onto the spine at a small, well-defined set of call sites. Four subsystems:

### 3a. License subsystem — `src/pro/license/` ([`04-license-subsystem.md`](audit/04-license-subsystem.md))

`LicenseManager.shared` is the **single source of truth** for entitlement. It computes a flat 4-case `LicenseState` enum — `.trial(daysRemaining:)`, `.pro`, `.proExpired`, `.trialExpired` (`LicenseState.swift:14-19`); there is no `.lifetime` case (lifetime is `.pro` + variant slug `"pro_lifetime"`, `LicenseManager.swift:25`). A **14-day trial** starts on first launch (`LicenseManager.swift:17,192-200`).

- The master gate **`isProLocked`** (`LicenseManager.swift:67-72`) is `true` for `.proExpired`/`.trialExpired`, `false` for `.pro`/`.trial`. Every settings intercept, the write-bounce, the shortcut cap, and `ProFeature.attemptUse()` consult it.
- `activate(_:)` (`LicenseManager.swift:104-140`) does all-or-nothing Keychain writes with rollback, then flips `state = .pro`. `RemoteLicenseClient` (`RemoteLicenseClient.swift`) POSTs activate/validate/deactivate to **`https://alt-tab.app/api/v1/license`** (`Endpoints.swift:11`), sending a machine fingerprint (`MachineFingerprint.swift:9-20`, IOPlatformUUID) + trial-start timestamp. Revalidation is throttled to 30 days.
- Keychain service: **`com.lwouis.alt-tab-macos.license`** (`LicenseManager.swift:4`); a parallel UserDefaults suite of the same name holds `trialStartDate`, `lastValidation`, `customerEmail`.
- `LicenseCookie.swift:5-22` writes a per-tier `license` cookie on `.alt-tab.app` so the Sparkle appcast can be tier-tailored.

### 3b. Trial-nag "Pro Transition" scheduler — `src/pro/scheduling/` ([`05-trial-nag-scheduling.md`](audit/05-trial-nag-scheduling.md))

A self-contained Day1→Day35 upsell-escalation engine. Coordinator `ProTransitionManager` (singleton) + timed `ProTransitionScheduler` (persisted `DispatchWorkItem`) + persisted `ProTransitionState` (all `hasSeen*` flags + `remembered*` Pro indices, in the `.license` UserDefaults suite) + pure, 100%-unit-tested `ProTransitionManagerTestable` state machine. The coordinator emits abstract `ProPromptAction` cases through `onAction`; `ProPromptHost` maps each to a concrete Day-X window/popover so the coordinator stays AppKit-free.

- **Soft nags** (never block): `[A]` Day1 Welcome (fires immediately on first launch), `[H]` Day4 Tour, `[B]` Day12 Heads-Up, `[D]` Day15 Proactive, `[F]` Day21, `[G]` Day35, plus a Days13-14 menubar badge dot.
- **Hard gate arms at Day15 expiry:** `onProLockEngaged()` (`ProTransitionState.swift:73-79`) snapshots degradable Pro prefs to `remembered*` and downgrades stored values to free equivalents; the three hard-gated features then route through a free-pass ladder (`ProTransitionManager.swift:226-242`): first post-expiry attempt = `.freePass` (allow once, queue `[C]` Full Upgrade) → `.showFullUpgrade` → `.showHardGatePopover` `[E]` forever.
- Prompts only fire 10:00-11:30 or 15:30-17:00; give-up at Day49.

### 3c. Feature gating — `ProFeature.swift` + `PreferenceDefinition.swift` ([`03-preferences-and-gating.md`](audit/03-preferences-and-gating.md), [`06-profeature-and-copy.md`](audit/06-profeature-and-copy.md))

Two complementary mechanisms:

1. **Degradable preferences** — declared as 6 `ProGatedPreferences` definitions (`PreferenceDefinition.swift:103-164`): 3 globals (`appearanceStyle`, `appearanceSize`, `shortcutStyle`) + their 3 shortcut-0 overrides. Each carries a `freeEquivalent`, a `rememberedKey`, and an `isProValue` predicate. `PreferenceDefinition.read()` (`:32-44`) is the hot-path getter; while locked it returns the free equivalent. Pro getters in `Preferences.swift` route through these (`:129,130,155,313,319,330`).
2. **Hard-gated runtime actions** — no backing preference, gated at use-time via `ProFeature.attemptUse()` (`ProFeature.swift:74-83`): `extraShortcut(index:)`, `searchInSwitcher`, `lockSearchInSwitcher`. Call sites: `ShortcutAction.swift:56`, `TilesView.swift:79,92`.

Write-side enforcement bounces any setter that lands a Pro value into a gated key while locked, to the Upgrade tab (`PreferencesEvents.swift:62-64`). Free users are hard-capped at **1 shortcut** (`ControlsTab.swift:589-592`). The registered defaults already hold the Pro values (e.g. `appearanceSize=.auto`), so **removing the gate auto-unlocks everything with no default changes.**

### 3d. Upsell UI — `src/pro/ui/` + Settings/Menubar entanglement ([`07-pro-ui-and-menubar.md`](audit/07-pro-ui-and-menubar.md))

Reusable AppKit upsell primitives (none contain license logic; they only render): `ProPromptHost` (dispatch hub), `ProPromptPopover`/`ProPromptWindow` (shared chrome), `ProPromptHeader`, `ProGradientButton` (gradient buy CTA), `UsageStatHeroView` (a "your usage so far" stat block), and `ProBadgeView.swift` (misleadingly named — holds 5 types incl. the `ProGradient` utility enum, `NotAdvisedButton`, and the "Pro" pill). These are also consumed by **Settings** (the persistent Get-Pro gradient pill `UpgradeButton`, the in-window Upgrade view, `ProBadgeView` badges on gated rows, and the "Pro" search-index keyword), which is why `src/pro/ui/` can only be deleted after Settings consumers are cut.

---

## 4. The complete set of Pro-gated features (what becomes free)

There are **two degradable groups + three hard-gated actions**, marketed as four headline features. After removal, all are unconditionally available.

| Feature (marketing copy) | Kind | Free (locked) value | Pro value | Gate mechanism | Definition |
|---|---|---|---|---|---|
| **App Icons & Titles styles** (`appearanceStyle`) | Degradable + hard-gated | `thumbnails` (0) | `appIcons` (1) / `titles` (2) | `read()` downgrade + first-summon `[C]` | `PreferenceDefinition.swift:103-109`; `Preferences.swift:129` |
| **Auto Size** (`appearanceSize`) | Degradable | `medium` (1) | `auto` (3) | `read()` downgrade only | `PreferenceDefinition.swift:111-117`; `Preferences.swift:130` |
| **Search on release** (`shortcutStyle`) | Degradable + hard-gated | `doNothingOnRelease`/`focusOnRelease` | `searchOnRelease` (2) | `read()` downgrade + first-summon `[C]` | `PreferenceDefinition.swift:119-125`; `Preferences.swift:155` |
| ↳ same three as **shortcut-0 overrides** | Degradable | free equivalents | Pro values | `read()` downgrade | `PreferenceDefinition.swift:130-164`; `Preferences.swift:313,319,330` |
| **Up to 9 keyboard shortcuts** (extra slots ≥ 2) | Hard-gated | capped at **1** shortcut | up to 9 | `ProFeature.attemptUse()` + `addShortcutSlot` cap | `ProFeature.swift:14`; `ShortcutAction.swift:56`; `ControlsTab.swift:589-592` |
| **Search — find a window by typing** | Hard-gated | blocked | available | `ProFeature.attemptUse()` | `ProFeature.swift:15`; `TilesView.swift:92` |
| **Lock-search in switcher** | Hard-gated | blocked | available | `ProFeature.attemptUse()` | `ProFeature.swift:16`; `TilesView.swift:79` |

Marketing copy: `ProFeatureCopy.swift` (4 strings); the comparison table that advertises them is `Day1WelcomeLetterWindow.swift:77-80`. Note **preview-selected-window is NOT actually Pro-gated** (`Preferences.effectivePreviewSelectedWindow` reads the raw bool, gated only by Screen-Recording permission) — leave it alone.

---

## 5. The complete removal surface

**Removal strategy (consensus across all sections):** *delete `src/pro/` as a unit, then fix the consumers that reference it.* The lowest-risk staged approach is to first force `LicenseManager.isProLocked = false` / `isProAvailable = true` (every gate becomes a pass-through with no other edits), then progressively excise. The list below — grouped by file — is the full set of edits required for a clean build, incorporating the completeness review's additional items and build-break risks. **Bold flags** mark items the deep sections under-weighted.

### `src/pro/` — delete wholesale (CUT)

- `src/pro/license/` — `LicenseManager`, `LicenseState`, `LicenseAPI`, `RemoteLicenseClient`, `LicenseCookie`, `Keychain`, `MachineFingerprint`, `Clock`, `LicenseManagerSpecs.md`, `LicenseManagerTests.swift`.
- `src/pro/scheduling/` — `ProTransitionManager`, `ProTransitionScheduler`, `ProTransitionState`, `ProTransitionManagerTestable`, all `Day*.swift` windows/popovers, `ProTransitionTests.swift`, `ProTransitionSpecs.md`.
- `src/pro/ui/` — `ProPromptHost`, `ProPromptPopover`, `ProPromptWindow`, `ProPromptHeader`, `ProGradientButton`, `UsageStatHeroView`, `ProBadgeView.swift` (all 5 types). **Delete only AFTER the Settings consumers below are removed.**
- `src/pro/` root — `ProFeature.swift`, `ProFeatureCopy.swift`, `ProConversionCopy.swift`, `UsageStats.swift` / `UsageStatsTestable.swift` (local-only; feeds only upsell copy).

### `src/App.swift` (REWRITE — the spine wiring)

- Selectors `upgradeToProAction` / `openAccountAction` / `supportProjectAction` (`:25-27`) and methods `upgradeToPro` / `openAccount` / `supportProject` (`:111-121`) — remove (Menubar-only consumers).
- `hideUi` `onSwitcherDismissed()` (`:78`) and `showUiOrCycleSelection` `onSwitcherShown()` (`:328`) — remove the single Pro line each (switcher hot path).
- First-launch welcome entanglement (`:189-233`): `willShowDay1WelcomeOnAppLaunch` (`:205-208`) + deferral observer referencing `Day1WelcomeLetterWindow` (`:194-218`). **Simplify to always call `showAndCenterSettingsWindowOnFirstLaunch`; the welcome window and its `willCloseNotification` observer must be removed together or Settings never shows on first launch.**
- Phase-B Pro wiring `onAction` / `onAppLaunchComplete` (`:428-429`) — remove (all other phase-B wiring stays).
- License callback block (`:448-460`): `onBeforeProUnlock`, the `onStateChanged` fan-out (`refreshLicenseMenuItems`, `syncLicenseCookie`, `onLicenseStateChanged`, `UpgradeTab.refreshStatus`, `refreshUpgradeButton`, `proLockStateDidChange` post), `LicenseManager.initialize()`. The cleanest 13-line cut point. Keep `resetPreferencesDependentComponents` (`:51-53`) — it's used elsewhere; just drop the caller.
- Custom-URL handler `application(_:open:)` + `handleCustomUrl` (`:465-490`) — remove wholesale (exists only for the `<bundleid>://activate` deep link; the registered scheme is `$(PRODUCT_BUNDLE_IDENTIFIER)` = `com.lwouis.alt-tab-macos://`, NOT a literal `alt-tab://`). **Also drop the URL scheme from `Info.plist` (`CFBundleURLSchemes`, :53-56).**

### `src/Menubar.swift` (REWRITE)

- License item vars (`:8-10`), the Get Pro / My Account / Support adds + view assignment (`:46-50`), `refreshLicenseMenuItems` (`:84-107`), `toggleUpgradeMenuItem` (`:109-118`).
- `UpgradeMenuItemView` gradient pill incl. trial "days remaining" copy (`:235-390`; copy at `:370-375`) — delete; only consumer is `:47`.
- Badge dot: `badgeDotLayer` (`:187`), `updateBadgeDotOverlay` (`:202-227`) gated on `ProTransitionManager.shouldShowBadgeDot` (`:205`), and its call inside `loadPreferredIcon` (`:196`).
- `menuWillOpen` (`:392-399`): drop `LicenseManager.shared.refreshState()` (`:396`); **keep `refreshPermissionCallout()` (`:397`).**
- **`updateContent(_ state: LicenseState)` (`:357`) hard-depends on the `LicenseState` enum type — goes away with `UpgradeMenuItemView`. Keep `menubarIconCallback` (`:155-164`), used by non-pro callers.**

### `src/preferences/` (REWRITE)

- `PreferenceDefinition.swift` — delete entirely; **it is also a unit-test-target member (`project.pbxproj:1979`), so a broken getter fails app AND test compile.**
- `Preferences.swift` — rewrite the 3 gated getters (`:129,130,155`) and 3 index-0 override branches (`:313,319,330`) to read raw values; remove `overrideRememberedKey` + `ProTransitionState` cleanup in `removeOverride` (`:282-298`).
- `PreferencesEvents.swift:62-64` — delete the `isProLocked && isStoredValuePro` bounce.
- `PreferencesMigrations.swift:20` — remove the `ProTransitionState.markFreshInstallIfUnknown` call (the only paywall coupling in migrations; **the real symbol, distinct from the self-contained stub in `PreferencesMigrationsTests.swift:356`**).
- `LabelAndControl.swift` — strip `proGatedIndices` param + intercept (`:74-116`, esp. `:86-92`).
- `AppearanceTab.swift` — `proLockStateDidChange` observer (`:414-419`), `proGatedAppearanceStyleIndices` (`:462,700-703`), `ProBadge.attach` (`:463,481,575,688-698`), `wrapShortcutStyleProLockIntercept` (`:585-598`), `wrapAppearanceSizeProLockIntercept` (`:662-679`), `refreshProLockUi` (`:705+`).
- `ShortcutEditor.swift` — `proGatedIndices` (`:429,437,449,459`), segmented + radios locked intercepts (`:599-607,705-711`).
- `ControlsTab.swift` — `proLockStateDidChange` observer (`:141`), `row.setProBadge` for index≥1 (`:515`), the `addShortcutSlot` shortcut cap (`:589-592`).
- `ShortcutsWhenActiveSheet.swift` — `ProBadge` on search/lock-search rows (`:25,51,54,63-69`).

### `src/preferences/settings-window/SettingsWindow.swift` — **the most license-entangled non-pro file outside Menubar/UpgradeTab (REWRITE — under-weighted by §7)**

- `UpgradeButton` class (`:133-214`, a `ProGradientButton` subclass reading `LicenseManager.state`/`.isLifetimeVariant`/`.customerEmail`/`.trial`/`.proExpired`); instance `:303`; state `:308-311`; `setupUpgradeButton` + `upgradeButtonClicked` (`:401,507-526`).
- `showUpgradeView` / `hideUpgradeView` embedding `UpgradeTab.initTab` (`:1066,1122-1161`); `refreshUpgradeButton` (`:1163-1165`, called from `App.swift:454` and `UpgradeTab:214`).
- `windowDidBecomeKey` → `LicenseManager.refreshState` + `UpgradeTab.refreshStatus` + shine animation (`:1243-1254`); `UpgradeTab.cleanup` in `windowWillClose` (`:1266`).
- Settings-search registers `ProBadgeView → "Pro"` (`:679-680`); `refreshEmailTooltip` + `hasSecondLine` read `.pro`/`customerEmail` (`:196,206-207`).

### Other Settings / secondary windows (REWRITE)

- `SidebarList.swift` — `private var proBadge: ProBadgeView?` (`:93`) and `setProBadge` instantiating `ProBadgeView` (`:244-258`).
- `UpgradeTab.swift` — delete the whole tab; **`ProHeroButton: ProGradientButton` (`:493`) + `usageHero`/`heroButton`/`makeHeroButton` (`:5-6,37-38,160-161`); `activateLicense`/`deactivateLicense`/`deactivateInstance` + `LicenseAPIError.seatLimitExceeded` seat-management UI (`:322-405`) — full activation UI, §4 listed only `LicenseManager`/`RemoteLicenseClient`.**
- `DebugProfile.swift:17` — `LicenseManager.shared.state.debugProfileLabel` (extension at `LicenseState.swift:14`). **This feeds `FeedbackWindow`, which is being kept — hand-edit (drop the License line), do not delete the file.**

### `src/debug/QAMenu.swift` (REWRITE)

- The DEBUG manual triggers/resets (`:170-241`) directly instantiate every Day-X window and poke `LicenseManager`/manager flags — must be removed/updated in lockstep or the **DEBUG build won't compile.**

### Build / distribution / telemetry (REWRITE / FLAG — see [`08`](audit/08-build-release-distribution.md), [`09`](audit/09-telemetry-and-upstream.md))

- `Endpoints.swift` — `licenseApiBaseUrl` (`:11`), `checkoutUrl` (`:9`), `accountUrl` (`:10`) become dead. `feedbackUrl` (`:12`) and `supportUrl` (`:8`) are not paywall — owner decides.
- **Identity (mandatory regardless of removal):** the upstream Developer ID cannot be used. Change bundle id (`config/base.xcconfig:4`; also hardcoded `Mocks.swift:133` and unit-test ids `project.pbxproj:2477/2542`), signing cert (`release.xcconfig:5`), generate a NEW Sparkle EdDSA keypair (`Info.plist:62 SUPublicEDKey` + CI `$SPARKLE_ED_PRIVATE_KEY`), repoint feed/download/website URLs (`base.xcconfig:20-21`, `update_appcast.sh:16,18`, `App.repository` `App.swift:16`), truncate the upstream-signed `appcast.xml`.
- **AppCenter removal touches the app's principal class:** `App` subclasses `AppCenterApplication` (`App.swift:7`), `Info.plist:36-37 NSPrincipalClass=AppCenterApplication`, `alt-tab-macos-Bridging-Header.h:1`. Removing AppCenter requires choosing a replacement principal class / reverting to `NSApplication`, or **the app won't launch and won't compile.** Also: `src/vendors/AppCenterCrashes.swift`, `Secrets.appCenterSecret`, `scripts/upload_symbols_to_appcenter.sh`, `ci_cd.yml:56`.
- `.github/FUNDING.yml` and the website repository-dispatch (`update_website.sh:5 → lwouis/alt-tab-website`) point at upstream — repoint or remove.

### `alt-tab-macos.xcodeproj/project.pbxproj` — **mechanical but build-fatal (REWRITE)**

Every `src/pro` file (and `Endpoints`/`Secrets`/`AppCenter`) has a `PBXBuildFile` + `PBXFileReference` + `PBXGroup` child + `PBXSourcesBuildPhase` membership (~102 in-Sources pro entries; app phase ~1830, test phase ~1902; incl. `PreferenceDefinition.swift:1979`). **`Clock`/`Keychain`/`LicenseAPI`/`MachineFingerprint`/`ProTransitionManagerTestable` each have TWO build-file UUIDs (app + test) — both must be removed.** Any file deleted on disk but left referenced breaks at project-load/link.

### Test target (REWRITE)

`LicenseManagerTests`, `ProTransitionTests`, `ProTransitionManagerTestable`, `UsageStatsMessageTests`, `ProBadgeViewSegmentTests`, and `_test-support/Mocks.swift` (ProBadgeView stub + `ShortcutStylePreference` mock + bundle id `:133`) all break if pro symbols vanish — update/remove in lockstep.

### Build-break risk summary (the hard dependencies)

| Symbol being deleted | Non-pro / under-weighted consumers that break first |
|---|---|
| `LicenseState` enum | `Menubar.swift:357` (`updateContent` param), `DebugProfile.swift:17` (`.debugProfileLabel`) |
| `LicenseManager.shared` | `SettingsWindow.swift:162,164,167,196,206-207,1246`; `UpgradeTab.swift:220-405` |
| `ProGradientButton` (superclass) | `UpgradeButton` (`SettingsWindow.swift:133`), `ProHeroButton` (`UpgradeTab.swift:493`), `ProGradient.makeLayer` (`Menubar.swift:247`) |
| `ProBadgeView` | `SidebarList.swift:93,254`, `SettingsWindow.swift:679`, Appearance/Controls/ShortcutsWhenActiveSheet tabs |
| `ProGatedPreferences` / `PreferenceDefinition` | `Preferences.swift:129,130,155`; also a test-target member → fails app + test compile |
| `AppCenterApplication` | `App.swift:7` superclass + Bridging-Header + `Info.plist` NSPrincipalClass |
| `Day1WelcomeLetterWindow` | `App.swift:213` first-launch deferral observer |
| `ProTransitionState.markFreshInstallIfUnknown` | `PreferencesMigrations.swift:20` (real symbol) |

---

## 6. Notable findings, risks, and open questions

### Findings

- **The paywall is well-isolated.** Outside `src/pro/`, the entire spine coupling is ~13 lines in `App.swift` (`:448-460`) plus discrete blocks in `Menubar`, `Settings`, and the gating layer. The launch path, switcher kernels, macOS hooks, threading, and core preferences are all paywall-free.
- **Defaults already hold Pro values.** Removing the gate auto-unlocks features with no default changes (`appearanceSize=.auto`, etc.).
- **`.proExpired` is effectively dead code** in this build: `versionLimitedVariants` is empty (`LicenseManager.swift:28`), so no `.pro` variant ever expires by version.
- **No third-party analytics SDK.** Only telemetry is AppCenter Crashes (opt-in, EoL); `UsageStats` is local-only and never networked.

### Risks

- **In-place upgrade data loss.** Users who passed trial expiry on the paywalled build have stored prefs already downgraded to free equivalents, with the original Pro index parked in `proTransition.remembered*` keys (in the `.license` UserDefaults suite). After removal, `read()` no longer restores them → silent loss of their prior Pro selection. A **new bundle id** (clean UserDefaults domain) sidesteps this; otherwise add a one-time migration copying `remembered*` indices back to base keys before deleting `proTransition.*`.
- **`state.didSet` fires `onStateChanged`.** If you hardcode `state = .pro` at init, ensure the hook tolerates being invoked (or unset it) — otherwise it can re-enter paywall code you intend to delete.
- **Keychain/signing invariant is MOOT for a free build.** Removing `src/pro` removes all Keychain license usage, so changing bundle id / Developer ID has nothing to orphan — but the **identity change is still mandatory** because the upstream Developer ID cannot be used. (Per [`AGENTS.md`](../AGENTS.md), do not rotate identity while licensing is retained.)
- **Do NOT `git revert 9147a4a8`.** It mixes the paywall with a 1869-file folder reorg; removal must be by deleting `src/pro/` and untangling the wiring, then confirming the build links (`ai/build.sh`).

### Open questions (owner decisions)

1. **New bundle id vs in-place?** Determines whether the `remembered*` migration above is needed.
2. **Keep "Support this project"** (donation link, upstream precedent) and the feedback feature? Both are non-paywall but currently route through paywall-adjacent code / upstream endpoints (`Endpoints.supportUrl`, `Endpoints.feedbackUrl` → `alt-tab.app`, whose server side is not in this repo).
3. **Auto-update story.** A fork cannot ship updates against the upstream `SUPublicEDKey` / `alt-tab.app/appcast.xml` without owning that domain and lwouis's private key. Stand up own host + EdDSA key, or strip Sparkle.
4. **Keep crash diagnostics?** Remove AppCenter entirely (most privacy-aligned, but requires a replacement principal class) vs repoint to a self-owned AppCenter app (EoL).
5. **Rebase on pre-paywall v10.12.0** vs in-place removal — both yield the same unlocked feature set.

---

*Deep-dive sections: [`01-core-architecture`](audit/01-core-architecture.md) · [`02-switcher-ui`](audit/02-switcher-ui.md) · [`03-preferences-and-gating`](audit/03-preferences-and-gating.md) · [`04-license-subsystem`](audit/04-license-subsystem.md) · [`05-trial-nag-scheduling`](audit/05-trial-nag-scheduling.md) · [`06-profeature-and-copy`](audit/06-profeature-and-copy.md) · [`07-pro-ui-and-menubar`](audit/07-pro-ui-and-menubar.md) · [`08-build-release-distribution`](audit/08-build-release-distribution.md) · [`09-telemetry-and-upstream`](audit/09-telemetry-and-upstream.md)*
