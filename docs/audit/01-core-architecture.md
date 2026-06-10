# 01 — Core Application Architecture & Lifecycle

> Audit scope: the app entry point, `App.swift` (`NSApplicationDelegate`), and `src/macos/`
> (permissions, accessibility, login item, AX scheduling). This is the spine the rest of the
> paywall-removal audit hangs on. **Read-only audit — no source was modified.**

All `file:line` references are against the tree as audited (branch `master`, commit `9fadf36b`).

---

## 1. Entry point & process bootstrap

The app has **no `@main` / `@NSApplicationMain`**. It uses a top-level `main.swift`
(`src/main.swift`) as the executable entry, per the AGENTS.md "pure Swift, no Interface Builder"
constraint.

Boot order in `src/main.swift`:

1. `src/main.swift:4-6` — CLI fast-path. If launched with a recognized CLI command
   (`CliClient.detectCommand()`), it forwards the command to the already-running instance via a
   Mach message port and the process exits early (never becomes the GUI app).
2. `src/main.swift:11-15` — installs POSIX signal handlers for `SIGTERM` / `SIGTRAP` that call
   `emergencyExit(...)`.
3. `src/main.swift:19-21` — installs `NSSetUncaughtExceptionHandler` (Obj-C exceptions) → also
   `emergencyExit(...)`.
4. `src/main.swift:23` — `App.shared.run()` enters the AppKit run loop.

`emergencyExit` (`src/main.swift:33-39`) re-enables the native ⌘-Tab
(`setNativeCommandTabEnabled(true)`), prints a stack trace, drains in-flight screen captures
(`makeSureAllCapturesAreFinished()`, `src/main.swift:41-51`, which sets `App.isTerminating = true`
and spins up to 5 s waiting on `ActiveWindowCaptures.value()`), then `exit(0)`.

**Paywall touchpoint in entry path:** none. `main.swift` is clean.

---

## 2. The `App` class

`App` (`src/App.swift:7`) subclasses `AppCenterApplication` (a Microsoft AppCenter `NSApplication`
subclass, used for crash reporting) and sets itself as its own delegate
(`src/App.swift:41-44`, `delegate = self`). It conforms to `NSApplicationDelegate` in the extension
at `src/App.swift:434-507`.

It is a hybrid singleton: instance methods satisfy the `NSApplicationDelegate` protocol, but the
bulk of the app's coordination logic lives in `static` methods/properties on `App` (e.g.
`App.showUi`, `App.hideUi`, `App.refreshUi`, `App.continueAppLaunchAfterPermissionsAreGranted`).
`App.shared` (`src/App.swift:24`) downcasts `NSApplication.shared`.

Notable static state:
- `App.isTerminating` (`src/App.swift:28`) — read by the capture-drain loop.
- `App.activity` (`src/App.swift:9-10`) — a `ProcessInfo.beginActivity` token preventing App Nap.
- `App.sparkleDelegate` / `App.updaterController` (`src/App.swift:35-36`) — Sparkle auto-update.
- Selectors `supportProjectAction` / `upgradeToProAction` / `openAccountAction`
  (`src/App.swift:25-27`) — wired into the menubar (see §7).

---

## 3. Startup sequence (the two-phase launch)

Launch is **deliberately two-phase**, gated on macOS permissions. This split is structurally
important for the removal plan because the paywall is initialized in **phase A** and the rest of the
app only boots in **phase B** after permissions pass.

### Phase A — `applicationDidFinishLaunching` (`src/App.swift:435-463`)

Runs immediately on launch, before any permission is confirmed:

1. `:436` `AppCenterCrash()` — crash reporting.
2. `:437` `disableRelaunchOnLogin()`.
3. `:438-439` `Logger.initialize()` + version log.
4. `:444` (release only) `MoveToApplicationsFolder.promptIfNeeded()`.
5. `:446` `AXUIElement.setGlobalTimeout()` — sets the global 1 s AX messaging timeout.
6. `:447` `Preferences.initialize()` — loads `UserDefaults`, runs migrations.
7. **`:448-460` License/Pro wiring (PAYWALL).** Wires three `LicenseManager.shared` callbacks and
   calls `LicenseManager.shared.initialize()`. Detailed in §6.
8. `:461` `BackgroundWork.preStart()` — creates the *minimal* early queues needed for permission
   polling (`permissionsCheckOnTimerQueue`, `permissionsSystemCallsQueue`, `screenshotsQueue`;
   `src/util/BackgroundWork.swift:23-30`).
9. `:462` `SystemPermissions.ensurePermissionsAreGranted()` — starts the permission timer (see §5).

Phase A does **not** create the switcher panel, menubar, or any event taps. If permissions are
missing, the app sits in the permission-window loop and never proceeds to phase B.

### Phase B — `App.continueAppLaunchAfterPermissionsAreGranted` (`src/App.swift:383-431`)

Called **once**, from `SystemPermissions.checkPermissionsPreStartup()`
(`src/macos/SystemPermissions.swift:77`), the moment both Accessibility and Screen-Recording
permissions are confirmed. This is the real subsystem-wiring sequence:

| Line | Call | Subsystem |
|------|------|-----------|
| `:385` | `BackgroundWork.start()` | full set of background threads/queues (§4) |
| `:386` | `NSScreen.updatePreferred()` | display state |
| `:387` | `Appearance.update()` | switcher theming |
| `:388-389` | `TilesPanel.updateMaxPossible…Size()` | layout precompute |
| `:390` | `Menubar.initialize()` | menubar status item (**touches license**, §7) |
| `:391` | `MainMenu.create()` | app main menu |
| `:392-393` | `TilesPanel()` / `PreviewPanel()` | switcher windows |
| `:394-395` | `Spaces.refresh()` / `Screens.refresh()` | spaces & displays state |
| `:396-405` | `*.observe()` for Spaces, Screens, SystemAppearance, SystemScrollerStyle, InputSource, Cursor, Trackpad, Cli; plus `Applications.initialDiscovery()`; `KeyboardEvents.addEventHandlers()` | event observers / taps (§8) |
| `:406-413` | `SparkleDelegate()` + `SPUStandardUpdaterController`, updater started 30 s later | auto-update |
| `:414` | `PreferencesEvents.initialize()` | applies side-effects of every preference |
| `:415` | `BenchmarkRunner.startIfNeeded()` | dev benchmark |
| `:416-420` | first-launch Settings window (`showSettingsWindowOnFirstLaunchIfNeeded`) | UI (**license-aware**, §6) |
| `:421-426` | `#if DEBUG` QA menu / debug graph | dev-only |
| `:427` | `UsageStats.prune()` | usage telemetry |
| **`:428-429`** | **`ProTransitionManager.shared.onAction = …` + `onAppLaunchComplete()`** | **PAYWALL** (§6) |

`Applications.initialDiscovery()` (`src/App.swift:401`) is also where the NSWorkspace
running-applications observer gets installed: it calls `RunningApplicationsEvents.observe()`
internally (`src/switcher/state/Applications.swift:20`).

---

## 4. Background threading model (`BackgroundWork`)

`src/util/BackgroundWork.swift`. The app is heavily multithreaded because most macOS hooks
(CGEvent taps, AX observers, Mach ports) require their own run loops, and AX calls can block for the
1 s timeout.

- **Dedicated run-loop threads** (`BackgroundThreadWithRunLoop`, `:106-137`):
  `accessibilityEventsThread`, `keyboardAndMouseAndTrackpadEventsThread`, `missionControlThread`,
  `cliEventsThread`. Each runs a `CFRunLoopRun()` with a dummy source to stay alive
  (`:131-136`). Created in `start()` (`:43-49`).
- **Operation queues** (`LabeledOperationQueue`, `:140-160`): `repeatingKeyQueue`,
  `screenshotsQueue`, `accessibilityCommandsQueue`, `focusOrderQueue`, `crashReportsQueue`,
  `permissionsCheckOnTimerQueue`, `permissionsSystemCallsQueue`.
- `preStart()` (`:23-30`) creates only the three queues needed before permissions; `start()`
  (`:32-50`) creates the rest in phase B.
- Thread budget is policed: `addPotentialThreadCount` asserts the total stays ≤ 45 against the
  ~64-thread process limit (`:59-63`).

The separate `AXCallScheduler` (`src/macos/AXCallScheduler.swift`) owns three more bounded pools
for *outgoing* AX queries (`axQueryFirstTryQueue` 10, `axQueryScanQueue` 6, `axQueryRetryQueue` 8;
`:43-45`). It is a per-key serializing executor with retry/backoff for unresponsive apps
(`schedule(...)`, `:51-71`; `attemptBlock`, `:113-169`). It does **no** throttling/coalescing —
that is the caller's job. **No paywall coupling.**

**Paywall touchpoint in threading:** none. `BackgroundWork` and `AXCallScheduler` are clean.

---

## 5. How permissions are requested (`src/macos/SystemPermissions.swift`)

`SystemPermissions` drives a `DispatchSourceTimer` on `permissionsCheckOnTimerQueue`.

- `ensurePermissionsAreGranted()` (`:22-27`) creates the timer with handler
  `checkPermissionsOnTimer` and fires it immediately.
- **Pre-startup** (`checkPermissionsPreStartup`, `:70-84`): if both
  `AccessibilityPermission.status` and `ScreenRecordingPermission.status` are not-`.notGranted`,
  it flips `preStartupPermissionsPassed = true`, closes the permission window, switches to the
  infrequent timer, starts the distributed-notification revoke listener, and calls
  **`App.continueAppLaunchAfterPermissionsAreGranted()`** (`:77`). Otherwise it shows the
  permissions window (`:81`).
- **Post-startup** (`checkPermissionsPostStartup`, `:86-91`): if Accessibility is revoked while
  running, it restarts the app (`App.restart()`).
- **Revoke detection** (`startListeningForDistributedRevoke`, `:29-43`): observes the undocumented
  `com.apple.accessibility.api` distributed notification; on revoke → `App.restart()`. A sparse
  60 s backstop timer covers cases where the notification doesn't fire (`setInfrequentTimer`,
  `:96-103`).
- **Accessibility detection** (`AccessibilityPermission`, `:116-128`): `AXIsProcessTrustedWithOptions`
  with `kAXTrustedCheckOptionPrompt: false`.
- **Screen-recording detection** (`ScreenRecordingPermission`, `:130-217`): via
  `SCShareableContent.getExcludingDesktopWindows` (macOS 12.3+) or `CGDisplayStream` probing,
  each wrapped in a 6 s timeout (`runWithTimeout`, `:202-217`). Honors
  `Preferences.screenRecordingPermissionSkipped` (`:141`).

The permission UI window (`PermissionsWindow`) lives outside this scope
(`src/secondary-windows/permission-window/`).

**Paywall touchpoint in permissions:** none. `SystemPermissions.swift` is clean.

---

## 6. PAYWALL — every place the spine touches License / Pro

This section is the deliverable's core. Below is **every** reference in the spine (`App.swift`,
`Menubar.swift`, `main.swift`, `src/macos/`) to `LicenseManager`, `ProTransitionManager`,
`ProPromptHost`, checkout, and `UpgradeTab`.

### 6.1 `App.swift` — license wiring & callbacks

| `file:line` | Code | Purpose |
|-------------|------|---------|
| `src/App.swift:26` | `static var upgradeToProAction: Selector { #selector(App.upgradeToPro) }` | selector exposed to menubar "Get Pro" |
| `src/App.swift:27` | `static var openAccountAction: Selector { #selector(App.openAccount) }` | selector for menubar "My Account" |
| `src/App.swift:78` | `ProTransitionManager.shared.onSwitcherDismissed()` | inside `hideUi()` — ends free-pass session, queues post-dismiss upsell windows |
| `src/App.swift:115-117` | `@objc static func upgradeToPro() { ProTransitionManager.openCheckout() }` | opens checkout URL |
| `src/App.swift:119-121` | `@objc static func openAccount() { UpgradeTab.openAccountPage() }` | opens account page |
| `src/App.swift:206-207` | `if case .pro = LicenseManager.shared.state { return false }` / `return !ProTransitionManager.shared.hasSeenWelcome` | `willShowDay1WelcomeOnAppLaunch()` — defers first-launch Settings if the Day-1 welcome nag will show |
| `src/App.swift:328` | `ProTransitionManager.shared.onSwitcherShown()` | inside `showUiOrCycleSelection()` — decides Day-4 tour or post-expiration free-pass |
| `src/App.swift:428` | `ProTransitionManager.shared.onAction = { ProPromptHost.shared.dispatch($0) }` | binds the prompt-action emitter to the Day-X UI host |
| `src/App.swift:429` | `ProTransitionManager.shared.onAppLaunchComplete()` | starts the trial-nag scheduler |
| `src/App.swift:448` | `LicenseManager.shared.onBeforeProUnlock = { ProTransitionManager.shared.onProUnlocked() }` | restore Pro prefs on activation |
| `src/App.swift:449-459` | `LicenseManager.shared.onStateChanged = { state in … }` | the big state-change fan-out (see below) |
| `src/App.swift:460` | `LicenseManager.shared.initialize()` | computes initial license/trial state; **first thing that touches Keychain/UserDefaults trial bookkeeping** |
| `src/App.swift:480` | `UpgradeTab.showAutoActivating(licenseKey)` | custom-URL `alttab://activate` handler |
| `src/App.swift:481-489` | `LicenseManager.shared.activate(licenseKey) { … }` (+ `UpgradeTab.showAutoActivation{Success,Failed}`) | license activation via custom URL |

The `onStateChanged` closure (`src/App.swift:449-459`) does six things on every license-state
transition:
1. `Menubar.refreshLicenseMenuItems()` (`:450`)
2. `syncLicenseCookie(state:)` (`:451`) — defined in `src/pro/license/LicenseCookie.swift:5`,
   writes a Sparkle HTTP cookie so the appcast can serve license-aware updates.
3. `ProTransitionManager.shared.onLicenseStateChanged()` (`:452`)
4. `UpgradeTab.refreshStatus()` (`:453`)
5. `SettingsWindow.shared?.refreshUpgradeButton()` (`:454`)
6. `App.resetPreferencesDependentComponents()` if `TilesPanel.shared != nil` (`:455`), then posts
   `ProTransitionManager.proLockStateDidChangeNotification` (`:458`).

### 6.2 `App.swift` custom-URL scheme — license activation

`application(_:open:)` (`src/App.swift:465-471`) routes `alttab://` URLs to `handleCustomUrl`
(`:473-490`), which handles **only** `host == "activate"` with a `license_key` query item, calling
`LicenseManager.shared.activate(...)`. **The entire custom-URL handler exists solely for license
activation** — there is no other URL scheme use in the spine.

### 6.3 `Menubar.swift` — license-driven menu items & badge

`Menubar` is the other spine file with deep paywall coupling (it's created in phase B at
`src/App.swift:390`):

| `file:line` | Purpose |
|-------------|---------|
| `src/Menubar.swift:46-47` | builds the "Get Pro" item with a custom `UpgradeMenuItemView` |
| `src/Menubar.swift:48` | "My Account" item (`App.openAccountAction`) |
| `src/Menubar.swift:49` | "Support this project" item |
| `src/Menubar.swift:50` | calls `refreshLicenseMenuItems()` during build |
| `src/Menubar.swift:84-107` | `refreshLicenseMenuItems()` — switches visibility of Get-Pro/Account/Support items on `LicenseManager.shared.state` |
| `src/Menubar.swift:109-118` | `toggleUpgradeMenuItem()` — inserts/removes the Get-Pro item |
| `src/Menubar.swift:156-158` | comment referencing `LicenseManager.initialize()` ordering vs `statusItem` nil |
| `src/Menubar.swift:202-227` | `updateBadgeDotOverlay()` — gated on `ProTransitionManager.shared.shouldShowBadgeDot` (orange nag dot on the menubar icon) |
| `src/Menubar.swift:235-390` | `UpgradeMenuItemView` — the entire gradient/shine "Get Pro" menu cell, uses `ProGradient.makeLayer()` and `App.upgradeToPro()`; `updateContent(_ state: LicenseState)` renders trial-days-remaining |
| `src/Menubar.swift:392-399` | `MenubarMenuDelegate.menuWillOpen` → `LicenseManager.shared.refreshState()` |

### 6.4 `src/macos/` — license touchpoints

**None.** `SystemPermissions.swift`, `BackgroundWork.swift`, `AXCallScheduler.swift`,
`LoginItem.swift` contain no License/Pro references (verified by grep). The `src/macos/` layer is
paywall-free.

### 6.5 The contract the spine depends on (for the removal plan)

`App.swift` depends on this public surface of the Pro module:

- `LicenseManager.shared` (singleton, `src/pro/license/LicenseManager.swift:7-15`), with:
  `.state: LicenseState` (`:51`), `.initialize()` (`:91`), `.refreshState()` (`:99`),
  `.activate(_:completion:)` (`:104`), `.onStateChanged` (`:38`), `.onBeforeProUnlock` (`:49`),
  `.isProLocked` (`:67`), `.isProAvailable` (`:62`), `.daysSinceTrialStart` (`:79`),
  `.customerEmail` (`:55`).
- `LicenseState` enum (`src/pro/license/LicenseState.swift:1-5`): `.trial(daysRemaining:)`,
  `.pro`, `.proExpired`, `.trialExpired`.
- `ProTransitionManager.shared` (`src/pro/scheduling/ProTransitionManager.swift:105`), with the
  lifecycle hooks `onSwitcherShown/Dismissed`, `onAppLaunchComplete`, `onLicenseStateChanged`,
  `onProUnlocked`, `onAction`, `hasSeenWelcome`, `shouldShowBadgeDot`, the static
  `openCheckout()` (`:307`) and `proLockStateDidChangeNotification` (`:110`).
- `ProPromptHost.shared.dispatch(_:)` (`src/pro/ui/ProPromptHost.swift:9-11`).
- `UpgradeTab` static methods (`src/preferences/settings-window/tabs/UpgradeTab.swift`).
- `syncLicenseCookie(state:)` (`src/pro/license/LicenseCookie.swift:5`).

The **runtime feature gate** itself is `ProFeature.attemptUse()`
(`src/pro/ProFeature.swift:74-83`): returns `true` if `isProAvailable`, else if a free-pass
session is active, else routes hard-gated features through
`ProTransitionManager.shared.attemptHardGatedFeature(...)`. Call sites for the gate live outside
this scope (TilesView, ShortcutAction, SearchModeResolver) — see §9.

---

## 7. App-menu / window plumbing (license-adjacent)

`App` exposes several `@objc` window/show helpers wired into the menubar and main menu:
`showSettingsWindow` (`:137`), `showAboutWindow` (`:151`), `showFeedbackPanel` (`:123`),
`showDebugWindow` (`:132`), `showPermissionsWindow` (`:235`), `checkForUpdatesNow` (`:103`),
`checkPermissions` (`:107`), `supportProject` (`:111`). Of these, only `supportProject`,
`upgradeToPro`, `openAccount` are paywall-adjacent.

First-launch Settings logic (`showSettingsWindowOnFirstLaunchIfNeeded`, `:189-233`) is
**entangled with the Day-1 welcome nag**: it checks `willShowDay1WelcomeOnAppLaunch()`
(`:205-208`, reads `LicenseManager.shared.state` and `ProTransitionManager.shared.hasSeenWelcome`)
and, if the welcome window will appear, defers showing Settings until a `Day1WelcomeLetterWindow`
`willCloseNotification` fires (`:210-220`).

---

## 8. How AltTab hooks into macOS (event taps, AX observers, NSWorkspace)

The hooks are installed in phase B and live mostly under `src/events/`. Summary of the kernel of
macOS integration the rest of the audit will reference:

- **CGEvent tap (keyboard)** — `KeyboardEvents.addCgEventTap()`
  (`src/events/KeyboardEvents.swift:132-152`): a `.cghidEventTap` / `.headInsertEventTap` /
  `.defaultTap` tap for `.flagsChanged` + `.keyDown`, added to
  `BackgroundWork.keyboardAndMouseAndTrackpadEventsThread`'s run loop. If `tapCreate` returns nil
  (permission lost) → `App.restart()` (`:150`). Also a local `NSEvent` monitor
  (`:123-130`). The tap's `.keyDown` branch only absorbs Esc, and only when a shortcut binds it
  and the switcher is active (issue #5585 workaround, `:33-44`).
- **Carbon hotkeys** — `RegisterEventHotKey` for the global switcher shortcuts
  (`registerHotKeyIfNeeded`, `:104-120`; handlers installed in `addGlobalHandlerIfNeeded`,
  `:154-173`). `toggleGlobalShortcuts` (`:64-75`) registers/unregisters them when an app exception
  disables AltTab.
- **Accessibility (AX) observers** — `AccessibilityEvents.axObserverCallback`
  (`src/events/AccessibilityEvents.swift:6-21`). Subscriptions bake `(pid, wid)` into the
  `refcon` (`subscriptionRefcon`, `:25-28`). Focus/activation use an IPC-free fast lane
  (`updateFocusOrderFastLane`, `:38-56`) on `BackgroundWork.focusOrderQueue`; everything else is
  scheduled through `AXCallScheduler.shared` and dispatched to `handleEventApp` / `handleEventWindow`.
  These feed the window inventory (`Windows`, `Applications`) and drive
  `App.refreshOpenUiAfterExternalEvent` / `App.checkIfShortcutsShouldBeDisabled`.
- **NSWorkspace** — `RunningApplicationsEvents.observe()`
  (`src/events/RunningApplicationsEvents.swift:6-10`): KVO on
  `NSWorkspace.shared.runningApplications` (not the launch/terminate notifications, which miss
  non-GUI apps), feeding `Applications.addRunningApplications` / `removeRunningApplications`.
- **Other observers** wired at `src/App.swift:396-405`: Spaces, Screens, system appearance,
  scroller style, input source, cursor, trackpad, CLI (Mach message port).
- **Login item** — `src/macos/LoginItem.swift` writes/removes a launchd `LaunchAgents` plist
  keyed by `App.bundleIdentifier`; reconciled from `Preferences.startAtLogin` via
  `PreferencesEvents`.

None of the macOS hook installation is paywall-coupled. The only license interaction at runtime
is via `ProFeature.attemptUse()` invoked from feature call sites (§9), not from the tap/observer
plumbing itself.

---

## 9. Runtime feature gates reachable from the spine (out-of-scope files, noted for the plan)

The spine wires the managers; the actual *gating* happens when features run. For continuity with
later audit sections, the `ProFeature.attemptUse()` (`src/pro/ProFeature.swift:74`) call sites are:

- `src/switcher/main-window/TilesView.swift:79` (`lockSearchInSwitcher`), `:92` (`searchInSwitcher`)
- `src/switcher/ShortcutAction.swift:56` (`extraShortcut(index:)`)
- preference read interception: `src/preferences/PreferenceDefinition.swift:34-35`
  (`isProLocked` + `isFreePassSessionActive` swap stored Pro values for Free)

And the broader (non-spine) paywall coupling surface — settings UI badges, upgrade tab, and the
preference setter that bounces to the Upgrade tab — is concentrated in `src/preferences/...`,
`src/Menubar.swift`, `src/events/PreferencesEvents.swift:62-63`, and `src/debug/QAMenu.swift`
(DEBUG-only). These are covered by later audit sections; they are listed here only so the spine's
fan-out is traceable.

---

## 10. Removal-plan notes (spine only)

**Goal:** every `ProFeature.attemptUse()` should behave as if `isProAvailable == true`, and all
trial-nag / upsell windows and license activation should be gone, without breaking the two-phase
launch.

1. **`App.continueAppLaunchAfterPermissionsAreGranted` must keep its non-Pro work.** Only
   `src/App.swift:428-429` (the `onAction` binding + `onAppLaunchComplete`) is Pro. Removing those
   two lines stops the trial-nag scheduler. Everything else in this method (queues, panels,
   observers, Sparkle, first-launch Settings) must stay.
2. **`applicationDidFinishLaunching` license block (`src/App.swift:448-460`)** is the cleanest cut
   point. If the Pro module is deleted wholesale, all 13 lines (`:448-459` callback wiring +
   `:460` `initialize()`) go. **Risk:** `LicenseManager.shared.initialize()` is currently the
   place that seeds `trialStartDate` (`src/pro/license/LicenseManager.swift:193-194`); removing it
   is fine for a free build (nothing reads trial state once gating is unconditional), but any
   leftover reader of `LicenseManager.shared.state` will crash if the singleton is deleted.
3. **`onStateChanged` fan-out (`src/App.swift:449-459`)** has one non-Pro side effect worth noting:
   `App.resetPreferencesDependentComponents()` (`:455`) and the
   `proLockStateDidChangeNotification` post (`:458`). Both become dead once Pro is removed, but
   `resetPreferencesDependentComponents()` itself (`src/App.swift:51-53`) is a legitimate function
   used elsewhere — keep the function, drop this caller.
4. **`hideUi` / `showUiOrCycleSelection`** each have exactly one Pro line
   (`src/App.swift:78` and `:328`). Remove the `ProTransitionManager.shared.onSwitcher*` calls;
   the surrounding session logic is independent.
5. **`upgradeToPro` / `openAccount` / `supportProject`** (`src/App.swift:111-121`) and their
   selectors (`:25-27`) are only referenced by the menubar. Removing the corresponding
   `Menubar` items (`src/Menubar.swift:46-50`, the entire `UpgradeMenuItemView`
   `:235-390`, `refreshLicenseMenuItems` `:84-118`, badge dot `:202-227`, and the
   `MenubarMenuDelegate.menuWillOpen` license refresh `:392-399`) lets these selectors be deleted.
   `supportProject` (`Endpoints.supportUrl`) is a donation link, not a paywall — keep or drop per
   the owner's call.
6. **Custom-URL handler (`src/App.swift:465-490`).** The entire `application(_:open:)` +
   `handleCustomUrl` exists only for license activation. It can be removed entirely (and the
   `alttab://` URL scheme dropped from `Info.plist` — out of this scope but flagged).
7. **First-launch welcome entanglement (`src/App.swift:189-233`).** `willShowDay1WelcomeOnAppLaunch`
   (`:205-208`) and the deferral observer (`:210-220`) reference Pro. With the welcome nag gone,
   simplify `showSettingsWindowOnFirstLaunchIfNeeded` to always call
   `showAndCenterSettingsWindowOnFirstLaunch()` directly. **Risk:** if you delete
   `Day1WelcomeLetterWindow` but leave the `willCloseNotification` observer, the observer never
   fires and Settings never shows on first launch — remove the observer path together with the nag.
8. **Keychain / signing invariant (from AGENTS.md).** A free build that *keeps* `LicenseManager`
   alive (e.g. to avoid touching many call sites) must preserve `App.bundleIdentifier`, TeamID, and
   Developer ID, because `LicenseManager.keychainService` is `"\(App.bundleIdentifier).license"`
   (`src/pro/license/LicenseManager.swift:4`). A clean free build that deletes the Pro module
   entirely removes all Keychain usage and sidesteps this — preferred. Either way, do **not**
   rotate bundle ID without the migration AGENTS.md describes.
9. **`src/macos/` is safe.** No file under `src/macos/` references the paywall; the permission
   loop, AX scheduler, and login item need no changes. The phase-A→phase-B handoff
   (`SystemPermissions.swift:77` → `App.continueAppLaunchAfterPermissionsAreGranted`) is the
   critical path and is paywall-free.

---

### Appendix — files read for this section

`src/main.swift`, `src/App.swift`, `src/Menubar.swift`, `src/macos/SystemPermissions.swift`,
`src/macos/AXCallScheduler.swift`, `src/macos/LoginItem.swift`, `src/util/BackgroundWork.swift`,
`src/events/KeyboardEvents.swift`, `src/events/AccessibilityEvents.swift`,
`src/events/RunningApplicationsEvents.swift`, `src/switcher/SwitcherSession.swift`,
`src/pro/scheduling/ProTransitionManager.swift`, `src/pro/license/LicenseManager.swift`,
`src/pro/license/LicenseState.swift`, `src/pro/ProFeature.swift`,
`src/pro/ui/ProPromptHost.swift` (surface only), `src/pro/license/LicenseCookie.swift` (ref only).
