# 06 — ProFeature Model & Marketing/Conversion Copy

Scope: `src/pro/ProFeature.swift`, `src/pro/ProFeatureCopy.swift`, `src/pro/ProConversionCopy.swift`, and the Pro-gating machinery in `src/preferences/PreferenceDefinition.swift`. Cross-references to call sites are included so a clean free-build removal can be planned without breaking compilation.

All paths are absolute under `/Users/james.maes/Git.Local/kof22/alt-tab-free`.

---

## 1. The `ProFeature` model

Defined in `src/pro/ProFeature.swift:8`. `ProFeature` is an `enum: Equatable, Hashable` that is described in its own doc comment (`src/pro/ProFeature.swift:3-7`) as the "single source of truth" for: which preferences degrade on lock, which runtime actions are hard-gated, which preference keys the click-interceptor routes to the Upgrade tab, and which copy the Day-X views show.

### 1.1 Cases (`src/pro/ProFeature.swift:9-16`)

```swift
case appIconsAndTitlesStyle           // degradable preference
case autoSize                         // degradable preference
case searchOnReleaseShortcut          // degradable preference
case extraShortcut(index: Int)        // hard-gated runtime action, no stored pref
case searchInSwitcher                 // hard-gated runtime action, no stored pref
case lockSearchInSwitcher             // hard-gated runtime action, no stored pref
```

### 1.2 `GateKind` and `gateKind` (`src/pro/ProFeature.swift:18-33`)

Three gate kinds:
- `.degradable` — silent fallback only; the stored value is downgraded on lock; never triggers the `[C]` upgrade prompt by itself.
- `.hardGated` — use-time free-pass → `[C]` ladder; no stored preference.
- `.degradableAndHardGated` — both: silent downgrade AND the first post-expiration switcher summon triggers `[C]`.

Mapping in `gateKind` (`src/pro/ProFeature.swift:27-33`):
- `.autoSize` → `.degradable`
- `.appIconsAndTitlesStyle`, `.searchOnReleaseShortcut` → `.degradableAndHardGated`
- `.extraShortcut`, `.searchInSwitcher`, `.lockSearchInSwitcher` → `.hardGated`

### 1.3 `gatedPreference` — link to the backing preference (`src/pro/ProFeature.swift:35-44`)

Returns the type-erased `AnyProGatedPreference` (defined in `PreferenceDefinition.swift`) that backs a degradable feature, or `nil` for hard-gated cases:
- `.appIconsAndTitlesStyle` → `ProGatedPreferences.appearanceStyle.erased`
- `.autoSize` → `ProGatedPreferences.appearanceSize.erased`
- `.searchOnReleaseShortcut` → `ProGatedPreferences.shortcutStyle.erased`
- `.extraShortcut`, `.searchInSwitcher`, `.lockSearchInSwitcher` → `nil`

### 1.4 `copy` — per-case marketing line (`src/pro/ProFeature.swift:46-56`)

Maps each case to a `ProFeatureCopy` string. Note multiple cases share a line:
- `.appIconsAndTitlesStyle` → `ProFeatureCopy.appIconsAndTitles`
- `.autoSize` → `ProFeatureCopy.autoSize`
- `.searchOnReleaseShortcut` → `ProFeatureCopy.extraShortcuts` ("grouped under keyboard shortcuts")
- `.extraShortcut` → `ProFeatureCopy.extraShortcuts`
- `.searchInSwitcher`, `.lockSearchInSwitcher` → `ProFeatureCopy.search`

### 1.5 `degradable` list (`src/pro/ProFeature.swift:59`)

```swift
static let degradable: [ProFeature] = [.appIconsAndTitlesStyle, .autoSize, .searchOnReleaseShortcut]
```

### 1.6 Availability & runtime gating

- `isAvailable` (`src/pro/ProFeature.swift:63`) → `LicenseManager.shared.isProAvailable`
- `isLocked` (`src/pro/ProFeature.swift:65`) → `LicenseManager.shared.isProLocked`
- `attemptUse() -> Bool` (`src/pro/ProFeature.swift:74-83`): returns `true` if Pro is available or a free-pass session is active; otherwise hard-gated cases consult `ProTransitionManager.shared.attemptHardGatedFeature(self)` while degradable cases always return `true` (they are gated at preference-write time, not use time).
- `isStoredValuePro(preferenceKey:)` (`src/pro/ProFeature.swift:87-89`): static helper that delegates to `ProGatedPreferences.forPreferenceKey(...)?.isStoredValuePro()`. **Note:** the `snapshotAndDowngradeStored` / `restoreStored` / `preferenceKey` / `rememberedKey` methods named in the audit prompt no longer live on `ProFeature` — the doc comments in `PreferenceDefinition.swift:16-17` and `:99-101` explicitly state this logic was extracted out of `ProFeature` into `PreferenceDefinition`. They are documented in section 3 below at their current home.

---

## 2. Marketing copy strings (these get deleted)

### 2.1 `ProFeatureCopy` (`src/pro/ProFeatureCopy.swift:3-8`)

The canonical feature-list strings. Every one of these is a `NSLocalizedString`:

| Constant | String |
|---|---|
| `appIconsAndTitles` | `"App Icons & Titles styles"` |
| `search` | `"Search — find a window by typing"` |
| `autoSize` | `"Auto Size — larger previews with few windows, more at once with many"` |
| `extraShortcuts` | `"Up to 9 keyboard shortcuts"` |

Consumers (all upsell UI, to be removed/neutralised):
- `src/pro/scheduling/Day1WelcomeLetterWindow.swift:77-80` — the Free-vs-Pro comparison table rows.
- `src/pro/ProFeature.swift:50-54` — the `copy` accessor.

### 2.2 `ProConversionCopy` (`src/pro/ProConversionCopy.swift`)

View-layer presenter for trial-nag prompts. Reads from `UsageStats` and emits formatted upsell strings. All strings are `NSLocalizedString` and are pure upsell/nag copy.

`day12Subtitle()` (`src/pro/ProConversionCopy.swift:11-24`):
- empty usage: `"On Day 15, Pro features revert to the free version."`
- 1–2 used: `"You've been using %@.\nThese will switch back to defaults on Day 15."`
- 3+ used: `"You've been using %d Pro features.\nThey'll switch back to defaults on Day 15."`

`day21Body()` (`src/pro/ProConversionCopy.swift:26-44`):
- both counts > 0: `"You've used AltTab %@ times — %@ of those used Pro features."`
- triggers only: `"You've used AltTab %@ times."`
- neither: `"Pro is still available whenever you're ready."`

Consumers:
- `src/pro/scheduling/Day12HeadsUpPopover.swift:21` — `ProConversionCopy.day12Subtitle()`
- `src/pro/scheduling/Day21ReminderPopover.swift:18` — `ProConversionCopy.day21Body()`

### 2.3 Adjacent upsell copy that references this scope (out of file, in scope by linkage)

These strings live in sibling files but are wired directly to `ProFeatureCopy`/feature names and are also upsell copy slated for deletion:

- `src/pro/scheduling/Day1WelcomeLetterWindow.swift:20-26` — welcome/"now has a Pro tier" titles and the 14-day-trial body copy; `:36` `"Start my 14-day trial"`; `:75-76,89-92` table headers (`"Feature"`, `"Free"`, gradient "Pro" header) and the two always-true free rows (`"Reliable, fast window switching with high-quality thumbnails"`, `"Dark Mode, live preview, window controls, trackpad gestures, and more"`).
- `src/pro/scheduling/Day15FullUpgradeWindow.swift:22-44` — supporting lines: `"AltTab Pro adds 4 features beyond the free switcher."`, `"Some Pro features have reverted to free defaults."`, plus per-reason lines (`"Extra shortcuts are a Pro feature."`, `"Search is a Pro feature."`, `"The App Icons style is a Pro feature."`, `"The Titles style is a Pro feature."`); `:59` `"Get Pro"`; `:66` `"Continue with Free"`.
- `src/util/UsageStatsTestable.swift:4-9` — feature display names fed into `ProConversionCopy.day12Subtitle()` via `UsageStats.usedProFeatureNames()`: `"Search"`, `"App Icons appearance"`, `"Titles appearance"`, `"Extra shortcuts"`.

---

## 3. Snapshot / downgrade / restore machinery (now in `PreferenceDefinition.swift`)

The methods the prompt calls `snapshotAndDowngradeStored` / `restoreStored` / `isStoredValuePro` / `preferenceKey` / `rememberedKey` have been refactored out of `ProFeature` and now live on `PreferenceDefinition<T>` / `AnyProGatedPreference` in `src/preferences/PreferenceDefinition.swift`.

### 3.1 `PreferenceGate<T>` (`src/preferences/PreferenceDefinition.swift:7-11`)

Per-preference gate policy carrying:
- `freeEquivalent: T` — the value to fall back to when locked.
- `rememberedKey: String` — UserDefaults sub-key under which the Pro value index is snapshotted.
- `isProValue: (T) -> Bool` — predicate identifying which stored values count as "Pro".

### 3.2 `PreferenceDefinition<T>` (`src/preferences/PreferenceDefinition.swift:18-74`)

Single-source-of-truth per macro preference. Carries `key`, `default`, optional `gate`. Methods:
- `read() -> T` (`:32-44`) — reads stored value via `CachedUserDefaults.macroPref`; if locked + gated, three branches: (1) active free-pass + valid remembered index → return remembered Pro selection; (2) stored value is still Pro → return `freeEquivalent`; (3) otherwise return stored (already downgraded).
- `snapshotAndDowngrade() -> Int?` (`:51-57`) — if stored value is a Pro selection, overwrite with `freeEquivalent` via `Preferences.set(...)` and return the original index for the caller to persist under `rememberedKey`. Returns `nil` if no gate or already free.
- `restore(from rememberedIndex:)` (`:62-65`) — writes the remembered index back via `Preferences.set(key, ..., false)` (notify:false so the restore pass doesn't bounce observers to Upgrade).
- `isStoredValuePro() -> Bool` (`:69-73`) — true when the stored value is a Pro selection, regardless of lock state. This is what `ProFeature.isStoredValuePro(preferenceKey:)` and `PreferencesEvents` consult.

### 3.3 `AnyProGatedPreference` (`src/preferences/PreferenceDefinition.swift:79-96`)

Type-erased descriptor exposing concrete-typed ops only: `preferenceKey`, `rememberedKey`, `snapshotAndDowngrade: () -> Int?`, `restoreFromIndex: (Int) -> Void`, `isStoredValuePro: () -> Bool`. Produced by `PreferenceDefinition.erased` (`:88-95`). This is what `ProFeature.gatedPreference` returns.

### 3.4 `ProGatedPreferences` registry (`src/preferences/PreferenceDefinition.swift:102-170`)

Holds all gated `PreferenceDefinition`s, the `all` list, and `forPreferenceKey(_:)` lookup. See section 4 for the value-level mapping.

### 3.5 Where the passes are driven (`src/pro/scheduling/ProTransitionState.swift`)

- `onProLockEngaged()` (`:73-79`) — iterates `ProGatedPreferences.all`, calls `pref.snapshotAndDowngrade()`, and persists the returned index under `pref.rememberedKey`. Idempotent.
- `onProUnlocked()` (`:85-92`) — iterates `ProGatedPreferences.all`, restores from remembered index via `pref.restoreFromIndex(idx)`, then clears the remembered key.
- `resetAll()` (DEBUG, `:125-131`) — clears the remembered keys among other transition flags.

---

## 4. Definitive list of "Pro" features and their preference mappings

### 4.1 Degradable features (have a backing preference)

| ProFeature case | Backing `ProGatedPreferences` def | preferenceKey | rememberedKey | default | freeEquivalent | isProValue (= what counts as Pro) |
|---|---|---|---|---|---|---|
| `.appIconsAndTitlesStyle` | `appearanceStyle` (`PreferenceDefinition.swift:103-109`) | `appearanceStyle` | `rememberedAppearanceStyle` | `.thumbnails` | `.thumbnails` | `$0 != .thumbnails` (i.e. `.appIcons` or `.titles`) |
| `.autoSize` | `appearanceSize` (`:111-117`) | `appearanceSize` | `rememberedAppearanceSize` | `.auto` | `.medium` | `$0 == .auto` |
| `.searchOnReleaseShortcut` | `shortcutStyle` (`:119-125`) | `shortcutStyle` | `rememberedShortcutStyle` | `.focusOnRelease` | `.doNothingOnRelease` | `$0 == .searchOnRelease` |

Underlying enums (`src/preferences/MacroPreferences.swift`):
- `AppearanceStylePreference` (`:284-287`): `.thumbnails`, `.appIcons`, `.titles` → Pro = `.appIcons`/`.titles`.
- `AppearanceSizePreference` (`:308-312`): `.small`, `.medium`, `.large`, `.auto` → Pro = `.auto`.
- `ShortcutStylePreference` (`:100-103`): `.focusOnRelease`, `.doNothingOnRelease`, `.searchOnRelease` → Pro = `.searchOnRelease`.

### 4.2 Per-shortcut override gated preferences (no direct ProFeature case)

`ProGatedPreferences.all` (`PreferenceDefinition.swift:157-164`) also includes three per-shortcut "override 0" definitions that are NOT directly mapped from a `ProFeature` case but ARE snapshotted/restored on lock/unlock. Their registered defaults are the FREE values, so `snapshotAndDowngrade` is a no-op unless the user explicitly set a Pro override:

| Def | preferenceKey | rememberedKey | default | freeEquivalent | isProValue |
|---|---|---|---|---|---|
| `appearanceStyleOverride0` (`:131-137`) | `appearanceStyleOverride` | `rememberedAppearanceStyleOverride` | `.thumbnails` | `.thumbnails` | `$0 != .thumbnails` |
| `appearanceSizeOverride0` (`:139-145`) | `appearanceSizeOverride` | `rememberedAppearanceSizeOverride` | `.medium` | `.medium` | `$0 == .auto` |
| `shortcutStyleOverride0` (`:147-153`) | `shortcutStyleOverride` | `rememberedShortcutStyleOverride` | `.doNothingOnRelease` | `.doNothingOnRelease` | `$0 == .searchOnRelease` |

### 4.3 Hard-gated features (no backing preference)

| ProFeature case | Gate site | Behaviour |
|---|---|---|
| `.extraShortcut(index:)` | `src/switcher/ShortcutAction.swift:56` — gates pressing shortcut slot index ≥ 1 | `attemptUse()` → `ProTransitionManager.attemptHardGatedFeature`. Also recorded by `UsageStats.recordTrigger` under `triggersExtraShortcuts`. |
| `.searchInSwitcher` | `src/switcher/main-window/TilesView.swift:92` (`enableSearchEditing`) | gated via `SearchModeResolver.enableEditing(...canSearch:)` |
| `.lockSearchInSwitcher` | `src/switcher/main-window/TilesView.swift:79` (`lockSearchMode`) | gated via `SearchModeResolver.lock(...canLockSearch:)` |

The four marketing-level "Pro features" advertised to users (per `Day15FullUpgradeWindow.swift:23-25` "adds 4 features" and the `Day1` table `:77-80`) are: **App Icons & Titles styles, Search, Auto Size, and up to 9 keyboard shortcuts.**

---

## 5. Cross-reference: all known consumers of this scope

| Symbol | Consumer site |
|---|---|
| `ProFeature.extraShortcut(index:).attemptUse()` | `src/switcher/ShortcutAction.swift:56` |
| `ProFeature.lockSearchInSwitcher.attemptUse()` | `src/switcher/main-window/TilesView.swift:79` |
| `ProFeature.searchInSwitcher.attemptUse()` | `src/switcher/main-window/TilesView.swift:92` |
| `ProFeature.isStoredValuePro(preferenceKey:)` | `src/events/PreferencesEvents.swift:62` (bounces to `UpgradeTab.navigateToUpgradeTab()` when locked) |
| `ProFeatureCopy.*` (4 strings) | `src/pro/scheduling/Day1WelcomeLetterWindow.swift:77-80`; `src/pro/ProFeature.swift:50-54` |
| `ProConversionCopy.day12Subtitle()` | `src/pro/scheduling/Day12HeadsUpPopover.swift:21` |
| `ProConversionCopy.day21Body()` | `src/pro/scheduling/Day21ReminderPopover.swift:18` |
| `ProGatedPreferences.all` / `forPreferenceKey` | `src/pro/scheduling/ProTransitionState.swift:74,86,129`; `src/preferences/Preferences.swift`; `src/pro/ProFeature.swift:39-41,88` |
| `SearchModeResolver` gating note | `src/switcher/state/SearchModeResolver.swift:9` |

`SearchModeResolver` itself does not depend on `ProFeature` — it is purely a pure-state resolver that receives `canSearch`/`canLockSearch` booleans, so in a free build those callers can simply pass `true` (or be inlined) without touching `SearchModeResolver`.

---

## 6. Removal notes for a clean free build

1. **`attemptUse()` must become an unconditional `true`.** The three runtime gate sites (`ShortcutAction.swift:56`, `TilesView.swift:79,92`) all call `ProFeature.*.attemptUse()`. For a fully-unlocked build, either delete the `if !... { return }` guard at `ShortcutAction.swift:53-58` entirely, and pass `canSearch: true` / `canLockSearch: true` directly at `TilesView.swift:79,92`, or stub `attemptUse()` to always return `true`. Removing `ProFeature` wholesale requires editing all three call sites.

2. **`PreferencesEvents.swift:62` bounce-to-Upgrade must be removed.** This is the only consumer of `ProFeature.isStoredValuePro(preferenceKey:)`. Deleting the `if LicenseManager.shared.isProLocked && ProFeature.isStoredValuePro(...)` block (`:62-64`) prevents settings changes from yanking users to a (deleted) Upgrade tab. Note `UpgradeTab.navigateToUpgradeTab()` is itself paywall UI removed elsewhere.

3. **Preference gating (`PreferenceDefinition.read()`) must stop downgrading.** `read()` (`PreferenceDefinition.swift:32-44`) returns `freeEquivalent` when `LicenseManager.shared.isProLocked`. With a free build `isProLocked` should be hard-wired to `false` (license layer is audited separately), which neutralises `read()`, `snapshotAndDowngrade()`, and `onProLockEngaged()` without code changes here. Cleaner removal: strip the `gate:` arguments from all six `ProGatedPreferences` definitions (`:103-153`) so every preference is ungated, then `ProGatedPreferences.all` becomes empty and the snapshot/restore passes in `ProTransitionState` become no-ops. Confirm `Preferences.swift` getters still resolve through `PreferenceDefinition.read()` (referenced by the doc comment at `:99-100`) before stripping.

4. **`rememberedKey` migration risk.** Existing installs may have `proTransition.rememberedAppearanceStyle` / `...Size` / `...Style` (and the three `*Override` variants) persisted from a prior lock. If gating is removed without an unlock pass, a user's pre-lock Pro selection stays downgraded in `appearanceStyle`/`appearanceSize`/`shortcutStyle`. Consider running `onProUnlocked()` (`ProTransitionState.swift:85-92`) once on upgrade-to-free-build, or document that users may need to re-select their preferred style/size after migrating. The remembered keys are namespaced `proTransition.<key>` in UserDefaults.

5. **Copy deletion is self-contained.** `ProFeatureCopy.swift` and `ProConversionCopy.swift` can be deleted in full once `ProFeature.copy` (`ProFeature.swift:48-56`), `Day1WelcomeLetterWindow.swift:77-80`, `Day12HeadsUpPopover.swift:21`, and `Day21ReminderPopover.swift:18` are removed. The feature-name strings in `UsageStatsTestable.swift:4-9` and the `UsageStats.usedProFeatureNames()`/`usedProFeaturesSessionCount` telemetry feed only the conversion copy — they can be deleted with the nag system. `Day15FullUpgradeWindow.swift` supporting lines (`:22-44`) and `HardGateReason` are tied to the hard-gate ladder and are removed with that subsystem (covered by other audit sections).

6. **`UsageStats` trigger recording** (`src/util/UsageStats.swift:8-15`) exists only to power conversion copy and the Day-X nags. It has no functional effect on switching; safe to remove along with the prompt system, but it is harmless if left (writes to a separate `.usage` UserDefaults suite).
