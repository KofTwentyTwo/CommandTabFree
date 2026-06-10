# 05 — Trial / "Pro Transition" Nag-Escalation System

Scope: `src/pro/scheduling/` (the timed/escalating upsell machinery). This is the layer that
schedules and fires the Day1→Day35 nag prompts, computes the "hard gate" that blocks Pro features
after trial expiry, and persists which prompts have already been shown. It sits on top of the
license layer (`src/pro/license/`) and the feature-gating layer (`src/pro/ProFeature.swift`).

---

## 1. Architecture at a glance

The system is split into four cooperating pieces plus eight UI classes:

| Piece | File | Role |
|---|---|---|
| Coordinator | `ProTransitionManager.swift` | Singleton. Wires license state + persisted state + scheduler + UI emitter. Holds the public hooks App.swift calls. Owns the session-only free-pass flag. |
| Scheduler | `ProTransitionScheduler.swift` | Owns the persisted `nextScheduledDate`, the in-flight `DispatchWorkItem`, and `computeNextFireDate()`. Fires `onFire` (→ `evaluateAndShow()`). |
| Persisted state | `ProTransitionState.swift` | All `hasSeen*` flags + `remembered*` Pro indices in the `<bundleId>.license` UserDefaults suite, keys prefixed `proTransition.`. Snapshots into the pure decision struct. |
| Pure decision logic | `ProTransitionManagerTestable.swift` | No singletons / no `Date()` / no UI. `State` struct + `evaluate*` functions. The actual state machine. 100% unit-tested by `ProTransitionTests.swift`. |
| UI dispatch | `src/pro/ui/ProPromptHost.swift` | Receives `ProPromptAction` enum cases and maps them to concrete Day-X window/popover classes. |

The coordinator never references AppKit Day-X classes directly. It emits a `ProPromptAction`
(`ProTransitionManager.swift:87-98`) through `onAction`; `ProPromptHost.dispatch(_:)`
(`ProPromptHost.swift:11-38`) owns the concrete `.show()` calls.

### Time / day model
- `daysSinceTrialStart` is **0-indexed**: Day 1 = 0, Day 12 = 11, Day 15 = 14, Day 21 = 20,
  Day 35 = 34, Day 49 = 48 (`ProTransitionManagerTestable.swift:11`, computed in
  `LicenseManager.daysSinceTrialStart`, `LicenseManager.swift:79-82`:
  `Int(clock.now.timeIntervalSince(start) / 86400)`).
- `trialStartDate` is stored in the license UserDefaults suite (`LicenseManager.swift:74-77`).
- Time-of-day windows: prompts only fire between **10:00–11:30** or **15:30–17:00**
  (`ProTransitionManagerTestable.isInTimeWindow`, `ProTransitionManagerTestable.swift:148-152`:
  600–690 min or 930–1020 min). The window check is snapshotted in
  `ProTransitionState.snapshot(...)` (`ProTransitionState.swift:97-118`).

---

## 2. What triggers the system (entry points)

There are exactly **three** kinds of trigger, all routed through `ProTransitionManager`:

### A. App launch / timed scheduler fire
- `App.swift:429` calls `ProTransitionManager.shared.onAppLaunchComplete()` at end of launch
  (after `onAction` is wired at `App.swift:428`).
- `ProTransitionManager.onAppLaunchComplete()` (`ProTransitionManager.swift:167-169`) delegates to
  `scheduler.onAppLaunchComplete()` (`ProTransitionScheduler.swift:24-30`): if a persisted
  `nextScheduledDate` is in the past, fire immediately; then `scheduleNext()`.
- The scheduler arms a single `DispatchWorkItem` (`ProTransitionScheduler.swift:40-55`) that calls
  `onFire` → `evaluateAndShow()` (`ProTransitionManager.swift:121, 271-293`) → consults
  `evaluateTimedAction(...)` and emits the matching prompt action, then re-arms `scheduleNext()`.

### B. Switcher shown / dismissed
- `App.showUiOrCycleSelection()` calls `ProTransitionManager.shared.onSwitcherShown()` at the start
  of a **fresh** summon, not on a cycle (`App.swift:328`, inside the `isFirstSummon` branch).
- `App.hideUi()` calls `ProTransitionManager.shared.onSwitcherDismissed()` (`App.swift:78`).
- `onSwitcherShown()` (`ProTransitionManager.swift:205-223`) consults `evaluateSwitcherOpen(...)`
  and queues a `pendingDismissAction` (Day 4 tour, or post-expiration free-pass + [C]).
- `onSwitcherDismissed()` (`ProTransitionManager.swift:187-201`) ends any active free-pass session
  and, 1 second later (so the focused window is back in front), runs the queued action.

### C. Hard-gated feature attempt (use-time)
- `ProFeature.attemptUse()` (`ProFeature.swift:74-83`) is the gate. For the hard-gated features
  (`.extraShortcut`, `.searchInSwitcher`, `.lockSearchInSwitcher`) it calls
  `ProTransitionManager.shared.attemptHardGatedFeature(self)` (`ProFeature.swift:79`).
- `attemptHardGatedFeature(_:)` (`ProTransitionManager.swift:226-242`) consults `evaluateHardGate`
  and returns whether the action may proceed; side effects are the free-pass / [C] / [E] ladder.

---

## 3. Public hooks called from App.swift (the integration surface)

These are the exact call sites a clean removal must sever (all in `src/App.swift` unless noted):

| Call site | Hook | Purpose |
|---|---|---|
| `App.swift:78` | `onSwitcherDismissed()` | Ends free-pass session, fires deferred prompt. |
| `App.swift:116` | `ProTransitionManager.openCheckout()` | Opens LemonSqueezy checkout URL. |
| `App.swift:207` | `hasSeenWelcome` (read) | Gates first-launch behavior (`!hasSeenWelcome`). |
| `App.swift:328` | `onSwitcherShown()` | Queues Day 4 tour / post-expiry free-pass. |
| `App.swift:428` | `onAction = { ProPromptHost.shared.dispatch($0) }` | Wires the emitter to the UI host. |
| `App.swift:429` | `onAppLaunchComplete()` | Kicks off the scheduler. |
| `App.swift:448` | `onProUnlocked()` (via `LicenseManager.onBeforeProUnlock`) | Restores remembered Pro prefs on purchase. |
| `App.swift:452` | `onLicenseStateChanged()` | Cancels scheduler + dismisses windows on Pro; engages lock on expiry. |
| `App.swift:458` | `proLockStateDidChangeNotification` (post) | Refreshes Settings ghost UI. |
| `Menubar.swift:205` | `shouldShowBadgeDot` (read) | Days 13–14 menubar badge dot. |
| `PreferenceDefinition.swift:35` | `isFreePassSessionActive` (read) | Swaps stored→remembered Pro value during free-pass. |
| `ProFeature.swift:76,79` | `isFreePassSessionActive`, `attemptHardGatedFeature(_:)` | Hard-gate ladder. |
| `QAMenu.swift:179-234` | many | DEBUG-only manual triggers / resets. |
| `AppearanceTab.swift:416`, `ControlsTab.swift:141` | `proLockStateDidChangeNotification` (observe) | Live Settings ghost-UI refresh. |

---

## 4. The full trial timeline (day-by-day)

All prompt selection lives in `ProTransitionManagerTestable.evaluateTimedAction(_:)`
(`ProTransitionManagerTestable.swift:63-98`), `evaluateSwitcherOpen(_:)` (lines 114-127), and
`evaluateHardGate(_:)` (lines 101-106). Letters [A]–[H] match the spec / `ProPromptAction` enum.

| Day (1-idx) | `daysSinceTrialStart` | Prompt | Trigger | What fires | Gate flag | Soft / Hard | Retry / miss behavior |
|---|---|---|---|---|---|---|---|
| **Day 1** | 0 | **[A] Welcome Letter** `Day1WelcomeLetterWindow` | Timed: launch / scheduler. `computeNextFireDate` returns `Date()` immediately while `!hasSeenWelcome` (`ProTransitionScheduler.swift:64-66`). `evaluateTimedAction` returns `.showWelcome` and blocks all other actions until seen (`Testable:67-69`). | NSWindow 560×520, Free-vs-Pro comparison table, "Start my 14-day trial" button. Copy varies fresh-install vs upgrade via `ProTransitionState.isFreshInstall` (`Day1WelcomeLetterWindow.swift:14-26`). | `hasSeenWelcome` | Soft | Always shows. |
| **Day 4** | 3 | **[H] Day 4 Tour** `Day4TourPopover` | **Switcher open** only. `evaluateSwitcherOpen` returns `.showDay4Tour` iff `isTrialActive && daysSinceTrialStart==3 && !hasSeenDay4Tour` (`Testable:116-119`). Deferred to 1s post-dismiss (`Manager:208-210, 193-199`). | NSPopover under menubar icon, 280×110, lists App Icons/Titles, extra shortcuts, Search; "Try them in Settings". | `hasSeenDay4Tour` | Soft | No retry — only fires if switcher is opened on Day 4 exactly. |
| Days 5–11 | 4–10 | — | — | Silent trial. | — | — | — |
| **Day 12** | 11 | **[B] Heads-Up** `Day12HeadsUpPopover` | Timed, only on the single day `daysSinceTrialStart==11`, inside a time window (`Testable:71-73`). Scheduler drops the candidate once `< day13Start` (`Scheduler:71-76`). | NSPopover under menubar icon, 300×100, "Your Pro trial ends in 2 days", "Not now" + "Get Pro". Also refreshes badge (`ProPromptHost.swift:17-19`). | `hasSeenDay12` | Soft | If missed in 10:00 window, try 15:30 window; **skip entirely** on Day 13+ (no retry). |
| Days 13–14 | 12–13 | Badge dot | `shouldShowBadgeDot` = `!isPro && isTrialActive && 12 <= days <= 13` (`Testable:131-133`). Read by `Menubar.swift:205`. | Orange/red dot on menubar icon. | — | Soft | Removed on Day 15 (days≥14). |
| **Day 15 (expiry)** | 14 | License flips to `.trialExpired`; **HARD GATE arms** | On the license state change, `onLicenseStateChanged()` (`Manager:171-182`) calls `onProLockEngaged()` because `isProLocked` is now true. | Degradable Pro prefs (style, size, shortcut style) immediately downgrade to Free equivalents and the Pro value is snapshotted into `remembered*` (`ProTransitionState.onProLockEngaged`, `ProTransitionState.swift:73-79`). | — | **HARD** | — |
| **Day 15+** | ≥14 | **[D] Proactive** `Day15ProactiveWindow` | Timed, only if **no hard-gate fired yet**: `days>=14 && !hasSeenProactiveDay15 && !hasSeenFullUpgrade && isInTimeWindow` (`Testable:77`). | NSWindow 380×280, "Your 14-day Pro trial just ended", two-stat usage hero, "Get Pro" / "Maybe later". `showProactiveDay15Window()` also calls `onProLockEngaged()` (`Manager:253-257`). | `hasSeenProactiveDay15` | Soft (window) | Retry next active day until shown or [C] fires. Scheduler stops offering it once `hasSeenFullUpgrade` (`Scheduler:79`). |
| **Day 15+** | ≥14 | **[C] Full Upgrade** `Day15FullUpgradeWindow` | (a) First **switcher open** post-expiry → free-pass + [C] (`evaluateSwitcherOpen` → `.triggerFreePass`, `Testable:123-124`); or (b) first **hard-gate attempt** via the free-pass ladder (`evaluateHardGate`, `Testable:101-106`). | NSWindow 440×340, header resolved by `HardGateReason.resolved` priority (`Manager:40-73`), usage hero, "Get Pro" / "Continue with Free". `showFullUpgradeWindow` sets `hasSeenFullUpgrade=true` then `onProLockEngaged()` (`Manager:244-251`). | `hasSeenFullUpgrade`, `freePassUsed`, `hasTriggeredPostExpirationSwitcher` | **HARD** (this is the lock-in moment) | N/A — user-initiated. Once-ever. |
| **after [C]** | ≥14 | **[E] Hard-Gate Popover** `Day15HardGatePopover` | Every hard-gate attempt **after** [C] shown: `evaluateHardGate` returns `.showHardGatePopover` when `freePassUsed && hasSeenFullUpgrade` (`Testable:101-106`). | NSPopover under menubar icon 280×100, header from same `resolved` priority, "Not now" / "Get Pro". | — | **HARD** (feature is blocked, returns `false`) | Fires on **every** post-[C] hard-gate attempt forever (continues after opt-out). |
| **Day 21–34** | 20–33 | **[F] Day 21 Reminder** `Day21ReminderPopover` | Timed: `days>=20 && days<34 && !hasSeenDay21 && isInTimeWindow` (`Testable:88`). Checked **after** Day 35 so a long-inactive user skips straight to [G]. | NSPopover 300×140, "AltTab Pro is still available", `ProConversionCopy.day21Body()`, "Not now" / "Get Pro". | `hasSeenDay21` | Soft | Retry daily; skipped if Day 35 arrives first (`hasSeenDay35` guard, `Scheduler:86`). |
| **Day 35–48** | 34–47 | **[G] Day 35 Final** `Day35FinalWindow` | Timed: `days>=34 && days<48 && !hasSeenDay35 && isInTimeWindow` (`Testable:83`). Checked **before** [F] (`Testable:82`). | NSWindow 380×280, "Still interested in Pro?", usage hero, "Get Pro" / **"No thanks — don't ask again"** (→ `userOptedOut=true`, `Day35FinalWindow.swift:37-41`). | `hasSeenDay35`, `userOptedOut` | Soft | Retry daily; **give up at Day 49** (`days<48` upper bound; scheduler caps at `day49`, `Scheduler:92-99`). ⨉ sets `hasSeenDay35` but does NOT opt out. |
| **Day 49+** | ≥48 | — | Scheduling complete (`isSchedulingComplete`, `Testable:140`). | Steady state: [E] on every hard-gate attempt; degradable features silently fall back; purchase only via Preferences. | — | **HARD** persists | — |

After all proactive prompts: `evaluateTimedAction` falls through to `.refreshBadgeDot` for `days>=14`
(`Testable:93-95`), which just re-paints the (now-removed) badge.

---

## 5. Soft nags vs. the HARD GATE — exactly what gets locked

**Soft nags** = [A], [H], [B], [D], [F], [G] and the badge dot. These are pure informational
windows/popovers. They never block functionality. Each is gated once-ever by a `hasSeen*` flag.
Dismissing them does nothing except set the flag (except [G]'s opt-out link, which sets
`userOptedOut`).

**The HARD GATE** is the feature-blocking mechanism that arms at trial expiry (Day 15). Two layers:

1. **Degradable prefs downgrade immediately** (`onProLockEngaged`, `ProTransitionState.swift:73-79`).
   On the `isProLocked` transition, every entry in `ProGatedPreferences.all` is snapshotted and
   downgraded: appearance style → `.thumbnails`, size → `.medium`, shortcut style →
   `.doNothingOnRelease`. The original Pro index is saved to `remembered*` (drives Settings "ghost"
   UI + the one-last-session free-pass read). `PreferenceDefinition.read()` (`PreferenceDefinition.swift:32-44`)
   returns the Free equivalent once locked — unless a free-pass session is active, in which case it
   returns the remembered Pro value (`PreferenceDefinition.swift:35-39`).

2. **Hard-gated features are blocked at use-time** via the **free-pass ladder**
   (`evaluateHardGate`, `Testable:101-106`):
   - `isPro || isTrialActive` → `.allow` (run normally).
   - `!freePassUsed` → `.freePass`: allow the action **once**, mark `freePassUsed=true`, open a
     free-pass session, and queue [C] for after dismissal (`Manager:230-234`).
   - `!hasSeenFullUpgrade` → `.showFullUpgrade`: block the feature (return `false`), show [C]
     inline (`Manager:235-237`).
   - else → `.showHardGatePopover`: block the feature, show [E] (`Manager:238-240`). Fires forever.

   Hard-gated features (`ProFeature.attemptUse`, `ProFeature.swift:77-82`): `.extraShortcut`
   (shortcut slot ≥ 2), `.searchInSwitcher`, `.lockSearchInSwitcher`. The degradable-only set
   (`.appIconsAndTitlesStyle`, `.autoSize`, `.searchOnReleaseShortcut`) always returns `true` here
   because it is gated at preference-write time, not use-time.

**The defining difference:** soft nags return control to the user immediately. After [C] has fired,
the hard gate **permanently blocks** the three hard-gated features (returns `false`, action does
not execute) and shows [E] each time — even after opt-out, even past Day 49. Only purchase clears it.

---

## 6. Free-pass sessions

A free-pass session is a **session-only** window (`isFreePassSessionActive`,
`ProTransitionManager.swift:135-142`) during which the user gets their Pro experience back for one
last switcher summon. It is opened in two places:

- `onSwitcherShown()` → `.triggerFreePass` (first post-expiry summon): sets `freePassUsed=true`,
  `hasTriggeredPostExpirationSwitcher=true`, `isFreePassSessionActive=true`, builds a
  `HardGateReason.proPreferences(...)` from `remembered*`, and queues [C] (`Manager:211-219`).
- `attemptHardGatedFeature()` → `.freePass`: sets `freePassUsed=true`, `isFreePassSessionActive=true`,
  queues [C] for the attempted feature (`Manager:230-234`).

While active:
- `PreferenceDefinition.read()` returns the **remembered Pro value** instead of the downgraded
  stored value (`PreferenceDefinition.swift:35-39`), so the switcher renders Pro for that one session.
- `ProFeature.attemptUse()` returns `true` for *all* features without re-consuming the pass
  (`ProFeature.swift:76`), so search/lock-search/extra-shortcut chords work inside the session.
- Setting the flag triggers `App.resetPreferencesDependentComponents()` (when `TilesPanel` exists)
  so `TilesView` re-renders against the new `read()` (`Manager:136-142`).

The session ends in `onSwitcherDismissed()` (`Manager:189`), which sets
`isFreePassSessionActive=false`; the deferred [C] window then appears 1s later (`Manager:193-199`).

---

## 7. How the schedule is computed and persisted

`ProTransitionScheduler.computeNextFireDate()` (`ProTransitionScheduler.swift:58-103`):
- Bails (returns `nil`) if Pro, or `userOptedOut && hasSeenDay35`, or no `trialStartDate`.
- If `!hasSeenWelcome` → returns `Date()` (fire [A] now).
- Otherwise builds a candidate list from the unshown prompts (Day 12, Day 15 proactive, Day 21,
  Day 35), each via `nextTimeWindow(onOrAfterDay:trialStart:)` (`Scheduler:106-123`) which finds the
  next 10:00 or 15:30 slot on/after the target trial day (scanning up to 60 days). Returns the
  **earliest** candidate.
- Day 12 candidate is dropped once past `day13Start` (`Scheduler:71-76`); Day 35 candidate must be
  before `day49` (`Scheduler:92-99`).

`scheduleNext()` (`Scheduler:40-55`) cancels the prior `DispatchWorkItem`, persists the chosen date
to UserDefaults key `proTransition.nextScheduledDate` (`Scheduler:14, 46`), and arms a new
`DispatchWorkItem` via `asyncAfter`. On fire it calls `onFire()` then re-schedules.

**Persistence:** all flags + the next-fire date live in the `<bundleId>.license` UserDefaults suite,
keys prefixed `proTransition.` (`ProTransitionState.swift:9, 136-154`; `Scheduler:14`). Note the
schedule and the nag state are co-located in the **license** suite (shared with `trialStartDate`),
not standard defaults. The pure-decision `isSchedulingComplete` (`Testable:136-145`) mirrors the
scheduler's bail conditions for testing.

`cancel()` (`Scheduler:33-37`) removes `nextScheduledDate` and the work item — called on purchase
via `onLicenseStateChanged()` (`Manager:172-176`), which also emits `.dismissAllProWindows` +
`.refreshBadge`.

---

## 8. Removal notes (for the free build)

Removing the nag system cleanly is largely about severing the App.swift hooks in §3 and deleting the
`src/pro/scheduling/` directory. Key dependencies and risks:

- **`src/pro/scheduling/` is self-contained UI/logic** but depends on: `ProFeature` /
  `ProGatedPreferences` (feature gating), `LicenseManager` (state, `trialStartDate`,
  `daysSinceTrialStart`, `clock`), `UsageStats`, `ProConversionCopy` / `ProFeatureCopy`,
  `ProPromptWindow`/`ProPromptPopover`/`ProPromptHeader`/`UsageStatHeroView`/`NotAdvisedButton`
  (shared Pro UI in `src/pro/ui/`), and `Endpoints.checkoutUrl`. Those are part of the broader
  paywall and are covered by other audit sections; this directory is a *consumer* of them.
- **App.swift hooks to remove/neutralize** (all load-bearing): `App.swift:78, 116, 207, 328, 428,
  429, 448, 452, 458`. The `onSwitcherShown`/`onSwitcherDismissed` calls are in the switcher hot
  path; the `pendingDismissAction` 1s-deferred dispatch must be dropped with them.
- **`ProFeature.attemptUse()` (`ProFeature.swift:74-83`)** calls into `attemptHardGatedFeature`.
  For a fully-unlocked build this must unconditionally return `true` (delete the
  `ProTransitionManager` call and the `isFreePassSessionActive` short-circuit at `ProFeature.swift:76`).
- **`PreferenceDefinition.read()` (`PreferenceDefinition.swift:32-44`)** references
  `isFreePassSessionActive` and `ProTransitionState.int(...)`. With no lock these branches are dead;
  removal must keep `read()` returning the stored value unconditionally.
- **`Menubar.swift:205`** reads `shouldShowBadgeDot`; remove the badge-dot call.
- **Settings observers** (`AppearanceTab.swift:416`, `ControlsTab.swift:141`) subscribe to
  `proLockStateDidChangeNotification`; with no lock these never fire but the symbol must still
  resolve or be removed alongside the manager.
- **`ProGatedPreferences.all`** is iterated by `onProLockEngaged`/`onProUnlocked`. If those prefs
  become permanently unlocked, the snapshot/restore logic is dead code; ensure no stored value is
  ever forced to the Free equivalent on launch.
- **Risk — orphaned UserDefaults:** existing installs carry `proTransition.*` keys in the
  `<bundleId>.license` suite (and `trialStartDate`). A free build that ignores them is safe, but if
  any remaining read of `isProLocked` survives, a previously-expired user could still see a degraded
  pref. Confirm `isProLocked` always evaluates to `false` in the free build.
- **DEBUG-only QAMenu** (`QAMenu.swift:170-241`) directly instantiates every Day-X window and pokes
  manager flags; it must be removed/updated in lockstep or it won't compile.
- **Tests:** `ProTransitionTests.swift` (729 lines) and `ProTransitionManagerTestable.swift` are
  pure-logic and will need to be deleted with the system; nothing outside scheduling imports them.
