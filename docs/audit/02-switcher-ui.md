# Audit 02 — Switcher UI (the product itself)

Scope: `src/switcher/` and `src/events/`. This section covers how windows are
enumerated and modeled, how the switcher panel is rendered/updated, how
cycling/selection/focus works, the keyboard/shortcut event flow, and how all of
this consults preferences. Pro-gated behavior that surfaces in this subsystem is
called out explicitly with `file:line` references and summarized at the end.

All paths are relative to the repo root `/Users/james.maes/Git.Local/kof22/alt-tab-free`.

---

## 1. Window enumeration and modeling

### 1.1 The data model

The product is built around two model layers:

- **Live AppKit-coupled objects** — `Window` (`src/switcher/state/Window.swift`)
  and `Application` (`src/switcher/state/Application.swift`). These hold
  `AXUIElement` handles, AX observers, thumbnails, icons, etc.
- **Pure value records** — `WindowState` (`src/switcher/state/WindowState.swift`)
  and `ApplicationState`. These are `Equatable` structs containing only the
  "facts" (`isMinimized`, `isFullscreen`, `spaceIds`, `title`, `lastFocusOrder`,
  …) and are passed into the unit-testable decision "kernels"
  (`WindowFilterResolver`, `WindowOrderResolver`, `SelectionResolver`,
  `ExceptionMatcher`, `SearchModeResolver`).

`Window` is `@dynamicMemberLookup` over `WindowState`
(`src/switcher/state/Window.swift:3`, subscript at `:43-46`), so `window.title`,
`window.isMinimized`, etc. forward to `window.state`. This is purely a
convenience and has no paywall coupling.

Per-window fields of interest (`Window.swift:19-38`): `state`, `cgWindowId`,
`thumbnail: CALayerContents?`, `icon` (delegates to `application.icon`),
`shouldShowTheUser`, `tabbedSiblingWids`, `position`/`size`, `screenId`,
`axUiElement`, `application`, `axObserver`, `rowIndex`, search-result caches
(`swAppResults`, `swTitleResults`, `swBestSimilarity`, `lastSearchQuery`).

### 1.2 How windows are discovered

Discovery is **event-driven**, not poll-driven, and is rooted in `src/events/`:

1. **Accessibility (AX) notifications** drive everything. Each `Window` subscribes
   to a fixed set of AX notifications on creation
   (`Window.swift:5-12`: destroyed/title-changed/miniaturized/deminiaturized/
   resized/moved) via `observeEvents()` (`Window.swift:134-150`). The callback is
   `AccessibilityEvents.axObserverCallback`
   (`src/events/AccessibilityEvents.swift:6-21`).
2. The callback decodes the owning `(pid, wid)` from a packed `refcon`
   (`AccessibilityEvents.swift:25-33`) and routes through `AxEventRouting`
   (`src/events/AxEventRouting.swift`) to either app-level (`handleEventApp`,
   `AccessibilityEvents.swift:95-107`) or window-level (`handleEventWindow`,
   `:141-175`) handling.
3. `handleEventWindow` reads AX attributes (title, subrole, role, size, position,
   fullscreen, minimized, children for tab detection) and calls
   `Windows.findOrCreate(...)` (`AccessibilityEvents.swift:151`).
4. `Windows.findOrCreate` (`src/switcher/state/Windows.swift:390-400`) either
   updates an existing window (matched by `cgWindowId` via `byWindowId` or by
   `isEqualRobust`) or, gated by `WindowDiscriminator.isActualWindow(...)`, creates
   a new `Window` and calls `appendWindow`.

`WindowDiscriminator` (`src/switcher/state/WindowDiscriminator.swift`) is the
"is this a real, user-switchable window?" filter: it rejects `wid == 0`, missing
size, and windows smaller than 100x50 (`:8-19`), then accepts based on subrole
(`kAXStandardWindowSubrole`/`kAXDialogSubrole`) plus a large set of
app-specific special cases (Adobe, Steam, Firefox, VLC, JetBrains, Keynote,
Books, Crossover/Wine, scrcpy, AutoCAD, etc., `:20-44` and helpers). No paywall
logic here.

`appendWindow` (`Windows.swift:402-411`) appends to the canonical
`Windows.list`, registers it in `byWindowId`, assigns an initial
`lastFocusOrder`, and grows the recycled `TileView` pool if needed
(`TilesView.recycledViews`).

### 1.3 Spaces / screens / tab groups

- `Window.updateSpacesAndScreen` (`Window.swift:301-307`) populates `spaceIds`,
  `spaceIndexes`, `isOnAllSpaces`, and `screenId` from CGS, with a workaround for
  inactive tabs (`:309-320`).
- `recomputeIsInvisible()` (`Window.swift:124-126`) flags "ghost" windows
  (no Space, not tabbed/minimized/hidden).
- Tab groups are tracked via `TabGroup` (`src/switcher/state/TabGroup.swift`) and
  `tabbedSiblingWids`.

### 1.4 Window lifecycle / removal

`Windows.removeWindows` (`Windows.swift:413-483`) is the teardown path. Of note
(all memory-hygiene, no paywall): it releases pooled `TileView` IOSurfaces
(`:419-425`), clears `PreviewPanel` if it was showing a removed window
(`:427-431`), detaches the per-window AX observer runloop source via
`releaseAxObserver()` (`Window.swift:101-108`, `Windows.swift:473`), strips
`AXCallScheduler`/throttler entries, and re-shifts `lastFocusOrder`. It ends with
`App.refreshOpenUiAfterExternalEvent([], windowRemoved: true)`.

### 1.5 Per-show refresh

`Windows.updatesBeforeShowing()` (`Windows.swift:63-82`) runs each time the
switcher is summoned: refreshes Spaces, snapshots per-shortcut filter preferences
once (`WindowFilters.snapshot()`, `Windows.swift:507-519`), recomputes
`shouldShowTheUser` per window via `WindowFilterResolver.shouldShow(...)`
(`Windows.swift:105-125`), applies "only main windows" grouping
(`refreshWhichWindowsToShowTheUser`, `:89-103`, gated on
`Preferences.onlyShowMainWindows()`), and sorts. It returns `false` (and the show
aborts) if Mission Control is showing all/front windows.

---

## 2. The switcher panel: rendering and updating

### 2.1 Panel objects

- **`TilesPanel`** (`src/switcher/main-window/TilesPanel.swift`) — the main
  `NSPanel`. `.nonactivatingPanel`, floating, `level = .popUpMenu`, joins all
  Spaces, clear background, vibrant dark/light appearance
  (`TilesPanel.swift:11-32`, appearance at `:34-37`). Its content view is
  `TilesView.contentView`. Singleton `TilesPanel.shared`. Created in
  `App.swift:392` (`_ = TilesPanel()`).
- **`PreviewPanel`** (`src/switcher/PreviewPanel.swift`) — a separate `NSPanel`
  that shows a full-resolution preview of the *selected* window, ordered just
  below `TilesPanel` (`PreviewPanel.swift:46-53`). Created in `App.swift:393`.
  **This is the "preview selected window" feature** (see §6).

### 2.2 `TilesView` — the layout/render engine

`TilesView` (`src/switcher/main-window/TilesView.swift`) is a static class that
owns the scroll view, search field, "No Window" label, the recycled tile pool,
and the layout math. Key flow:

- `initialize()` (`:29-38`) sets up the search field, the no-window label, the
  background effect view, and pre-allocates **20** `TileView` objects into
  `recycledViews`.
- **Cell recycling**: `TileView`s are reused across shows. `recycledViews[i]` is
  bound to `Windows.list[i]` during layout. Tiles past the visible/list count get
  their image references released and `window_ = nil`
  (`:514-519`, `:455`).
- `updateItemsAndLayout(_:)` (`:386-412`) is the entry point called by
  `TilesPanel.updateContents` (`TilesPanel.swift:39-49`). It computes max width,
  optionally resolves "auto" size, lays out tiles into rows
  (`layoutTileViews`, `:471-529`), positions parent views
  (`layoutParentViews`, `:549-601`), centers rows, and re-highlights the
  selection.
- `TileView` (`src/switcher/main-window/TileView.swift`) renders a single cell:
  thumbnail layer, app-icon layer, title label, status icons, dock label badge,
  windowless-app indicator. The chosen content depends on the **appearance
  style** (`thumbnails` / `appIcons` / `titles`) read via
  `Preferences.effectiveAppearanceStyle(...)` (e.g. `TileView.swift:52, 64, 82`).
- Companion views: `TileOverView` (hover/window-controls overlay + hit-testing),
  `TileUnderLayer` (highlight rectangle), `StatusIconsView`, `TileTitleView`,
  `TileFontIconView`, `TilesPanelBackgroundView` (all under
  `src/switcher/main-window/`).

### 2.3 Show / hide / refresh orchestration (in `src/App.swift`)

The switcher's lifecycle methods live in `App.swift`, not in `src/switcher/`, but
they are the orchestration glue:

- `App.showUiOrCycleSelection(shortcutIndex, forceDoNothingOnRelease)`
  (`App.swift:307-351`) — creates the `SwitcherSession` if absent, records usage
  (`UsageStats.recordTrigger`, see §6), and on the first summon (or a
  different shortcut index) rebuilds: updates preferred screen, sorts by level on
  the very first summon, hides the panel (`alpha = 0`) to mask the rebuild,
  **notifies the trial/upsell scheduler** via
  `ProTransitionManager.shared.onSwitcherShown()` (`App.swift:328`, see §6),
  starts the search session, runs `updatesBeforeShowing`, picks the initial
  selection, then displays after `Preferences.windowDisplayDelay`. If the same
  shortcut is held, it cycles instead (`:347-350`).
- `App.buildUiAndShowPanel()` (`App.swift:353-369`) — updates Appearance, swaps
  the background effect view, refreshes UI, calls `TilesPanel.shared.show()`,
  previews the selected window, kicks off thumbnail capture.
- `App.refreshUi(preserveScrollPosition)` (`App.swift:293-305`) — the in-session
  redraw: `Windows.updateSelectedWindow()` → `TilesPanel.updateContents(...)` →
  VoiceOver → `WindowThumbnails.previewSelectedIfNeeded()` →
  `Applications.refreshBadgesAsync()`. Heavily guarded by
  `SwitcherSession.isActive` between each step (race-safety).
- `App.refreshOpenUiAfterExternalEvent(...)` (`App.swift:284-291`) — throttled
  redraw triggered by AX events (window created/moved/focused/destroyed).
- `App.hideUi(keepPreview)` (`App.swift:63-79`) — tears down the session:
  `SwitcherSession.current = nil`, `UsageStats.resetSession()`, end search,
  toggle context-menu/cursor/trackpad event handling off, order the panel out,
  and **notify the scheduler** via
  `ProTransitionManager.shared.onSwitcherDismissed()` (`App.swift:78`, see §6).

### 2.4 `SwitcherSession` — per-invocation state

`SwitcherSession` (`src/switcher/SwitcherSession.swift`) holds everything scoped
to one show: `shortcutIndex`, `isFirstSummon`, `forceDoNothingOnRelease`,
`selectedIndex`, `hoveredIndex`, `selectedTarget` (window id for stable
re-selection), `searchQuery`. `SwitcherSession.current != nil` is the canonical
"panel is conceptually shown" flag (`isActive`, `:11`).
`SwitcherSession.activeShortcutIndex` (`:14`) is read by essentially every
per-shortcut effective-preference lookup in the UI.

---

## 3. Cycling, selection, hover, and focus

### 3.1 Selection state

Selection is stored on `SwitcherSession` (`selectedIndex`, `hoveredIndex`,
`selectedTarget`). The canonical list `Windows.list` is index-aligned with
`TilesView.recycledViews`.

### 3.2 Selection decisions (pure kernel)

`SelectionResolver` (`src/switcher/state/SelectionResolver.swift`) is a pure,
unit-tested kernel. `Windows` projects `list` into `[SelectionWindow]`
(`Windows.selectionSnapshot`, `Windows.swift:185-193`), builds `SelectionInputs`
(`makeSelectionInputs`, `:195-204`), and:

- On show: `setInitialSelectedAndHoveredWindowIndex()` (`Windows.swift:163-172`)
  → `SelectionResolver.initialPickIndex(...)`.
- On every refresh: `updateSelectedWindow()` (`Windows.swift:174-182`) →
  `SelectionResolver.decide(...)` → `applySelectionDecision(...)` (`:206-223`).

`makeSelectionInputs` reads `Preferences.windowOrder[shortcutIndex]` to set
`useLastFocusedRule` (`Windows.swift:200-201`).

### 3.3 Cycling

- `App.cycleSelection(direction, allowWrap)` (`App.swift:248-256`) dispatches:
  up/down → `TilesView.navigateUpOrDown(...)`; left/right →
  `Windows.cycleSelectedWindowIndex(step, allowWrap)`.
- `Windows.cycleSelectedWindowIndex` (`Windows.swift:272-284`) and
  `selectedWindowIndexAfterCycling` (`:286-297`) skip non-displayed windows and
  handle wrap-around suppression on key-repeat.
- `TilesView.navigateUpOrDown` (`TilesView.swift:367-384`) and `nextRow`
  (`:341-365`) handle row-based vertical navigation, respecting RTL layout.
- `updateSelectedAndHoveredWindowIndex(newIndex, fromMouse)`
  (`Windows.swift:238-270`) is the single mutation point. It distinguishes hover
  (mouse) from focus (keyboard or mouse-with-`mouseHoverEnabled`), updates the
  highlight (`TilesView.highlight`), scrolls the focused tile into view, triggers
  the window preview (`WindowThumbnails.previewSelectedIfNeeded()`), and notifies
  VoiceOver. Mouse hover honors `Preferences.mouseHoverEnabled` (`:255`).

### 3.4 Highlight rendering

`TilesView.highlight(index)` (`TilesView.swift:324-339`) draws the per-tile
highlight and updates `TileUnderLayer` with the focused and (distinct) hovered
tile frames.

### 3.5 Focus / activation

When the user commits (key-up in focus-on-release, or the focus shortcut):

- `App.focusTarget()` (`App.swift:96-101`) → `App.focusSelectedWindow(...)`
  (`:263-275`) → `Window.focus()` (`Window.swift:245-275`).
- `Window.focus()` handles three cases: AltTab's own windows, windowless apps
  (launch/activate), and normal windows (private SkyLight
  `_SLPSSetFrontProcessWithOptions` + `makeKeyWindow` byte-poking ported from
  Hammerspoon, `Window.swift:277-288`, then `axUiElement.focusWindow()`).
- Optional cursor-follows-focus via `App.moveCursorToSelectedWindow`
  (`App.swift:277-282`), gated on `Preferences.cursorFollowFocus`.

Window-management actions on the selected window are wired in `ShortcutActions`
(`src/switcher/ShortcutAction.swift:28-32`): `close()`, `minDemin()`,
`toggleFullscreen()`, `application.quit()`, `application.hideOrShow()` (all in
`Window.swift`/`Application.swift`). None of these are paywalled.

---

## 4. Keyboard / shortcut event flow

### 4.1 Registration

`KeyboardEvents` (`src/events/KeyboardEvents.swift`) installs:

- **Carbon global hotkeys** (`RegisterEventHotKey`) for the `nextWindowShortcut*`
  and `holdShortcut*` slots (`:104-120`, IDs from
  `KeyboardEventsTestable.globalShortcutsIds`,
  `src/events/KeyboardEventsTestable.swift:4-9`).
- A **local NSEvent monitor** for keyDown/keyUp (`:123-130`).
- A **CGEvent tap** on `.cghidEventTap` for `.flagsChanged` and `.keyDown`
  (`:132-152`). The `.keyDown` path only absorbs **Esc** (and only when a
  shortcut binds Esc and the switcher is active) to beat the macOS 26 Game
  Overlay hook on `⌘⎋` (`:33-44`, `anyShortcutUsesEscape` at `:20`).

Registration is driven from `ControlsTab`
(`src/preferences/.../ControlsTab.swift:781` calls
`KeyboardEvents.addGlobalShortcut`). `addEventHandlers()` is called once at
startup (`App.swift:402`).

### 4.2 Matching and dispatch

All paths funnel into `handleKeyboardEvent(...)`
(`src/events/KeyboardEventsTestable.swift:13-24`):

1. If the search field is being edited and the panel is key, the keyDown is first
   offered to `TilesView.handleSearchEditingKeyDown` (`:14-19`).
2. `triggerMatchingShortcuts(...)` (`:49-66`) iterates `ControlsTab.shortcuts`,
   and for each `ATShortcut` calls `matches(...)` then `shouldTrigger()`, and if
   both pass, `executeAction(isARepeat)`.

`ATShortcut` (`src/switcher/ATShortcut.swift`) encapsulates one bound shortcut:
`matches(...)` (`:21-41`) does global-id and modifier/keycode matching;
`modifiersMatch(...)` (`:43-61`) handles the hold-modifier semantics and the
"base key without hold modifiers when panel open" case;
`shouldTrigger()` (`:63-80`) gates by scope (global/local), trigger phase
(down/up), session shortcut index, and — for the key-up path —
`Preferences.effectiveShortcutStyle(...) == .focusOnRelease`;
`redundantSafetyMeasures()` (`:90-110`) is a safety net for dropped/out-of-order
key-up events.

### 4.3 Actions

`ShortcutActions.execute(id)` (`src/switcher/ShortcutAction.swift:49-70`) maps an
id to behavior:

- A static table `ShortcutActions.all` (`:9-41`) maps named ids to closures
  (`focusWindowShortcut`, `previousWindowShortcut`, arrow/vim cycling,
  `cancelShortcut`, `closeWindowShortcut`, `minDeminWindowShortcut`,
  `toggleFullscreenWindowShortcut`, `quitAppShortcut`, `hideShowAppShortcut`,
  `searchShortcut`, `lockSearchShortcut`).
- Prefix-matched ids: `holdShortcut*` → `App.focusTarget()`;
  `nextWindowShortcut*` → `App.showUiOrCycleSelection(index, false)`.
- **A Pro gate is applied at the top** for `holdShortcut`/`nextWindowShortcut`
  slots with index ≥ 1 (`ShortcutAction.swift:50-58`, see §6).

### 4.4 Key repeat

`KeyRepeatTimer` (`src/switcher/KeyRepeatTimer.swift`) implements artificial
key-repeat for next/previous-window cycling when the bound shortcut has no
keycode (modifier-only). It reads the system `KeyRepeat`/`InitialKeyRepeat`
defaults (`:41-42`) and polls hardware modifier state to detect release
(`holdModifierIsReleased`, `:62-70`). No paywall coupling.

### 4.5 Other event monitors (`src/events/`)

- `CursorEvents` (`src/events/CursorEvents.swift`) — `.cgSessionEventTap` for
  mouse down/up/moved; handles click-to-focus, click-outside-to-dismiss
  (`:88`), middle-click-to-close (`:120-129`), and hover with a "deadzone" to
  ignore tiny trackpad jitter (`:178-189`). Toggled on/off with the session.
- `ScrollwheelEvents` (`src/events/ScrollwheelEvents.swift`) — blocks continuous
  (trackpad) scroll while letting discrete (mouse) scroll through.
- `TrackpadEvents` (`src/events/TrackpadEvents.swift`) — gesture-based cycling.
- `ContextMenuEvents` (`:ContextMenuEvents.swift`) — right-click menu on tiles.
- Plus environment monitors that trigger refreshes: `SpacesEvents`,
  `ScreensEvents`, `DockEvents`, `SleepWakeEvents`, `InputSourceEvents`,
  `SystemAppearanceEvents`, `SystemScrollerStyleEvents`,
  `RunningApplicationsEvents`, `WindowCaptureEvents` (thumbnail capture),
  `PreferencesEvents`, `UserDefaultsEvents`, `CliEvents`, `AxEventRouting`.

  **`PreferencesEvents`** contains one paywall touchpoint
  (`src/events/PreferencesEvents.swift:62`, see §6).

---

## 5. Search

Search is a first-class part of the switcher UI and is **Pro-gated** (see §6).

- `Search` (`src/switcher/Search.swift`) computes per-window match/relevance
  using the `SearchTestable` fuzzy matcher, caching results on the `Window`
  (`swBestSimilarity`, `lastSearchQuery`).
- `Windows.updateSearchQuery(...)` (`Windows.swift:14-35`) updates the session
  query and the "select best match / restore default" flags, then re-sorts.
- `Windows.shouldDisplay(window)` (`Windows.swift:10-12`) is
  `shouldShowTheUser && Search.matches(window, query)`. This single predicate is
  consulted everywhere (layout, cycling, selection snapshot, viewport).
- `SearchModeResolver` (`src/switcher/state/SearchModeResolver.swift`) is the pure
  search-mode state machine (`off`/`editing`/`locked`). Its `enableEditing` and
  `lock` decisions take a `canSearch` / `canLockSearch` `Bool`; the caller
  (`TilesView`) computes that bool from `ProFeature.*.attemptUse()` (`:68-86`).
- `TilesView` translates those decisions into AppKit side effects
  (`enableSearchEditing`, `lockSearchMode`, `disableSearchMode`,
  `TilesView.swift:59-128`).
- Sorting respects per-shortcut order/group preferences via `WindowOrderResolver`
  (`src/switcher/state/WindowOrderResolver.swift`, `OrderSortType` =
  `recentlyFocused`/`recentlyCreated`/`alphabetical`/`space`) and search
  relevance (`Windows.sort`, `Windows.swift:322-343`).

---

## 6. Pro / paywall touchpoints surfacing in this subsystem

The switcher subsystem itself is mostly free of paywall logic — the gating lives
in `src/pro/` (`ProFeature`, `ProTransitionManager`, `LicenseManager`,
`ProGatedPreferences`) — but it is *invoked* from a small number of well-defined
sites in scope. The pattern is consistent: pure kernels never gate; the
imperative wrapper calls `ProFeature.<case>.attemptUse()` (or reads an
"effective" preference that silently downgrades when Pro is locked) at the real
use moment.

`ProFeature.attemptUse()` (`src/pro/ProFeature.swift:74-83`) returns `true` when
Pro/trial is available or a "free pass session" is active; otherwise it consults
the Day1→Day35 nag ladder for hard-gated features. For a fully-free build, every
one of these should resolve to "always allowed."

### Hard gates invoked from the switcher

1. **Extra shortcut slots (index ≥ 1)** — `ShortcutAction.swift:50-58`
   (`ShortcutActions.execute`): pressing any `holdShortcut`/`nextWindowShortcut`
   slot past the first calls `ProFeature.extraShortcut(index:).attemptUse()` and
   `return`s (does nothing) if denied. Removing this gate makes all configured
   shortcut variants always work.

2. **Search in the switcher** — `TilesView.swift:92`
   (`enableSearchEditing`): `ProFeature.searchInSwitcher.attemptUse()` is passed
   as `canSearch` to `SearchModeResolver.enableEditing`. If denied, the kernel
   returns `.proGateBlocked(.search)` and editing never starts.

3. **Lock search results** — `TilesView.swift:79` (`lockSearchMode`):
   `ProFeature.lockSearchInSwitcher.attemptUse()` passed as `canLockSearch` to
   `SearchModeResolver.lock`.

### Degradable preferences read via "effective" getters

These do not call `attemptUse()` directly; instead the switcher reads
`Preferences.effective*` getters, and the *stored* value is silently downgraded
when Pro is locked (via `ProGatedPreferences`). The switcher consumes them at:

4. **Appearance style** (`appIcons`/`titles` are Pro;
   `ProFeature.appIconsAndTitlesStyle`) — read via
   `Preferences.effectiveAppearanceStyle(...)`. Surfaces in the switcher at, e.g.,
   `TilesView.swift:388, 563, 614`, `TilesPanel.swift:101, 128`,
   `TileView.swift:52, 64, 82`. The Pro-aware read path for index 0 is
   `ProGatedPreferences.appearanceStyleOverride0.read()`
   (`Preferences.swift:311-315`).

5. **Auto size** (`ProFeature.autoSize`) — read via
   `Preferences.effectiveAppearanceSize(...)` at `TilesView.swift:388, 391`
   (and `TilesPanel`/`Appearance`). Pro-aware read at
   `Preferences.swift:317-321`.

6. **Search-on-release shortcut style** (`ProFeature.searchOnReleaseShortcut`) —
   read via `Preferences.effectiveShortcutStyle(...)` at `ATShortcut.swift:70,
   96`, `App.swift:329`, `ShortcutAction.swift:22`. Pro-aware read at
   `Preferences.swift:328-332`. (`focusOnRelease` itself is free; the
   `searchOnRelease` value is the Pro one.)

### Preview selected window

7. **`PreviewPanel`** (`src/switcher/PreviewPanel.swift`) and
   `WindowThumbnails.previewSelectedIfNeeded()`
   (`src/switcher/state/WindowThumbnails.swift:6-19`) implement the "preview the
   selected window full-size" feature, driven by
   `Preferences.effectivePreviewSelectedWindow(...)`
   (`Preferences.swift:334-337`). **As written, this preference is NOT in
   `ProFeature` / `ProGatedPreferences`** — `effectivePreviewSelectedWindow`
   reads the stored bool directly with no Pro-aware override. So in the current
   code preview-selected-window is effectively a free feature gated only by the
   Screen-Recording permission. Worth confirming against `src/pro/` during
   removal, but it does not appear to need changes for a free build.

### Trial/upsell scheduler hooks

8. The switcher show/hide lifecycle notifies the trial-nag scheduler:
   `ProTransitionManager.shared.onSwitcherShown()` (`App.swift:328`) and
   `onSwitcherDismissed()` (`App.swift:78`). These are the hooks the Day1→Day35
   nag system uses to decide when to interrupt the user with upsell UI. For a free
   build these calls should be removed (or made no-ops).

### Usage analytics

9. `UsageStats.recordTrigger(...)` (`App.swift:315`) and
   `UsageStats.recordSearchIfFirst()` (`TilesView.swift:183`), reset via
   `UsageStats.resetSession()` (`App.swift:67`). `UsageStats`
   (`src/util/UsageStats.swift`) records trigger/search counts (including
   `triggersExtraShortcuts`, `triggersAppIcons`, etc.) into a private
   `UserDefaults` suite. This feeds the upsell messaging ("you used X N times").
   Not strictly a gate, but part of the paywall apparatus; safe to strip or stub
   for a free build.

> Note: `ProFeature.searchOnReleaseShortcut` is mapped to the "extra shortcuts"
> marketing copy and grouped under keyboard shortcuts
> (`ProFeature.swift:52`), which is why the trial copy lumps them together.

---

## 7. Preferences interaction summary

The switcher reads preferences in two modes:

- **Per-shortcut "effective" reads**, keyed on
  `SwitcherSession.activeShortcutIndex`. These are the ones that can be Pro-gated:
  `effectiveAppearanceStyle`, `effectiveAppearanceSize`, `effectiveShortcutStyle`,
  `effectivePreviewSelectedWindow`, `effectiveAppearanceTheme`
  (`Preferences.swift:311-337`). Window-filter preferences are snapshotted once per
  show in `WindowFilters.snapshot()` (`Windows.swift:507-519`) for performance.
- **Plain reads** scattered throughout: `Preferences.onlyShowMainWindows()`,
  `windowOrder`, `mouseHoverEnabled`, `cursorFollowFocus`, `windowDisplayDelay`,
  `fadeOutAnimation`, `previewFadeInAnimation`, `captureWindowsInBackground`, the
  `exceptions` list (consumed by `ExceptionMatcher`), etc.

`Appearance` (`src/switcher/Appearance.swift`) centralizes all derived layout
constants (paddings, font, theme, max-width-on-screen) and is recomputed via
`Appearance.update()` on each show.

---

## 8. Removal notes for a clean free build

To free everything in this subsystem without breaking the build, the cleanest
approach is to make the gates at the call sites always pass rather than ripping
`src/pro/` out from under the switcher first:

- **Make `ProFeature.attemptUse()` always return `true`.** This single change
  neutralizes the three hard gates invoked from scope
  (`ShortcutAction.swift:56`, `TilesView.swift:79, 92`) with no signature changes.
- **Make the `Preferences.effective*` getters read the raw stored value** (i.e.
  bypass `ProGatedPreferences.*Override0.read()` downgrades at
  `Preferences.swift:313, 319, 330`) so `appIcons`/`titles`/`auto`/`searchOnRelease`
  are honored regardless of license state. Equivalently, make
  `ProGatedPreferences.read()` return the stored Pro value unconditionally.
- **Stub `ProTransitionManager.shared.onSwitcherShown()` /
  `onSwitcherDismissed()`** (`App.swift:78, 328`) to no-ops, or delete the calls,
  to kill the trial-nag interrupts triggered by the switcher lifecycle.
- **`UsageStats` calls** (`App.swift:67, 315`; `TilesView.swift:183`) can be left
  (harmless) or stubbed; they only feed upsell copy.
- **`PreviewPanel` / preview-selected-window needs no change** for the free build
  per current code (not actually Pro-gated; see §6.7) — but verify against
  `src/pro/` in the licensing-focused audit section.

Risks / things to verify in the dedicated `src/pro/` audit:
- `SearchModeResolver` and `SelectionResolver` are pure and have unit tests; do
  **not** move gating into them — keep gates at the `TilesView`/`ShortcutAction`
  call sites so the kernels' tests stay valid.
- Removing `ProTransitionManager`/`LicenseManager` types outright will break these
  call sites at compile time; either keep thin stubs or update all call sites in
  the same change. The keyboard/selection/render paths have no other Pro coupling,
  so once the four/five sites above are neutralized the switcher is fully free.
- `ProFeatureCopy` / marketing strings are referenced only by `src/pro/` UI, not by
  the switcher, so they are out of scope here.
