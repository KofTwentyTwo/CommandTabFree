# 07 — Pro Upsell UI Overlay & Menu-bar Integration

**Scope:** `src/pro/ui/` (the shared upsell UI toolkit) and `src/Menubar.swift` (the
`NSStatusItem` menu and its license/trial/badge integration).

This section documents every upsell-specific UI component, how `ProPromptHost.dispatch`
routes the timed Day-X prompts, every menu-bar item that is license / trial / upsell
related, and what the menu bar should look like once the paywall is removed.

> Cross-references: the Day-X window/popover classes live in `src/pro/scheduling/`
> (audited separately). The coordinator that *emits* prompt actions is
> `ProTransitionManager` (`src/pro/scheduling/ProTransitionManager.swift`). License state
> lives in `src/pro/license/`. This section only covers the *UI receivers* of those
> emissions and the menu-bar surface.

---

## 1. The `src/pro/ui/` toolkit

`src/pro/ui/` is a small library of reusable AppKit building blocks. None of these classes
contain license/trial *logic* themselves — they are pure presentation primitives consumed
by the Day-X scheduling windows (in `src/pro/scheduling/`) and by the Settings "Upgrade"
tab (`src/preferences/settings-window/tabs/UpgradeTab.swift`). They exist *only* to render
the paywall/upsell, so all of them are deletion candidates for a fully-free build, but
several are referenced from non-pro code and must be untangled (see §1.8).

### 1.1 `ProPromptHost.swift` — the dispatch hub
`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/pro/ui/ProPromptHost.swift`

A singleton (`ProPromptHost.shared`, line 9) whose sole job is to translate the abstract
`ProPromptAction` enum into concrete Day-X UI calls. It is wired at launch in
`src/App.swift:428`:

```swift
ProTransitionManager.shared.onAction = { ProPromptHost.shared.dispatch($0) }
```

`dispatch(_:)` (lines 11–38) is a single `switch` over `ProPromptAction`
(defined in `src/pro/scheduling/ProTransitionManager.swift:87-98`). The complete routing
table:

| `ProPromptAction` case | Source line | UI call made | Day label |
|---|---|---|---|
| `.showWelcome` | `ProPromptHost.swift:13-14` | `Day1WelcomeLetterWindow.show()` | [A] Day 1 |
| `.showDay4Tour` | `:15-16` | `Day4TourPopover.show()` | [H] Day 4 |
| `.showDay12HeadsUp` | `:17-19` | `Day12HeadsUpPopover.show()` **then** `Menubar.menubarIconCallback(nil)` | [B] Day 12 |
| `.showDay15Proactive` | `:20-21` | `Day15ProactiveWindow.show()` | [D] Day 15 |
| `.showDay15FullUpgrade(reason)` | `:22-23` | `Day15FullUpgradeWindow.show(for: reason)` | [C] Day 15 |
| `.showDay15HardGatePopover(reason)` | `:24-25` | `Day15HardGatePopover.show(for: reason)` | [E] Day 15 hard gate |
| `.showDay21Reminder` | `:26-27` | `Day21ReminderPopover.show()` | [F] Day 21 |
| `.showDay35Final` | `:28-29` | `Day35FinalWindow.show()` | [G] Day 35 |
| `.dismissAllProWindows` | `:30-34` | closes the four singleton windows (Day1/Day15Full/Day15Proactive/Day35) | on upgrade-to-pro |
| `.refreshBadge` | `:35-36` | `Menubar.menubarIconCallback(nil)` | menu-bar badge dot refresh |

Two cases reach back into the menu bar: `.showDay12HeadsUp` (line 19) and `.refreshBadge`
(line 36) both call `Menubar.menubarIconCallback(nil)` to repaint the orange badge dot
(see §2.5). The window-class APIs the host calls were verified to exist:
`show()` / `show(for:)` static methods and `shared?` optionals on the window subclasses.

### 1.2 `ProPromptPopover.swift` — popover plumbing
`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/pro/ui/ProPromptPopover.swift`

An `enum` namespace (no instances) with two static helpers used by the four menu-bar-anchored
Day-X popovers ([B] Day 12, [E] Day 15 hard gate, [F] Day 21, [H] Day 4):
- `make(contentSize:)` (lines 10–15) builds a `.transient` `NSPopover`.
- `present(_:content:)` (lines 18–25) sets the content VC, activates the app, then anchors
  the popover under the menu-bar icon via `Menubar.showPopoverFromMenubar(popover)`
  (line 23) — its only coupling to `Menubar`.

### 1.3 `ProPromptWindow.swift` — base window chrome
`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/pro/ui/ProPromptWindow.swift`

`NSWindow` subclass (lines 7–26) providing the shared chrome for the four non-modal Day-X
*windows* ([A] Welcome, [C] Full Upgrade, [D] Proactive, [G] Final): hidden titlebar,
hidden traffic-light buttons, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`,
and `Esc`→`close()` (line 23-25). Title is hard-coded `"AltTab Pro"` (line 12).

### 1.4 `ProPromptHeader.swift` — branded window header
`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/pro/ui/ProPromptHeader.swift`

`NSStackView` subclass (lines 10–64) drawing an app-icon + title row at the top of every
Day-X window. Notable: it auto-replaces the last `"Pro"` substring in the title with a
gradient text attachment from `ProGradient.makeProTextAttachment` (lines 55–63). Consumed by
Day1/Day15Full/Day15Proactive/Day35 windows (see §1.8).

### 1.5 `ProGradientButton.swift` — the gradient CTA button
`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/pro/ui/ProGradientButton.swift`

`NSButton` subclass (lines 3–100) rendering the pink→blue gradient "buy" button used as the
primary CTA across the upsell. Custom layer-based gradient fill (line 8, using
`ProGradient.makeLayer`), drop shadow, and a hover "shine" sweep animation
(`playShineAnimation`, lines 74–99). Subclassed by Settings: `UpgradeButton`
(`SettingsWindow.swift:133`) and `ProHeroButton` (`UpgradeTab.swift:493`).

### 1.6 `UsageStatHeroView.swift` — "your usage so far" stat block
`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/pro/ui/UsageStatHeroView.swift`

`NSStackView` subclass (lines 22–140) rendering a guilt/value-framing hero block driven by
`UsageStats.triggerCount` and `UsageStats.usedProFeaturesSessionCount` (read at init and on
`refresh()`, lines 64–65). Three render modes (both counts >0 → two columns; only triggers
→ one column; both zero → omitted). The "Pro feature uses" column number is drawn as a
gradient image (lines 84-88, 112-117). Lead-in copy is `"YOUR USAGE SO FAR"` (line 69).
Consumed by Day15Full, Day15Proactive, Day35 windows and the Upgrade tab (see §1.8).

### 1.7 `ProBadgeView.swift` — the "Pro" pill + gradient utilities (largest file)
`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/pro/ui/ProBadgeView.swift`

This 458-line file actually contains **five** distinct types, only the last of which is the
badge view proper:

1. **`enum ProGradient`** (lines 3–119) — the gradient color/geometry definitions
   (lines 4–13) plus rendering helpers: `makeLayer`, `makeGradientTextImage`,
   `makeProTextAttachment`, `makeGradientTextAttachment` (used for menu rows showing
   "Get Pro" per the line 70 comment), `makeFullProBadgeImage` (renders the badge into an
   `NSImage` for `NSMenuItem.image` / closed `NSPopUpButton` face, lines 90–101), and
   `drawGradientFill`. This enum is the shared dependency of basically every other upsell
   surface (the gradient menu pill, the Pro segment overlays in Settings, etc.).
2. **`class ProDropdownItemView`** (lines 124–187) — a custom `NSMenuItem.view` that draws a
   title + full Pro pill in a dropdown row, with its own highlight handling. (Used by
   Settings dropdowns, **not** the menu bar.)
3. **`class NotAdvisedButton`** (lines 190–200) — the small gray "discouraged action" link
   button ("Not now", "Maybe later", "Continue with Free", "No thanks…"). Consumed by all
   Day-X dismiss links (see §1.8).
4. **`class DynamicColorImageView`** (lines 205–213) — state-aware tinted image view used by
   the Pro-segment overlay in Settings.
5. **`class ProBadgeView`** (lines 215–458) — the actual "Pro" pill. Includes static helpers
   `attach(to:segmentIndex:…)` (lines 257–318) and `refreshSelection(…)` (lines 323–327)
   that overlay a Pro badge on a `NSSegmentedControl` segment in Settings. Registers `"Pro"`
   with the Settings search index at init (line 344: `SettingsSearchIndex.registerString`).

> Note: despite the filename, the menu-bar code does **not** instantiate `ProBadgeView`
> directly. Menubar uses `ProGradient.makeLayer` (indirectly, via `UpgradeMenuItemView`)
> and the orange dot is a hand-rolled `CALayer`, not a `ProBadgeView`.

### 1.8 Consumers of the toolkit (untangle map for removal)

Confirmed via grep across `src/`. These are the call sites that will break if `src/pro/ui/`
is deleted wholesale:

| Toolkit type | Consumed by | File:line |
|---|---|---|
| `ProGradientButton` | `UpgradeButton` (Settings) | `preferences/settings-window/SettingsWindow.swift:133` |
| `ProGradientButton` | `ProHeroButton` (Upgrade tab) | `preferences/settings-window/tabs/UpgradeTab.swift:493` |
| `UsageStatHeroView` | Upgrade tab hero | `preferences/settings-window/tabs/UpgradeTab.swift:5,37` |
| `UsageStatHeroView` | Day15Full / Day15Proactive / Day35 | `pro/scheduling/Day15FullUpgradeWindow.swift:56`, `Day15ProactiveWindow.swift:38`, `Day35FinalWindow.swift:27` |
| `ProPromptHeader` | Day1 / Day15Full / Day15Proactive / Day35 | `pro/scheduling/Day1WelcomeLetterWindow.swift:22`, `Day15FullUpgradeWindow.swift:53`, `Day15ProactiveWindow.swift:34`, `Day35FinalWindow.swift:23` |
| `NotAdvisedButton` | Day12 / Day15Full / Day15HardGate / Day15Proactive / Day21 / Day35 | `pro/scheduling/Day12HeadsUpPopover.swift:28`, `Day15FullUpgradeWindow.swift:66`, `Day15HardGatePopover.swift:28`, `Day15ProactiveWindow.swift:48`, `Day21ReminderPopover.swift:34`, `Day35FinalWindow.swift:37` |
| `ProGradient` / `ProBadgeView.attach` | Settings tabs (Appearance/Controls Pro segments, search index) | `SettingsSearchIndex.swift`, `AppearanceTab.swift`, `ControlsTab.swift`, `LabelAndControl.swift` (per earlier grep on `ProTransitionManager`/badge usage) |

Because every Day-X scheduling class is being removed in the same effort, the
`src/pro/ui/` types whose *only* surviving consumers are the Settings Upgrade tab are
`ProGradientButton`, `UsageStatHeroView`, and the `ProGradient`/`ProBadgeView` segment
helpers. Those will be resolved when the Upgrade tab and Pro-segment overlays are removed.

---

## 2. `src/Menubar.swift` — the `NSStatusItem` menu

`/Users/james.maes/Git.Local/kof22/alt-tab-free/src/Menubar.swift`

`Menubar` is the always-present `NSStatusItem`. Most of it (Show / Settings / Check for
updates / Check permissions / About / Send feedback / Quit, the menu-bar icon preference,
removal-from-menubar observation, the Screen-Recording `PermissionCallout`) is **not**
paywall-related and must survive. The paywall touch-points are isolated to the three
license-driven menu items, the `refreshLicenseMenuItems` state machine, the
`UpgradeMenuItemView`, and the badge-dot overlay.

### 2.1 Stored upsell menu items
Lines 8–10 declare three license-driven items as static vars:
```swift
private static var upgradeToProMenuItem: NSMenuItem!   // line 8
private static var supportProjectMenuItem: NSMenuItem!  // line 9
private static var myAccountMenuItem: NSMenuItem!       // line 10
```

### 2.2 Menu construction (`initialize()`, lines 27–66)
The non-pro items are added at lines 37–45 (Show, Settings, Check for updates, Check
permissions, About, **Debug tools**, Send feedback). The three pro items are added
immediately after:

- **Line 46:** `upgradeToProMenuItem = addMenuItem("Get Pro", App.upgradeToProAction, "", "star.fill", …)`
  — the "Get Pro" upsell entry. Its action `App.upgradeToProAction`
  (`App.swift:26`) → `@objc App.upgradeToPro()` (`App.swift:115-117`) →
  `ProTransitionManager.openCheckout()` → opens `Endpoints.checkoutUrl`
  (`ProTransitionManager.swift:307-308`; URL `…/pricing`, `Endpoints.swift:9`).
- **Line 47:** `upgradeToProMenuItem.view = UpgradeMenuItemView()` — replaces the row with the
  custom gradient view (§2.4).
- **Line 48:** `myAccountMenuItem = addMenuItem("My Account", App.openAccountAction, …)` —
  action `App.openAccountAction` (`App.swift:27`) → `App.openAccount()`
  (`App.swift:119-121`) → `UpgradeTab.openAccountPage()` → opens `Endpoints.accountUrl`
  (`…/my-account`, `Endpoints.swift:10`).
- **Line 49:** `supportProjectMenuItem = addMenuItem("Support this project", App.supportProjectAction, …, .red, …)`
  — heart icon, action `App.supportProjectAction` (`App.swift:25`) →
  `App.supportProject()` (`App.swift:111-113`) → opens `Endpoints.supportUrl`
  (`…/support`, `Endpoints.swift:8`).
- **Line 50:** `refreshLicenseMenuItems()` — runs the state machine to show/hide these three.

> Upstream AltTab (the GPL parent) historically shipped a "Support this project" /
> donate item; "Get Pro" and "My Account" are the fork's proprietary additions. Whether to
> keep "Support this project" in the free build is a product decision (see §3), but it is
> currently gated by the same `refreshLicenseMenuItems` state machine.

### 2.3 `refreshLicenseMenuItems()` state machine (lines 84–107)
Reads `LicenseManager.shared.state` (`LicenseState`, defined
`pro/license/LicenseState.swift:1-21`) and shows/hides the three items per state:

| `LicenseState` | "Get Pro" (upgrade) | "Support this project" | "My Account" |
|---|---|---|---|
| `.trial(daysRemaining)` | shown | hidden | hidden |
| `.pro` | **removed** (`toggleUpgradeMenuItem(false)`) | hidden | shown |
| `.proExpired` | shown | shown | shown |
| `.trialExpired` | shown | shown | hidden |

- `.pro` early-returns at line 105 *before* calling `updateContent`, so the gradient view's
  text is only refreshed for non-pro states (line 106).
- `toggleUpgradeMenuItem(_:)` (lines 109–118) inserts/removes `upgradeToProMenuItem`
  relative to `supportProjectMenuItem`'s index — the "Get Pro" row is fully removed from the
  menu (not just `isHidden`) for Pro users, because `NSMenuItem.isHidden` is unreliable with
  custom views (same pattern as the permission callout, comment at line 135).

`refreshLicenseMenuItems()` is invoked from:
- `Menubar.initialize()` line 50 (initial build).
- `App.swift:450` inside `LicenseManager.shared.onStateChanged` (license state transitions).

### 2.4 `UpgradeMenuItemView` (lines 235–390)
Custom `NSView` set as `upgradeToProMenuItem.view`. Renders the gradient "Get Pro" pill in
the menu with a two-line label and a `star.fill` icon (lines 269–275, tinted white). Uses
`ProGradient.makeLayer()` (line 247) for the backdrop and has its own hover "shine"
animation (`playShineAnimation`, lines 328–355) mirroring `ProGradientButton`.

- `updateContent(_ state:)` (lines 357–382) builds the two-line attributed string. The
  **trial day count** appears here: line 370-371,
  `String(format: "Trial: %d days remaining", daysRemaining)` for `.trial`; line 372-373
  `"License doesn't cover this version"` for `.proExpired`; else `"Trial expired"`
  (line 375). Second line is always `"Get Pro"` (line 380).
- `mouseUp` (lines 384–389) cancels menu tracking and calls `App.upgradeToPro()`
  (opens checkout).

### 2.5 The orange badge dot overlay (lines 187–227)
A hand-rolled 7pt orange `CALayer` (`systemOrange`, line 221) anchored to the bottom-right
of the menu-bar icon, signalling "the trial is ending / there's an upsell to see."
- `badgeDotLayer` static var (line 187).
- `updateBadgeDotOverlay()` (lines 202–227): removes any existing dot, then
  **guards on `ProTransitionManager.shared.shouldShowBadgeDot`** (line 205). If false (or
  no button), it stops — so the dot only appears when the transition manager says so
  (`shouldShowBadgeDot` defined `ProTransitionManager.swift:161-162`, delegating to
  `ProTransitionManagerTestable.shouldShowBadgeDot`). Otherwise it builds the orange dot
  layer.
- Invoked only from `loadPreferredIcon()` (line 196), which runs inside
  `applyMenubarIconPreferences()` → `menubarIconCallback(_:)` (lines 155–164). That callback
  is the entry point `ProPromptHost` calls (lines 19, 36) to repaint the dot, and is also
  called from `PreferencesEvents.swift:79` and `QAMenu.swift:240` (non-pro icon-pref
  changes also repaint, harmlessly).

### 2.6 `MenubarMenuDelegate` (lines 392–399)
`menuWillOpen` calls `LicenseManager.shared.refreshState()` (line 396) so the trial-day
subtitle in `UpgradeMenuItemView` reflects the current clock at open time, then
`Menubar.refreshPermissionCallout()` (line 397, non-pro). The `refreshState()` call is the
license/trial coupling here; the permission-callout refresh is independent and must stay.

### 2.7 Non-pro menu-bar code (must survive untouched)
For clarity on what is *not* in scope for removal: `addMenuItem` helper (14–25), the
QA-menu middle-click monitor (DEBUG only, 68–82), `refreshPermissionCallout` /
`togglePermissionCallout` / `PermissionCallout` (120–144, 401–445), `statusItemOnClick`
(146–153), the icon-preference + removal-observer machinery (166–197 minus the badge-dot
call at 196), and `showPopoverFromMenubar` (229–232). Note `showPopoverFromMenubar` is used
*only* by the Day-X popovers via `ProPromptPopover.present`, so after the paywall is removed
it becomes dead code and can be deleted too.

---

## 3. What the menu bar should look like with the paywall gone

After removing the trial/license/upsell system, the `NSStatusItem` menu should reduce to
the upstream-style set of items:

```
Show
─────────
Settings…
Check for updates…
Check permissions…
─────────
About AltTab
Debug tools            (DEBUG builds only — see note)
Send feedback…
Support this project    (product decision — see below)
─────────
Quit AltTab
```

Concrete `Menubar.swift` changes required for a clean free build:

- **Remove the three license-driven items and their wiring:**
  - Delete the three static vars at lines 8–10.
  - Delete line 46 (`Get Pro`), line 47 (`.view = UpgradeMenuItemView()`), line 48
    (`My Account`), and the `refreshLicenseMenuItems()` call at line 50. ("Support this
    project" at line 49 is the only one of the four that has upstream precedent — keep or
    drop per product decision; if kept, add it unconditionally and stop hiding it.)
- **Delete `refreshLicenseMenuItems()` (84–107) and `toggleUpgradeMenuItem(_:)` (109–118)**
  entirely — both reference `LicenseManager`/`LicenseState`.
- **Delete the `UpgradeMenuItemView` class (235–390)** — it is the gradient pill, the trial
  day-count renderer, and the checkout `mouseUp`. Its only consumer is line 47.
- **Delete the badge-dot overlay** (`badgeDotLayer` line 187; `updateBadgeDotOverlay()`
  202–227) and remove its call at line 196 inside `loadPreferredIcon()`. With it gone,
  `loadPreferredIcon` no longer depends on `ProTransitionManager`.
- **Simplify `MenubarMenuDelegate.menuWillOpen` (392–399)** — drop the
  `LicenseManager.shared.refreshState()` call at line 396; keep
  `refreshPermissionCallout()` (line 397).
- **`menubarIconCallback(_:)` (155–164)** can stay (it is also the icon-preference entry
  point), but its callers in `ProPromptHost.swift:19,36` disappear with the host. The
  `applyMenubarIconPreferences`/`loadPreferredIcon` path remains valid for the
  PreferencesEvents/QAMenu callers.
- **`showPopoverFromMenubar` (229–232)** becomes dead code (only the Day-X popovers used it)
  and can be removed.

In `src/App.swift`: remove `supportProjectAction`/`upgradeToProAction`/`openAccountAction`
(25–27) and the `@objc supportProject/upgradeToPro/openAccount` methods (111–121) if their
endpoints (`pricing`, `my-account`, `support`) are also dropped; remove the
`ProTransitionManager.shared.onAction = …` wiring (line 428) and the
`Menubar.refreshLicenseMenuItems()` call inside `onStateChanged` (line 450).

The entire `src/pro/ui/` directory can be deleted **once** its non-pro consumers in
`src/preferences/settings-window/` (the Upgrade tab, the Pro-segment overlays via
`ProBadgeView.attach` / `ProGradient`, and the search-index `"Pro"` registration at
`ProBadgeView.swift:344`) are removed in the Settings audit. Until then,
`ProGradient`, `ProGradientButton`, `UsageStatHeroView`, and the `ProBadgeView` segment
helpers are still referenced and would break the build if deleted prematurely.

> **Note on "Debug tools":** it is added unconditionally at `Menubar.swift:44` in this fork
> (not behind `#if DEBUG`), unlike the QA-menu monitor. Leaving it is orthogonal to the
> paywall; flag it for the product owner but it is not a removal blocker.
