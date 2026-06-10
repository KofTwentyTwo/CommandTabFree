# 03 — Preferences System & Feature-Gating Mechanism

Audit scope: the preferences system (`src/preferences/`) and the Pro feature-gating mechanism
that sits on top of it. This is the heart of how the paywall degrades and hides features. This
document is the authoritative reference for the removal plan; every gated preference is enumerated
with its exact key, Pro values, and free equivalent.

---

## 1. How the preferences system works (no-paywall baseline)

### 1.1 Storage and defaults

- `Preferences.defaultValues` (`src/preferences/Preferences.swift:6-78`) is the single dictionary of
  every default, registered into `UserDefaults.standard` via `registerDefaults()`
  (`Preferences.swift:179-181`). All values are stored as **strings** (e.g. `"true"`, `"100"`, or a
  stringified enum index like `AppearanceStylePreference.thumbnails.indexAsString`).
- Macro (enum-backed) preferences store the **enum case index** as a string. The index is derived by
  the `CaseIterable where Self: Equatable` extension `index` / `indexAsString`
  (`src/macos/api-wrappers/HelperExtensions.swift:330-337`).
- Reads go through `CachedUserDefaults` (`Preferences.swift:432-523`), a thread-safe cache keyed by
  preference name. `macroPref(key, allCases)` reads the stored int and maps it to `allCases[index]`,
  resetting to the default if the value can't be parsed (`getThenConvertOrReset`, lines 503-518).
- Writes go through `Preferences.set` / `setShortcut` / `remove` (`Preferences.swift:191-228`). Each
  write invalidates the cache and, unless `notify: false` is passed, fires
  `PreferencesEvents.preferenceChanged(key)` (`Preferences.swift:216-218`). **This notify hook is the
  single chokepoint the paywall hijacks to bounce setters to the Upgrade tab — see §3.2.**

### 1.2 Per-shortcut model and overrides

- Most behavioral prefs are per-shortcut, indexed by `indexToName(baseName, index)`
  (`Preferences.swift:421-423`): index 0 has no suffix (`appearanceSizeOverride`), index 1 gets
  suffix `2` (`appearanceSizeOverride2`), etc. (`nameToIndex` is the inverse, lines 425-429.)
- `maxShortcutCount = 9`, `minShortcutCount = 1` (`Preferences.swift:160-161`). `shortcutCount`
  clamps the stored count into that range (lines 162-164).
- Appearance **overrides** let any shortcut deviate from the global appearance. The 5 override base
  names are `appearanceStyleOverride`, `appearanceSizeOverride`, `appearanceThemeOverride`,
  `shortcutStyleOverride`, `previewFocusedWindowOverride` (`Preferences.swift:258-261`), each mapped
  back to its global key by `overrideToGlobalKey` (lines 264-270).
- `hasOverride(baseName, index)` (lines 275-277) consults `Preferences.all` (the cached
  `persistentDomain` snapshot, lines 238-244), which **excludes registered defaults**. So an
  untouched override reports `false` even though its key has a registered default. The override
  defaults are deliberately set to the **free-tier value** (`Preferences.swift:67-75`) so that
  `snapshotAndDowngrade` is a no-op for unset overrides.
- `effectiveAppearanceStyle/Size/Theme/ShortcutStyle/PreviewSelectedWindow(index)` (lines 311-337)
  resolve the value a given shortcut actually uses: the override if set, else the global. **For
  index 0, the three Pro-gated overrides route through `ProGatedPreferences.*Override0.read()`**
  (lines 313, 319, 330) — meaning index-0 overrides are degraded exactly like the globals.

### 1.3 Migrations

`PreferencesMigrations` (`src/preferences/PreferencesMigrations.swift`) runs once per version bump on
launch via `Preferences.initialize()` (`Preferences.swift:168-172`). It is largely paywall-agnostic
historical data migration. **The only paywall coupling** is one line in `migratePreferences()`:

- `PreferencesMigrations.swift:20` — `ProTransitionState.markFreshInstallIfUnknown(existingVersion == nil)`.
  This is the *only* place that can still observe a nil `preferencesVersion`, so it persists the
  fresh-install signal the trial scheduler later reads. For a free build this single call must be
  removed along with `ProTransitionState`.

No other migration references Pro/license/trial state.

---

## 2. The Pro-gating mechanism (the heart of the paywall)

The gating mechanism has two complementary halves:

1. **Degradable preferences** — stored values that get *silently downgraded* to a free equivalent
   when Pro locks, snapshotted for later restore, and *intercepted at write-time* in Settings.
2. **Hard-gated runtime actions** — features with no stored preference, gated at use-time (extra
   shortcuts, in-switcher search, lock-search).

### 2.1 `isProLocked` — the master gate

`LicenseManager.shared.isProLocked` (`src/pro/license/LicenseManager.swift:67-72`) is the single
boolean every gate consults:

```swift
var isProLocked: Bool {
    switch state {
    case .pro, .trial: return false
    case .proExpired, .trialExpired: return true
    }
}
```

So a user is "locked" once the 14-day trial (`trialDuration = 14`, line 17) expires or a Pro license
becomes invalid. `isProAvailable` is the inverse-ish (`pro` or `trial`).

For a fully-free build, the cleanest semantic equivalent is **`isProLocked == false` always** (and
`isProAvailable == true` always). Every gate below then becomes a no-op pass-through.

### 2.2 The `PreferenceDefinition` / `PreferenceGate` engine

`src/preferences/PreferenceDefinition.swift` is the single source of truth for degradable prefs.

- `PreferenceGate<T>` (lines 7-11) holds three things:
  - `freeEquivalent: T` — the value returned/written when locked.
  - `rememberedKey: String` — the `ProTransitionState` key under which the original Pro index is
    snapshotted for restore + "ghost UI".
  - `isProValue: (T) -> Bool` — predicate identifying which stored values count as "Pro".
- `PreferenceDefinition<T>` (lines 18-74) wraps `key`, `default`, and an optional `gate`, and exposes
  the read/downgrade/restore operations:
  - **`read()`** (lines 32-44): the hot-path getter. If there's no gate or `!isProLocked`, returns
    the stored value verbatim. When **locked**, three branches:
    1. If a **free-pass session** is active and a remembered Pro index exists → returns the
       remembered Pro value (so the switcher renders the user's Pro choice "one last time").
    2. Else if the stored value is still a Pro value (transient, before
       `onProLockEngaged()` has downgraded it) → returns `freeEquivalent`.
    3. Else → returns stored (already downgraded).
  - **`snapshotAndDowngrade()`** (lines 51-57): if stored is a Pro value, overwrites it with
    `freeEquivalent` via `Preferences.set` (which **fires the notify hook**), and returns the
    original index for the caller to remember. No-op if no gate or already free.
  - **`restore(from:)`** (lines 62-65): writes the remembered index back with `notify: false`.
  - **`isStoredValuePro()`** (lines 69-73): true iff stored is currently a Pro value, regardless of
    lock state — used by the notify hook (§3.2).
- `AnyProGatedPreference` (lines 79-85) is the type-erased view (Int/Bool returns only) that the
  lock/unlock passes iterate over. `PreferenceDefinition.erased` (lines 87-96) produces it.

### 2.3 `ProGatedPreferences` — the registry of gated prefs

`ProGatedPreferences` (`PreferenceDefinition.swift:102-170`) declares **six** gated
`PreferenceDefinition`s (3 globals + 3 index-0 overrides). `ProGatedPreferences.all` (lines 157-164)
is the list iterated on lock/unlock. `forPreferenceKey(_:)` (lines 167-169) is the lookup the notify
hook uses. **This enum is the precise enumeration source for the table in §4.**

### 2.4 `ProFeature` — capability registry

`src/pro/ProFeature.swift` enumerates every gated capability (degradable + hard-gated):

- Cases (lines 9-16): `.appIconsAndTitlesStyle`, `.autoSize`, `.searchOnReleaseShortcut`
  (degradable) and `.extraShortcut(index:)`, `.searchInSwitcher`, `.lockSearchInSwitcher`
  (hard-gated).
- `gateKind` (lines 27-33): `.degradable`, `.hardGated`, or `.degradableAndHardGated`.
- `gatedPreference` (lines 37-44): maps the 3 degradable features to their
  `ProGatedPreferences.*.erased` definition.
- `attemptUse()` (lines 74-83): the runtime gate. Returns `true` if `isProAvailable` or a free-pass
  session is active; otherwise hard-gated features defer to
  `ProTransitionManager.attemptHardGatedFeature`, and degradable features always return `true`
  (they're gated at write-time, not use-time).
- `isStoredValuePro(preferenceKey:)` (lines 87-89): delegates to the registry; used by the notify hook.

### 2.5 Lock / unlock passes — downgrade & restore

`ProTransitionState` (`src/pro/scheduling/ProTransitionState.swift`) owns the snapshot/restore logic
and the `remembered*` indices (persisted in the `<bundleId>.license` UserDefaults suite under keys
prefixed `proTransition.`):

- **`onProLockEngaged()`** (lines 73-79): iterates `ProGatedPreferences.all`, calls
  `snapshotAndDowngrade()` on each, and stores the returned Pro index under the pref's
  `rememberedKey`. Triggered when the license locks via `ProTransitionManager.onLicenseStateChanged`
  → `onProLockEngaged` (`ProTransitionManager.swift:179-181, 259-262`), and also from the Day 15
  Full-Upgrade / Proactive paths (lines 248-249, 256). Idempotent (re-entry no-ops because stored is
  already free).
- **`onProUnlocked()`** (lines 85-92): iterates the registry, restores each remembered index via
  `restoreFromIndex` (with `notify: false`), then clears the remembered key. Triggered on activation
  via `LicenseManager.onBeforeProUnlock` (wired in `App.swift`) and `ProTransitionManager.onProUnlocked`.
- `rememberedAppearanceStyle/Size/ShortcutStyle` + the three `*Override` variants (lines 36-62) are
  typed accessors over those `proTransition.remembered*` keys.

### 2.6 Free-pass session & ghost UI

- `ProTransitionManager.isFreePassSessionActive` (`ProTransitionManager.swift:135-142`) is a
  session-only flag, true between a free-pass grant and switcher dismissal. While active,
  `PreferenceDefinition.read()` returns the **remembered Pro value** (branch 1 above), so the
  switcher shows the user's Pro selection one last time before `[C]` upsell fires. Flipping the flag
  triggers `App.resetPreferencesDependentComponents()` so `TilesView` re-renders.
- The remembered indices also drive the "ghost outline" in Settings (the Pro selection is shown
  badged/dimmed even though the live value is the free equivalent).

---

## 3. How gating reaches the UI

### 3.1 Settings controls — write-time interception + badges

`LabelAndControl.makeImageRadioButtons` (`src/preferences/settings-window/LabelAndControl.swift:74-116`)
takes a `proGatedIndices: Set<Int>` parameter. On click, **if `isProLocked` and the clicked index is
gated** (lines 86-92): it snaps the radio group back to the stored value and calls
`UpgradeTab.navigateToUpgradeTab()` instead of writing. This is the generic interception primitive.

`AppearanceTab` (`src/preferences/settings-window/tabs/appearance/AppearanceTab.swift`) wires the three
global gated controls:

- **Appearance Style** radios (lines 458-463): `proGatedIndices: proGatedAppearanceStyleIndices()`
  which is "everything but `.thumbnails`" (lines 700-703 → indices `{1, 2}` = appIcons, titles).
  `addProBadgesToStyleButtons` (lines 688-698) attaches a `ProBadgeView` to every non-thumbnails
  card.
- **Appearance Size** segmented (lines 474-490): `wrapAppearanceSizeProLockIntercept` (lines 662-679)
  intercepts the `.auto` segment (last index) when locked — snaps back to stored, calls
  `navigateToUpgradeTab()`. `addProBadgeToAutoSegment` (lines 681-686) badges the Auto segment.
- **After-keys-released / shortcutStyle** segmented (lines 566-583):
  `wrapShortcutStyleProLockIntercept` (lines 585-598) intercepts the `.searchOnRelease` segment.
  `addProBadgeToShortcutStyleSegment` (lines 606-611) badges the Search segment.
- `refreshProLockUi()` (lines 705+) re-syncs these three controls when
  `ProTransitionManager.proLockStateDidChangeNotification` fires (observer registered lines 414-419),
  so the live Settings window updates on lock/unlock without a reopen.

The per-shortcut override panes mirror this exactly in `ShortcutEditor.swift`
(`src/preferences/settings-window/tabs/controls/ShortcutEditor.swift`):

- `ShortcutOverrideSegmented` / `ShortcutOverrideRadios` carry their own `proGatedIndices` (lines
  540, 648). The override `AppearancePane` (lines 425-465) gates: style → `{appIcons, titles}` (line
  429), size → `{.auto}` (line 437), theme → `[]` (line 449, **not gated**), shortcutStyle →
  `{.searchOnRelease}` (line 459). Preview toggle is **not** gated.
- The write-time intercept lives in `handleClick` for both controls (lines 596-621 for segmented,
  702-717 for radios): if a gated index is clicked while locked, snap back + `navigateToUpgradeTab()`.

### 3.2 The notify-hook bounce (write-side enforcement)

`PreferencesEvents.preferenceChanged(_:)` (`src/events/PreferencesEvents.swift:53-75`) contains the
critical line **62-64**:

```swift
if LicenseManager.shared.isProLocked && ProFeature.isStoredValuePro(preferenceKey: key) {
    UpgradeTab.navigateToUpgradeTab()
}
```

Any write that lands a Pro value into a gated key while locked bounces the user to Upgrade. This is
why `onProUnlocked` restores with `notify: false` (otherwise restoring a Pro value during a
still-locked window would yank the user to Upgrade). For the free build, removing this branch is
mandatory.

### 3.3 Extra-shortcut sidebar gating (`ControlsTab`)

- `ControlsTab` badges every shortcut row at index ≥ 1 as Pro (`row.setProBadge(index >= 1)`,
  `src/preferences/settings-window/tabs/controls/ControlsTab.swift:515`).
- `addShortcutSlot()` (lines 586-598): if `currentCount >= 1 && isProLocked`, it refuses to add the
  slot and calls `navigateToUpgradeTab()` (lines 589-592). **So free users are hard-capped at exactly
  1 shortcut.**

### 3.4 Runtime hard-gates (switcher)

- Extra shortcut trigger: `ShortcutAction.swift:56` — `if !ProFeature.extraShortcut(index: index).attemptUse() { return }`.
- In-switcher search: `TilesView.swift:92` gates editing on `ProFeature.searchInSwitcher.attemptUse()`.
- Lock-search: `TilesView.swift:79` gates on `ProFeature.lockSearchInSwitcher.attemptUse()`.
- `searchInSwitcher` / `lockSearchInSwitcher` map to copy "Search"; `searchOnReleaseShortcut` is the
  Settings-side degradable twin of the same capability.

---

## 4. ENUMERATION — every Pro-gated preference (exact)

There are **6 degradable preference definitions** (3 globals + 3 index-0 overrides) plus runtime
hard-gates with no backing preference. Indices below are the `CaseIterable` order (and thus the
stored string value).

### 4.1 Degradable preferences (downgraded on lock, snapshot/restore)

Source: `ProGatedPreferences` (`PreferenceDefinition.swift:103-153`).

| # | Preference key | Type / enum | `isProValue` (Pro values) | Pro index value(s) | Free equivalent (value written on lock) | Free index | rememberedKey | Default |
|---|----------------|-------------|---------------------------|--------------------|------------------------------------------|-----------|---------------|---------|
| 1 | `appearanceStyle` | `AppearanceStylePreference` | `$0 != .thumbnails` | `.appIcons` (1), `.titles` (2) | `.thumbnails` | 0 | `rememberedAppearanceStyle` | `.thumbnails` |
| 2 | `appearanceSize` | `AppearanceSizePreference` | `$0 == .auto` | `.auto` (3) | `.medium` | 1 | `rememberedAppearanceSize` | `.auto` |
| 3 | `shortcutStyle` | `ShortcutStylePreference` | `$0 == .searchOnRelease` | `.searchOnRelease` (2) | `.doNothingOnRelease` | 1 | `rememberedShortcutStyle` | `.focusOnRelease` |
| 4 | `appearanceStyleOverride` (shortcut 0 only) | `AppearanceStylePreference` | `$0 != .thumbnails` | `.appIcons` (1), `.titles` (2) | `.thumbnails` | 0 | `rememberedAppearanceStyleOverride` | `.thumbnails` |
| 5 | `appearanceSizeOverride` (shortcut 0 only) | `AppearanceSizePreference` | `$0 == .auto` | `.auto` (3) | `.medium` | 1 | `rememberedAppearanceSizeOverride` | `.medium` |
| 6 | `shortcutStyleOverride` (shortcut 0 only) | `ShortcutStylePreference` | `$0 == .searchOnRelease` | `.searchOnRelease` (2) | `.doNothingOnRelease` | 1 | `rememberedShortcutStyleOverride` | `.doNothingOnRelease` |

Notes:
- Enum orders: `AppearanceStylePreference = [thumbnails(0), appIcons(1), titles(2)]`
  (`MacroPreferences.swift:284-287`); `AppearanceSizePreference = [small(0), medium(1), large(2),
  auto(3)]` (lines 308-312); `ShortcutStylePreference = [focusOnRelease(0), doNothingOnRelease(1),
  searchOnRelease(2)]` (lines 100-103).
- **Note the asymmetry for `appearanceSize`/`shortcutStyle`**: the *registered default* is the Pro
  value (`.auto` / `.focusOnRelease` for the global), but the *free equivalent written on lock* is
  `.medium` / `.doNothingOnRelease`. (For `appearanceStyle` the default `.thumbnails` is already
  free.) Override-key defaults are intentionally the **free** value so unset overrides never get
  snapshotted (`Preferences.swift:67-75`, `PreferenceDefinition.swift:130-153`).
- Index-0 overrides (4-6) are the only override indices snapshotted, because indices ≥ 1 are
  unreachable while locked (extra shortcuts are hard-gated). `Preferences.removeOverride` also clears
  the matching remembered key for these three (`Preferences.swift:282-298`).
- The corresponding index-1..8 override keys (`appearanceStyleOverride2..9`, etc.) and the two
  **non-gated** overrides (`appearanceThemeOverride`, `previewFocusedWindowOverride`) are NOT gated.

### 4.2 Hard-gated runtime features (no backing preference)

Source: `ProFeature` (`ProFeature.swift:13-16`), enforcement sites in §3.3–3.4.

| Feature | Gate kind | Enforcement | Free-tier effect when locked |
|---------|-----------|-------------|------------------------------|
| Extra shortcuts (`shortcutCount` > 1, slots index ≥ 1) | hardGated | `ControlsTab.addShortcutSlot` (ControlsTab.swift:589-592) + `ShortcutAction.swift:56` | Capped at 1 shortcut; extra-shortcut chord no-ops |
| In-switcher search (`searchInSwitcher`) | hardGated | `TilesView.swift:92` via `attemptUse()` | Typing-to-search disabled in switcher |
| Lock-search (`lockSearchInSwitcher`) | hardGated | `TilesView.swift:79` via `attemptUse()` | Lock-search disabled |

`searchOnReleaseShortcut` is `degradableAndHardGated` (`ProFeature.swift:30`): it is the
Settings-side degradable form (#3/#6 above) **and** its first post-expiration switcher summon can
trigger the `[C]` upsell.

---

## 5. What must change for a clean free build

The intent is: **all features unlocked, all paywall/trial/license/upsell removed**, without breaking
the build. The preferences subsystem must keep working; only the gating layered on top is removed.

### 5.1 Minimal, low-risk approach (recommended first pass)

Neuter the master gate so every check becomes a pass-through, leaving the preferences plumbing intact:

- Make `LicenseManager.shared.isProLocked` always return `false` and `isProAvailable` always `true`.
  Every Settings intercept, the notify-hook bounce, the sidebar shortcut cap, and `attemptUse()`
  immediately become no-ops, and `PreferenceDefinition.read()` returns stored values verbatim.
- This is the smallest change that unlocks everything. Downside: dead paywall code (badges,
  `ProTransitionState`, Day-X UI, `UpgradeTab`) remains compiled in.

### 5.2 Full removal (the actual goal — requires care)

Touchpoints that must be removed/rewritten in this scope:

1. **`PreferenceDefinition.swift` (entire file)** — `PreferenceGate`, `PreferenceDefinition`,
   `AnyProGatedPreference`, `ProGatedPreferences`. The getters in `Preferences.swift` that call
   `ProGatedPreferences.*.read()` (lines 129, 130, 155) and the index-0 override branches in
   `effectiveAppearanceStyle/Size/ShortcutStyle` (lines 313, 319, 330) must be rewritten to read
   the raw value directly, e.g. `CachedUserDefaults.macroPref("appearanceStyle", AppearanceStylePreference.allCases)`.
2. **`PreferencesEvents.swift:62-64`** — delete the `isProLocked && isStoredValuePro` bounce block
   (and the `ProFeature` import dependency it implies).
3. **`Preferences.swift`** — remove `overrideRememberedKey` (lines 291-298) and the
   `ProTransitionState.setInt(...)` cleanup inside `removeOverride` (lines 284-286).
4. **`PreferencesMigrations.swift:20`** — remove the
   `ProTransitionState.markFreshInstallIfUnknown(...)` call.
5. **`LabelAndControl.swift:74-116`** — drop the `proGatedIndices` parameter and the
   `isProLocked && proGatedIndices.contains(index)` intercept (lines 86-92).
6. **`AppearanceTab.swift`** — remove `proGatedAppearanceStyleIndices`, all `ProBadgeView` attach
   calls, both `wrap*ProLockIntercept` methods, `refreshProLockUi` and its
   `proLockStateDidChangeNotification` observer, and the `autoSegment/shortcutStyleSegment` overlay
   refs.
7. **`ShortcutEditor.swift`** — drop `proGatedIndices`/`attachBadge`/`refreshBadge` plumbing and the
   locked-intercept branches in both `ShortcutOverrideSegmented.handleClick` (lines 599-607) and
   `ShortcutOverrideRadios.handleClick` (lines 705-711).
8. **`ControlsTab.swift`** — remove `row.setProBadge(index >= 1)` (line 515) and the
   `isProLocked` cap in `addShortcutSlot` (lines 589-592), plus the
   `proLockStateDidChangeNotification` observer (line 141).
9. **Switcher hard-gates** (out of strict scope but coupled) — `ShortcutAction.swift:56`,
   `TilesView.swift:79,92` call `ProFeature.*.attemptUse()`; these calls must be removed or replaced
   with `true`.
10. The defaults in `Preferences.defaultValues` need no value change to unlock features (defaults
    already include the Pro values, e.g. `appearanceSize = .auto`), but the **override defaults**
    that were deliberately set to the free value (`appearanceSizeOverride = .medium`,
    `shortcutStyleOverride = .doNothingOnRelease`, `Preferences.swift:72,74`) can stay as-is — they
    only mattered for the snapshot no-op trick, which is being removed.

### 5.3 Risks / gotchas

- **`index`/`indexAsString`/`macroPref` cache plumbing is paywall-independent** and must be
  preserved — it is core preferences infrastructure, not paywall code.
- **Already-locked users have downgraded stored values.** A user who ran the paywalled build past
  trial expiry has `appearanceStyle`/`appearanceSize`/`shortcutStyle` already overwritten to free
  equivalents in UserDefaults, with the original Pro index sitting in the `proTransition.remembered*`
  keys (in the `<bundleId>.license` suite). After removal, `read()` no longer restores those — the
  user keeps the free value and silently loses their old Pro selection. A free build with a **new
  bundle ID** (per AGENTS.md, identity is coupled to the signature) gets a clean UserDefaults domain,
  so this only affects in-place upgrades of the same bundle ID. Consider a one-time migration that
  copies any `proTransition.remembered*` index back into its base key before deleting the
  `proTransition.*` state — otherwise it's a silent (minor) data loss.
- **`screenRecordingDependentFeatures`** (`Preferences.swift:346-355`) iterates
  `effectiveAppearanceStyle`/`effectivePreviewSelectedWindow` across all shortcuts; once those stop
  routing through `read()`, behavior is unchanged but verify the permission callout still resolves
  correctly when more than 1 shortcut is now reachable.
- Removing `ProGatedPreferences` will break `ProFeature.gatedPreference` and
  `ProTransitionState.remembered*` accessors (compile errors) — these live in `src/pro/` and should
  be deleted as a unit alongside the rest of the paywall (covered by the pro-subsystem audit).
- Test files reference these symbols: `PreferencesMigrationsTests.swift`,
  `LicenseManagerTests.swift`, `ProTransitionTests.swift`, `OnActionExtensionTests.swift`, and the
  `_test-support/Mocks.swift` `ShortcutStylePreference` mock — they will need updating/removal.
