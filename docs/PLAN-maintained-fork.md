# Plan: Maintained, De-Paywalled AltTab Fork (tracks upstream)

This plan describes how to run **alt-tab-free** as a *perpetually maintained* fork of
[lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos): ship with the Pro paywall
neutralized and every feature free, and keep pulling in upstream's bug-fixes and features
indefinitely — re-stripping the paywall and re-publishing each cycle with the *least possible
manual effort and merge-conflict surface*.

The goal is fundamentally different from a one-time removal. A one-shot excision optimizes for a
clean end-state; a tracked fork optimizes for **repeatable, low-friction re-application against a
moving upstream**. Those two objectives pull in opposite directions, and this plan resolves that
tension decisively in favor of a thin, isolated patch. It **supersedes**
[`docs/PLAN-republish-free.md`](PLAN-republish-free.md) (the one-shot "full excision" approach) for
the tracked-fork goal; that document remains the reference for GPL/ethics (§A) and for a from-scratch
clean removal if the fork ever abandons upstream tracking.

---

## TL;DR

- **The entire paywall was introduced by lwouis in one commit, `9147a4a8` / v11.0.0.** In the 34
  commits upstream has shipped since, the four feature-gate chokepoint files have had **zero** edits.
  A patch that lands on those dormant lines stays merge-clean essentially forever.
- **De-paywall with 3 small body-suppress edits in 3 cold files** (`computeState() → return .pro`, plus
  two `if false { … }` body wraps — the `if false` form is required by warnings-as-errors, §2) — no
  deletions, no edits to any hot or warm file.
- **Scope the "fails loudly" property honestly (do not over-trust the compile gate).** The forced
  `return .pro` hard-breaks the build only on a **signature/enum refactor** of `LicenseState`/`computeState`.
  A **silent semantic relock** that still compiles — a new `LicenseState` case, the gate re-pointed off
  `state`, a server-driven entitlement check, the live-state producer moved out of `computeState()` — is
  caught NOT by the compiler and NOT by Guard A (the gate-consumers `ProFeature`/`PreferenceDefinition` are
  outside the `unit-tests` target), but only by the §4.4 **behavioral guards + per-release feature-unlock
  check** and the §6.2 **manual gate-consumer review** (§2). The "fails loudly" headline applies to the
  refactor class only; the rest is covered by the behavioral/manual layers, not the compile/Guard-A gate. `src/pro/` stays physically present so `project.pbxproj` (the most merge-hostile file)
  is never touched **by the de-paywall patch and on every per-merge cycle**. One edit
  (`computeState() → return .pro`) opens every gate in the tree at once. (The anti-relock backstop is
  added as new test *methods inside the already-membered* `LicenseManagerTests.swift`, so it too needs
  **zero** pbxproj edits — see §4.4. The only `project.pbxproj` touch in the whole plan is a *one-time,
  optional* one if the owner insists on a separate test file; the default path avoids it entirely.)
- **Do NOT delete `src/pro/`.** Deletion forces ~99 edits to `project.pbxproj` plus surgery on the
  251-commit `App.swift` spine — guaranteeing conflicts on every future merge. Inertia is cheaper than
  excision here, and the churn data proves it.
- **Identity lives in fork-owned or content-overwritten files** (a committed `config/local.xcconfig`,
  a replaced `README.md` and `app.icns`, a few dormant `Info.plist` lines) so rebranding adds near-zero
  recurring conflict surface.
- **Git model: merge** (not rebase/patch-queue). **Trigger: a daily cron** (recommended: an EXTERNAL
  scheduler hitting `repository_dispatch`, not the in-repo `schedule:` that auto-disables after 60 days — §4.2)
  that opens a sync PR.
  **Backstop: TWO layers — (i) pre-merge guards** — an anti-relock unit test (mock-injected `LicenseManager`,
  appended to the existing `LicenseManagerTests.swift`, using the existing `MockClock`), a target-independent
  CI grep (Guard B), and a conflict-marker grep (Guard C), run by a SEPARATE fork-owned `guard.yml` workflow on
  `pull_request` so they survive even a careless `ci_cd.yml` conflict resolution (§4.4) — **plus a per-release
  feature-unlock acceptance check on the BUILT app** (the gate-consumers are not unit-testable, §4.4);
  **and (ii) the same Guard B + Guard C greps wired into `ci_cd.yml` as the FIRST push-job steps — before
  `run_tests.sh` and therefore before `update_appcast.sh` (Sparkle sign), `semantic-release` (tag push), and
  `softprops/action-gh-release`** — so a relock or a still-conflicted tree aborts the job *before the tag is
  pushed or the binary signed*, even if the PR gate is missing or misconfigured. (A grep placed only just
  before `action-gh-release` is too late — by then the tag is already pushed and the binary signed; §4.4.)
- **BLOCKING bootstrap requirement (§4.2):** the sync cron MUST author its branch push + PR with a
  workflow-re-triggering credential (a GitHub App installation token / fork PAT, `SYNC_BOT_TOKEN`), **NOT the
  default `GITHUB_TOKEN`** — by GitHub's recursion rule a `GITHUB_TOKEN`-authored PR fires NO `pull_request`
  checks, so `guard.yml`/`ci_cd.yml`'s pre-merge gate would silently never run.
- **A first-class, mandatory bootstrap deliverable (§4.2/§6.1):** add a `pull_request:` trigger
  to the fork's `ci_cd.yml` AND gate every release-side step (including `commitlint` and
  `determine_next_version`, which misbehave on PR events — §4.2) so the PR check is cleanly green/red — with
  an acceptance test that a deliberately-relocked branch shows a RED PR check before merge. Upstream's
  `ci_cd.yml` fires only on push-to-master and is the sole workflow, so without this the guards would run only
  *post-merge*; the layered design above means a relock still cannot ship even in that degraded state.
- **One-time bootstrap chores the steady-state runbook does NOT repeat** (do these once before first
  release): re-sign the bundled Sparkle helpers under the fork's Developer ID, sweep the residual
  hardcoded `AltTab` brand strings (l10n + a handful of `src/*.swift` literals), repoint
  `App.repository`/`APP_NAME`, and wire `permissions: contents: write` + a `production` Environment.
  None of these recur per merge, but every one is load-bearing for a build that notarizes, doesn't
  infringe the trademark, and actually releases.
- **Steady-state effort, stated honestly with the l10n tax folded in:** **~5–15 min of PR review** when no
  swept file moves; **+10–20 min and a `genstrings` re-run** whenever a sync touches one of the ~18
  trademark-swept `src/*.swift` files or the `.strings` files (a *baseline* recurrence, not a rare edge case
  — `ensure_generated_files_are_up_to_date.sh` hard-fails on any uncommitted regenerated diff, §4.5); and only
  a rare upstream refactor of `src/pro/` internals costs ~30–90 min, with the merge conflict + test making a
  wrong resolution impossible to ship. **Plus a separate periodic-overhead bucket** (yearly cert/notarization
  renewal, per-Sparkle-bump helper re-sign — §4.6), independent of merge cadence. The unqualified "5–15 min"
  number describes only the no-swept-file-moved cold path; do not read it as the all-in steady state.

### Decision summary

| Decision | Choice | One-line rationale |
|---|---|---|
| **Git model** | **Merge** upstream release tags into `master` (not rebase / patch-queue) | The patched lines are dormant upstream, so a rebase's linear-history benefit buys nothing while multiplying replay cost; merge surfaces a chokepoint collision exactly once, loudly. |
| **Patch mechanism** | **3 small body-suppress edits in 3 cold files** (`computeState()→.pro`; `syncLicenseCookie` + `AppCenterCrash.init` bodies wrapped in `if false { … }`); leave `src/pro/` intact | One edit at the single state-producer opens every gate; **zero per-merge edits** to hot (`App.swift`, `project.pbxproj`) or warm (UI) files; fails loudly (compile break) on a *signature/enum* refactor — a *silent semantic* relock (new enum case, gate re-pointed off `state`, producer moved) compiles clean and is caught only by the §4.4 behavioral guards + the §6.2 gate-consumer review, not the compile (§2). (The de-paywall edits themselves need zero pbxproj edits, period; the anti-relock test is appended to an already-membered file so it adds none either.) |
| **Identity approach** | **Overlay in fork-owned / content-overwritten files** — commit `config/local.xcconfig`, replace `README.md`/`app.icns`, repoint/remove `.github/FUNDING.yml`, edit ~3 dormant `Info.plist` lines; let the `DOMAIN` cascade repoint everything else | Identity diff avoids files upstream churns; `base.xcconfig`/`Endpoints.swift`/`project.pbxproj` stay untouched. |
| **CI trigger** | **Scheduled cron** (`upstream_sync.yml`) opens a reviewable sync PR, authored with a workflow-re-triggering `SYNC_BOT_TOKEN` (NOT the default `GITHUB_TOKEN`); release fires on merge to `master` via the existing `ci_cd.yml` | No upstream cooperation needed; a human gates each release. **Two BLOCKING durability requirements (§4.2):** (1) the bot token must re-trigger checks or the PR gate never fires; (2) prefer an EXTERNAL scheduler over the in-repo `schedule:`, which GitHub disables after 60 days of repo inactivity — pair with a two-trigger liveness alert. |
| **Release gate** | **Mandatory bootstrap re-architecture of `ci_cd.yml`** — add `pull_request:` trigger, gate all release-side steps under `if: github.event_name=='push'`, PLUS a separate fork-owned `guard.yml` on `pull_request` — and Guard B (relock) + Guard C (conflict-marker) greps as the FIRST steps of `ci_cd.yml`'s push job — before `run_tests.sh`/`update_appcast.sh`(Sparkle sign)/`semantic-release`(tag push)/`action-gh-release` | First-class deliverable, not a footnote: upstream's `ci_cd.yml` is push-only and the sole workflow, so the guards must be re-wired to gate *pre-merge*; the in-`ci_cd.yml` greps (placed FIRST, not merely before `action-gh-release` — which runs after the tag is pushed, §4.4) + separate `guard.yml` make "a relock or conflicted tree can never ship — the job aborts pre-tag-push" robust to a missing/misconfigured trigger (§4.2/§4.4). Note the gate consumers aren't unit-testable, so a per-release built-app feature-unlock check is also required (§4.4). |
| **Maintenance off-ramp** | **Pre-committed trip-wire to abandon tracking** if the chokepoints churn repeatedly (§0.1); plus a maintainer-disengagement posture (§0.2) | A low-effort tracked fork has a defined failure point; when the 3-edit patch stops being cheap, fall back to excision (`PLAN-republish-free.md`) or pin to pre-paywall `v10.12.0` rather than fighting every merge. A lapsed maintainer degrades to "stale, not broken" (§0.2). |

**Realistic all-in steady-state effort (read this, not just the "5–15 min" headline):** a typical sync is
**~15–35 min** once the l10n tax is folded in (PR review + any "keep ours" identity/CI conflicts + a
`genstrings` re-run whenever a swept file moved + the per-release feature-unlock acceptance check, §4.4);
a rare chokepoint refactor is **~30–90 min**; and a **separate periodic-overhead bucket** (quarterly
cert/notarization/key/token review, per-Sparkle-bump helper re-sign — §4.6) sits outside the per-merge clock.
The bare "5–15 min" is only the cold path with no swept file moved.

---

## 0. Why continuous tracking, and why NOT full excision

> **Why continuous tracking at all (vs. lazy on-demand resync) — a conscious cost decision.** This fork
> carries **zero unique feature commits**: per `PLAN-republish-free` §B, the only delta from upstream IS the
> paywall removal. So the fork gains nothing of its own from upstream — it tracks purely to *inherit*
> upstream's bug-fixes, security fixes, and macOS-compatibility work. That makes a lighter posture
> defensible: **resync only when upstream ships something the owner actually wants**, skipping the daily
> cron + PR-gate + `SYNC_BOT_TOKEN` + `guard.yml` apparatus entirely and paying a larger one-off re-strip
> cost occasionally. This plan **chooses continuous tracking anyway**, for one reason: **unattended pickup of
> security/bug fixes.** A window-switcher that uses private SkyLight/AX APIs and ships a Sparkle auto-updater
> is exactly the kind of app where a silently-skipped upstream security fix is a real user-harm risk, and a
> human-driven "resync when I notice something" loop reliably drifts. The standing operational cost (the §4.6
> credential bucket, the cron-durability machinery, the macOS CI minutes per sync) is the conscious price of
> *not* having to remember to look. **If the owner does not value unattended fix-pickup, the lighter
> on-demand posture is legitimate** — in that case, pin to pre-paywall `v10.12.0` (§0.1 option 2) or run the
> one-shot excision (`PLAN-republish-free.md`) and resync by hand. The rest of this plan assumes the
> continuous-tracking choice has been made deliberately.

### Why NOT full excision (the merge-surface argument)

[`docs/PLAN-republish-free.md`](PLAN-republish-free.md) §B recommends **Strategy 2 — full excision**
(delete `src/pro/`, untangle every consumer). That is the right call for a *one-and-done* republish:
the end-state is clean, with no dead paywall code in the tree. But it is the **wrong** call for a fork
that must merge upstream forever, for one concrete reason rooted in the churn data:

- **`alt-tab-macos.xcodeproj/project.pbxproj` is the single most merge-hostile file in the repo**:
  240 commits all-time, 10 since v11.0.0, and ~99 lines that reference `pro/`, `License`, `ProFeature`,
  or `PreferenceDefinition`. Deleting `src/pro/` means deleting all ~99 of those build-file / group /
  Sources entries — and *every* upstream pbxproj change (it churns roughly monthly) would then collide
  with our deletions.
- **`src/App.swift` is the wiring spine** (5 commits since v11.0.0; historically the hottest source
  file). Excision requires severing the license fan-out (≈448–460), the `onAction`/`onAppLaunchComplete`
  hooks (≈428–429), the Day-1 first-launch entanglement (≈206–207), and the custom-URL activate handler.
  Every one of those edits sits on a high-traffic file.
- Excision also drags in the warm upsell-UI files (`Menubar.swift`, `SettingsWindow.swift`,
  `Preferences.swift`), each recently touched.

### 0.1 Off-ramp — when to abandon tracking (pre-committed trip-wire)

This plan's whole economic case is that the 3-edit patch lands on dormant lines and stays cheap. That
premise can degrade. **Define the exit now, before it's needed**, so a deteriorating upstream doesn't quietly
turn the "5-minute review" into a recurring fight:

- **Trip-wire A — repeated chokepoint churn.** If upstream refactors `computeState()` / the chokepoint
  signatures so the de-paywall patch must be re-applied by hand on **≥3 syncs within a rolling 12 months**,
  the dormancy premise (§1) has failed for this fork's lifetime. **Make this tally auto-observable, not a
  manual count:** when a sync's conflict touches a chokepoint file, the runbook (§6.2 step 4) labels that PR
  `chokepoint-refresh` (in addition to `sync,conflict`), so the trip-wire is a single query rather than a
  memory exercise:
  `gh pr list --state merged --label chokepoint-refresh --search 'merged:>=<12-months-ago>'` — if it returns
  ≥3, the trip-wire has fired. **Auto-apply the label from CI, don't rely on the human remembering:** the
  per-sync chokepoint-churn count (§1, measured-signal note) is nonzero exactly when a chokepoint file changed
  in the merge range, so have `guard.yml`/the sync workflow `gh pr edit --add-label chokepoint-refresh` when
  that count > 0 (or when `git diff --name-only --diff-filter=U` shows a chokepoint conflict). The manual
  §6.2-step-4 label is then a backstop, not the primary mechanism — trip-wire A's tally cannot be defeated by
  a forgotten label.
- **Trip-wire B — structural `src/pro/` reorg.** If a single upstream release moves/renames `src/pro/` such
  that the patch no longer applies and the conflict spans **>1 chokepoint file**, or if any sync newly couples
  a *hot* file (`App.swift`, `project.pbxproj`) into the de-paywall surface.
- **Trip-wire C — commercial-surface expansion.** If the periodic re-audit (§6.2) finds upstream has added a
  NEW gate/endpoint/telemetry path the current 3-edit + 2-test + 1-grep target does not cover.
- **Trip-wire D — functional / compatibility-breaking sync (NOT a paywall event).** The fork's job is not
  only "keep Pro free" but "keep the app working" across upstream's normal functional evolution — and the
  Guards A/B/C + the §4.4 feature-unlock check prove only that *Pro is free*, **not** that the app still
  launches and works on the supported macOS range. Trip this branch when a merge touches any of:
  - **`MACOSX_DEPLOYMENT_TARGET`** (`config/base.xcconfig:5`, currently `10.13`; drives
    `LSMinimumSystemVersion` via `Info.plist:32-33` and Sparkle's `minimumSystemVersion`) — a raised macOS
    floor changes who can run/auto-update the fork;
  - **`Info.plist` permission/entitlement keys** (a new `NS*UsageDescription`, a new entitlement, a
    hardened-runtime change) — affects Gatekeeper/notarization and first-run permission UX;
  - **`PreferencesMigrations.swift`** (a new migration step) — can interact with the §3.1(b) `remembered*`
    migration if the fork reused an existing bundle id;
  - **a major upstream version bump** (e.g. v11→v12) that the frozen `v100.0.0` fork offset (§4.3) must still
    present sanely to users and to Sparkle's numeric ordering.
  This is a normal, expected event for a 240+-commit-spine app; it is NOT an off-ramp to abandon tracking by
  itself — it is a flag to run the §6.2 compatibility branch (smoke/launch test on the macOS floor, system-
  requirements review, and an explicit owner go/no-go on a major bump) before releasing. It only escalates to
  a strategy change if a compatibility break is one the fork cannot reasonably carry.

**On any trip-wire, switch strategies** rather than absorbing the cost merge-after-merge:
1. **Fall back to excision** — execute `docs/PLAN-republish-free.md` (full `src/pro/` deletion) once, accept
   the one-time cost, and thereafter track upstream against the excised tree; OR
2. **Pin to pre-paywall `v10.12.0`** (commit `317a485b`, the last tag with no paywall — see `docs/AUDIT.md`
   §1) and cherry-pick only the upstream fixes the fork actually wants. This trades post-v11 features for a
   zero-paywall base, eliminating the re-strip loop entirely.

Reaching a trip-wire is the explicit owner-decision point; until then this plan's inert-patch strategy stands.

### 0.2 The OTHER off-ramp — maintainer disengagement (human-availability assumption)

§0.1 handles a deteriorating *upstream*. The loop has no off-ramp for a lapsed **maintainer** — yet every
gate in this plan (PR review, conflict resolution, the per-release feature-unlock acceptance check) assumes a
human shows up. State the assumption and a posture for when it fails:
- **The whole loop degrades gracefully to "no new releases," not to "a broken/relocked release."** Because
  the release fires only on a human-merged PR (§4.2) and Guards A/B/C fail-closed (§4.4), a disengaged
  maintainer simply means sync PRs pile up unmerged and the last good release keeps serving via Sparkle —
  the fork goes *stale*, it does not ship a regression. This is the intended safe-failure mode; say so.
- **Escalating liveness alert.** The §4.2 liveness alert (no sync PR in ~45 days / oldest open PR > ~14 days)
  is also the disengagement detector — wire it to escalate (e.g. notify a backup owner) rather than silently
  re-open the same issue.
- **Document "buildable from source by a successor."** Keep the bootstrap (§6.1) and runbook (§6.2) complete
  enough that a new maintainer can clone the fork and cut a release without tribal knowledge — the GPL source
  is already public (§5), so the project can outlive any single owner. Note that the Sparkle private key and
  signing cert are the one piece a successor cannot reconstruct (§4.6); a true hand-off must transfer those
  secrets, or the successor ships under a new identity (a fresh install for users).

A thin **leave-`src/pro`-inert** patch (this plan) touches `project.pbxproj` **zero** times *per merge*,
`App.swift` **zero** times *per merge* (one one-time cold-line `repository` repoint at bootstrap — §3.5),
and the warm UI files **zero** times. The dead paywall code physically remaining in the
tree is the *price we happily pay* to keep the recurring merge a 5-minute review instead of a recurring
fight with the two hottest files in the project. (NB: `docs/AUDIT.md` §5/§6 recommend the *opposite* —
full deletion of `src/pro/` — because that audit optimizes for a clean one-shot end-state, the same goal as
`PLAN-republish-free.md`. The leave-`src/pro`-inert strategy is **this plan's** synthesis for the
*tracked-fork* goal, not a recommendation carried over from the audit; the audit's own churn data — not its
conclusion — is what supports it.) For the tracked-fork goal, leaving `src/pro/` inert is therefore not a
compromise but strictly superior, even though it diverges from the audit's deletion recommendation.

---

## 1. Merge-conflict risk (churn analysis)

**Decisive fact:** the entire paywall — `src/pro/`, the `PreferenceDefinition` read-gate, the `api/`
files, and the `DOMAIN`/signing identity edits in `config/` — was introduced by lwouis in **one commit,
`9147a4a8` / v11.0.0** ("feat: introducing alt-tab pro!"). In the **34 commits** upstream has shipped
since (through HEAD `9fadf36b` / v11.3.0), the four chokepoint files have had **zero** subsequent edits.
Verified with git:

```
$ git rev-list --count v11.0.0..HEAD                                   # 34
$ git rev-list --count v11.0.0..HEAD -- src/pro/license/LicenseManager.swift     # 0
$ git rev-list --count v11.0.0..HEAD -- src/pro/ProFeature.swift                 # 0
$ git rev-list --count v11.0.0..HEAD -- src/preferences/PreferenceDefinition.swift # 0
$ git rev-list --count v11.0.0..HEAD -- src/pro/scheduling/ProTransitionManager.swift # 0
```

Pickaxe (`-S`) on the exact tokens `isProLocked`, `attemptUse`, `isFreePassSessionActive`,
`freeEquivalent` returns only the introducing commit for those *files*. The two later commits that move
those tokens anywhere in the tree (`60cca89b`, `3059dc23`, both 2026-05-28) touch only **consumers**
(`src/switcher/ShortcutAction.swift`, `TilesView.swift`) and one comment line in `SettingsWindow.swift`
— never the chokepoint definitions. A patch confined to those four cold files therefore lands on lines
upstream has never re-touched.

The hazards are **not** the chokepoints; they are the hot/warm files a deletion-based approach would be
forced to edit:

| File | All-time | Since v11.0.0 | Heat | Role / patch disposition |
|---|---:|---:|---|---|
| `src/pro/license/LicenseManager.swift` | 1 | **0** | **cold** | **Primary chokepoint.** `computeState()` (176-190) is the single state producer; `isProLocked` (67-72), `isProAvailable` (62). **PATCH HERE.** |
| `src/pro/ProFeature.swift` | 1 | **0** | **cold** | Hard-gated runtime features via `attemptUse()` (74-83). Goes inert via the flip — no edit needed. |
| `src/preferences/PreferenceDefinition.swift` | 1 | **0** | **cold** | Degradable-prefs gate `read()` (32-44). Inert via the flip — the `guard … isProLocked` (line 34) is false, so `read()` returns the user's *stored* value unrestricted (the gate opens; Pro values become selectable — it does not auto-seed them). |
| `src/pro/scheduling/ProTransitionManager.swift` | 1 | **0** | **cold** | Nag scheduler. Never arms once state is `.pro` — no edit needed. |
| `src/pro/license/LicenseCookie.swift` | 1 | **0** | **cold** | `syncLicenseCookie()` writes a cookie on `alt-tab.app`. **PATCH** (1 line) to silence it. |
| `src/vendors/AppCenterCrashes.swift` | 1 | **0** | **cold** | `AppCenterCrash.init()` starts AppCenter telemetry (line 20). **PATCH** (1 line) so it never starts. |
| `config/base.xcconfig` | 20 | **0** | **cold** | Bundle id (:4), `DOMAIN`/`API_DOMAIN` (:20-21). Dormant. **Do not edit** — override via `local.xcconfig`. |
| `config/release.xcconfig` | 9 | **0** | **cold** | `CODE_SIGN_IDENTITY` (:5). Override via `local.xcconfig`. |
| `Info.plist` | 23 | **0** | **cold** | `NSPrincipalClass` (key:36/value:37 — do NOT edit, §3.4), `SUPublicEDKey` (key:61/value:62 — edit value), `Domain`/`ApiDomain` (key:75/value:76, key:77/value:78), URL scheme. Only the `SUPublicEDKey` value is edited for identity — merge-safe (the domains repoint via the xcconfig cascade, no Info.plist edit). |
| `src/api/Endpoints.swift` | 1 | **0** | **cold** | All URLs derived from `DOMAIN`/`API_DOMAIN`. Repoints via cascade — no edit. |
| `src/api/Secrets.swift` | 1 | **0** | **cold** | Reads `AppCenterSecret` from bundle. Dead once telemetry off. No edit. |
| `src/Menubar.swift` | 3 | 2 | **warm** | "Get Pro"/"My Account" items, badge. Goes quiet via the flip. **Do not edit.** |
| `src/preferences/Preferences.swift` | 156 | 2 | **warm** | `effective*` getters read through the gate; auto-return Pro values once flipped. **Do not edit.** |
| `src/preferences/settings-window/SettingsWindow.swift` | 14 | 2 | **warm** | Upgrade button/tab, Pro badges. Stays hidden via the flip. **Do not edit.** |
| `.github/workflows/ci_cd.yml` | 20 | 1 | **warm→hot (fork-owned)** | Sole CI workflow. Fork must own it; accept manual reconciliation on upstream CI changes. |
| `src/App.swift` | 251 | 5 | **hot** | Wiring spine. Paywall fan-out becomes inert via the flip. **No per-merge edit.** ONE one-time cold-line bootstrap edit: `repository` (line 16) → fork URL (GPL §6 source pointer — §3.5). |
| `alt-tab-macos.xcodeproj/project.pbxproj` | 240 | 10 | **hot** | Most merge-hostile; ~99 pro-references. Leaving `src/pro/` in place keeps this at **0** per-merge edits, and the anti-relock backstop adds none (it lives in the already-membered `LicenseManagerTests.swift`). **Do not edit per merge.** |

**Verdict:** A thin patch confined to the four cold chokepoint files (plus optional cold identity edits)
stays merge-clean indefinitely. Deletion would make `project.pbxproj` the #1 conflict source. The
churn data unambiguously supports the leave-`src/pro`-inert strategy.

> **Make the dormancy premise a MEASURED signal, not a one-time assertion.** This whole plan's economics
> rest on "the chokepoint files stay dormant upstream" — true through v11.3.0, but it can silently stop being
> true. Turn it into a per-sync number surfaced ON the sync PR: have CI (or the sync workflow) run
> `git rev-list --count <last-synced-tag>..<new-tag> -- src/pro/license/LicenseManager.swift src/pro/ProFeature.swift src/preferences/PreferenceDefinition.swift src/pro/scheduling/ProTransitionManager.swift src/pro/license/LicenseCookie.swift src/vendors/AppCenterCrashes.swift`
> and post the count as a PR comment / check. A nonzero count is the early warning that dormancy is eroding
> (and feeds §0.1 trip-wire A) — surfaced before the maintainer resolves, not discovered as a surprise
> conflict. This converts the load-bearing premise from "we assert it holds" to "we measure it every sync."

---

## 2. The minimal de-paywall patch

### Mechanism: force `LicenseManager.computeState()` to return `.pro`

There is exactly **one** place in the codebase where a "real" `LicenseState` is produced from data:
`LicenseManager.computeState()` (`src/pro/license/LicenseManager.swift:176-190`). Every entry point
that sets live state routes through it:

- `initialize()` → `state = computeState()` (line 92), called once at launch from `App.swift:~460`.
- `refreshState()` → `computeState()` (line 100), called by Menubar/SettingsWindow before reading `state`.
- The only network-driven reassignment (`revalidateWithServer`, line 223) also calls `computeState()` —
  and it is itself unreachable, early-returning unless a keychain license key exists (line 210), which
  never happens in a free build.

Because `isProAvailable` (line 62) and `isProLocked` (lines 67-72) are pure functions of `state`, and
`ProFeature.attemptUse()` / `PreferenceDefinition.read()` / `ProTransitionManager` all consult them,
**one edit at `computeState()` opens every gate in the tree simultaneously** — no need to touch the
four-way chokepoint funnel individually.

**Why this beats the alternatives:**

- **vs. editing `isProLocked → return false`:** `isProLocked` alone leaves `isProAvailable` reading
  from `state` (still `.trialExpired`), so `ProFeature.attemptUse()` line 75
  (`if LicenseManager.shared.isProAvailable { return true }`) would *not* short-circuit; you'd also have
  to patch `attemptUse` and `LicenseState.isProAvailable`. Forcing `state` is strictly smaller (1 edit
  vs. 2-3).
- **vs. a `#if FREE_BUILD` compilation flag:** that adds a `SWIFT_ACTIVE_COMPILATION_CONDITIONS` line in
  an identity-bearing xcconfig plus `#if` blocks — more files, more conflict surface. The single-line
  return is smaller and equally cold.
- **Fails loudly if upstream refactors the SIGNATURE:** `computeState()` returns the non-optional
  `LicenseState` enum. If lwouis renames the enum, splits it, or changes the signature, the forced
  `return .pro` stops compiling — a hard build break the republish pipeline catches immediately, rather than
  silently re-locking. This fail-closed-to-the-fork property is exactly what the perpetual-rebase workflow
  wants.

> **Scope this property honestly (it is narrower than "fails loudly, period").** The compile-break catches
> only **signature/enum refactors** of `LicenseState`/`computeState`. It does NOT catch a *silent semantic
> relock* that still compiles cleanly: a NEW `LicenseState` case, `isProAvailable`/`isProLocked` being
> rewritten to consult something other than `state`, a per-feature or server-driven entitlement check added
> alongside the gate, or the live-state producer being **moved** out of `computeState()`. Those compile fine
> and would re-arm the paywall. They are caught — if at all — only by the **behavioral guards** (§4.4), and
> even Guard A is structurally limited to `LicenseManager`-level behavior (`ProFeature` /
> `PreferenceDefinition` / the gate consumers are NOT in the `unit-tests` target). The backstop for this class
> of relock is therefore the §6.2 **manual-review step**: on any sync that touches
> `ProFeature`/`PreferenceDefinition`/`ShortcutAction`/`TilesView` (the gate consumers, which upstream
> demonstrably churns — `60cca89b`/`3059dc23`), the reviewer MUST confirm the gates still consult `state`.

**Do NOT individually edit `isProLocked`, `ProFeature.attemptUse`, or `PreferenceDefinition.read`** —
they become inert automatically once `state == .pro`:
- `isProLocked` → `false` (line 69, the `.pro` case).
- `isProAvailable` → `true` → `attemptUse()` returns `true` at line 75 before consulting `ProTransitionManager`.
- `PreferenceDefinition.read()` → the `guard … isProLocked` at line 34 is false, so it returns the
  user's stored value **unrestricted**. The gate simply *opens* — Pro values become freely selectable and
  are never downgraded to the free equivalent. (It does not auto-set prefs to Pro; it stops forcing them
  to Free.) Zero edits.

Editing those three adds three diff hunks for no behavioral gain and three more future collision points.

> **Build-warning caveat (verified — applies to all three edits):** `config/base.xcconfig:7` sets
> `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`. A `return` placed *above* live code emits a "code after 'return'
> will never be executed" warning, which becomes a **build error**. **Therefore do NOT use a bare early
> return — wrap the original body in `if false { … }`** (so it is syntactically reachable, not flagged)
> and put `return .pro` after it. This keeps each edit to a single small hunk that survives upstream edits
> to the dead body. The per-edit code below shows the safe form explicitly.

### Edit 1 (PRIMARY — cold): force the gate open

**File:** `src/pro/license/LicenseManager.swift` (cold: 1/0). **Location:** body of `computeState()`
(signature at line 176; first body statement at line 177).

> **The naïve form below DOES NOT COMPILE.** Because `base.xcconfig:7` sets
> `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, a bare `return .pro` placed *above* the existing body emits
> "code after 'return' will never be executed" → a build error. The illustrative-only naïve form is:
>
> ```swift
> // ILLUSTRATIVE ONLY — will NOT build (warning-as-error on the dead code below):
> func computeState() -> LicenseState {
>     return .pro
>     if keychain.value(account: Self.keychainKeyAccount) != nil { ... }   // <- "code after return" → error
>     return computeTrialState()
> }
> ```
>
> **Ship the `if false { … }` wrap instead** (single hunk, no unreachable-code warning, survives upstream
> edits to the wrapped body):
>
> ```swift
> func computeState() -> LicenseState {
>     // alt-tab-free [depaywall]: paywall neutralized at the single live-state producer — see docs/AUDIT.md
>     if false {
>         if keychain.value(account: Self.keychainKeyAccount) != nil { ... }
>         return computeTrialState()
>     }
>     return .pro
> }
> ```

**Diff: a few lines (one `if false {` open + one `}` close around the original body, plus the forced
`return .pro`).** This alone delivers all Pro features free, silences nags (see Edit 4), and kills license
revalidation network calls. Behaviorally it is the *only* required change. (`computeState()` is the single
live `LicenseState` producer: forcing it makes `isProLocked → false` (line 69), `isProAvailable → true`
(`LicenseState.swift:7`), `ProFeature.attemptUse() → true` (`ProFeature.swift:75`), and
`PreferenceDefinition.read()` return the stored value — all without further edits.)

### Edit 2 (side-effect — cold): silence the launch-time cookie write

**File:** `src/pro/license/LicenseCookie.swift` (cold: 1/0). `syncLicenseCookie(...)` is a free function
(signature at line 5; the `guard` body starts at line 6). With state forced to `.pro`, `App.swift`'s
`onStateChanged` hook still calls `syncLicenseCookie(state: .pro)` once on launch, writing a
`license=pro` cookie on the `alt-tab.app` domain (lines 13-21). Neutralize at the top of the function —
**do not** touch the `App.swift` call site (hot file).

> **Same warnings-as-error trap.** A bare `return` above the body trips "code after 'return'". Use the
> `if false { … }` wrap (or `#if false` around the body) so the diff is a single safe hunk:
>
> ```swift
> func syncLicenseCookie(state: LicenseState) {
>     // alt-tab-free [depaywall]: no license cookie on the upstream domain
>     if false {
>         guard let host = URL(string: Endpoints.website)?.host else { return }
>         ...
>     }
> }
> ```

**Diff: 2 lines (`if false {` + `}`).**

`revalidateWithServer` (`LicenseManager.swift:209`) is genuinely dead — it early-returns unless a keychain
license key exists (line 210), which never happens in a free build, so `validate`/`MachineFingerprint`
behind it never fire. **But `RemoteLicenseClient.activate` is NOT unreachable on a state argument:** the
custom-URL handler (`App.swift:465-481`) is gated **only** on the URL *scheme*
(`url.scheme == App.bundleIdentifier`, `url.host == "activate"`) — it is *not* gated on `LicenseState`.
Any `<bundleid>://activate?license_key=…` invocation (the scheme stays registered via
`Info.plist CFBundleURLSchemes = $(PRODUCT_BUNDLE_IDENTIFIER)`) reaches
`LicenseManager.shared.activate → RemoteLicenseClient` POST to `licenseApiBaseUrl` regardless of trial/pro
state — and that POST sends the **machine hardware UUID**: `RemoteLicenseClient.swift:18` includes
`"fingerprint": MachineFingerprint.get(...)`, and `MachineFingerprint.swift:13` reads `kIOPlatformUUIDKey`
(verified). So this is a **live hardware-identifier exfiltration surface, not dead code.**

> **DEFAULT (promoted) — neutralize the `activate` handler itself, independent of where `API_DOMAIN` points.**
> Add a 1-line early return in `handleCustomUrl` that drops/ignores the `activate` host (or returns before
> the `LicenseManager.shared.activate(...)` call). This kills the fingerprint POST **regardless of the
> `API_DOMAIN` value**, so it is robust even when feedback (§3.4) needs `API_DOMAIN` to be a *routable*
> fork-owned host. This is a *4th* `src/App.swift` edit — but `App.swift` line 16 is already a one-time
> bootstrap edit (§3.5), so this rides along as a one-time bootstrap neutralization (not per-merge), and
> unlike the `API_DOMAIN` repoint it does NOT depend on the feedback decision. **This plan adopts the handler
> neutralization as the default for the `activate` surface.**
>
> **An `API_DOMAIN` repoint alone does NOT make `activate` safe.** Pointing `API_DOMAIN` at a *non-routable*
> host happens to dead-end the POST, but (i) it is the WRONG default if feedback option (a) is chosen —
> §3.4(a) requires `API_DOMAIN` to be **routable and fork-owned**, and in that branch a crafted `activate`
> deep link POSTs the machine fingerprint to the *fork's own* backend (the non-routable option's protection
> silently re-arms into exfiltration to the fork); and (ii) it overloads one knob with two opposite jobs. So
> the `API_DOMAIN` value is a *feedback* decision (§3.4), and the `activate` fingerprint POST is closed
> separately by the handler edit above — **the two are now decoupled.**

> **WARNING — `API_DOMAIN` is shared with the feedback feature.** A *non-routable* `API_DOMAIN` also breaks
> `FeedbackWindow` (its `feedbackUrl` derives from `API_DOMAIN`), disabling a user-visible feature. Because
> the `activate` surface is now closed by the handler edit (above) regardless of `API_DOMAIN`, you are free to
> make `API_DOMAIN` *routable* for feedback (§3.4 option a) WITHOUT re-arming the fingerprint POST. Choose the
> `API_DOMAIN` value purely on the feedback decision (§3.4); do not pick "non-routable" believing it is what
> protects `activate` — the handler edit is.

Leaving `RemoteLicenseClient.swift`/`MachineFingerprint.swift` physically present otherwise keeps
`Endpoints.swift`, `Secrets.swift` at 0 edits.

### Edit 3 (telemetry — cold): don't start AppCenter

**File:** `src/vendors/AppCenterCrashes.swift` (cold: 1/0). `Info.plist:37` sets
`NSPrincipalClass = AppCenterApplication` (a vendored `NSApplication` subclass), and the app's `App` class
subclasses it (`App.swift:7`); but telemetry only activates when `AppCenterCrash()` is constructed in
`App.swift` and calls `AppCenter.start(...)` at line 20. Suppress the body of `init()` (signature line 8;
`super.init()` line 9; `AppCenter.start` line 20) rather than editing the hot `App.swift` call site or the
principal class:

> **Same warnings-as-error trap** (the registration + `AppCenter.start` lines 11-20 follow). Wrap them so
> the diff is a single safe hunk:
>
> ```swift
> override init() {
>     super.init()
>     // alt-tab-free [depaywall]: telemetry disabled — do not start AppCenter
>     if false {
>         UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
>         ...
>         AppCenter.start(withAppSecret: AppCenterCrash.secret, services: [Crashes.self])
>     }
> }
> ```

**Diff: 2 lines (`if false {` + `}`).** `App.appCenterDelegate = AppCenterCrash()` still runs but the
object does nothing. (Upstream already sets `AppCenter.networkRequestsAllowed = false` at line 14, so it
only networks at crash-confirmation time anyway; this hard-stops even that.) The class is `AppCenterCrash`
(not `AppCenterCrashes`). **Alternative — flipping `Info.plist` `NSPrincipalClass` (key:36/value:37) — is
NOT equivalent and is best avoided.** The principal class is **`AppCenterApplication`** (verified —
`Info.plist:37` value is `AppCenterApplication`, a vendored `NSApplication` subclass), and the app's own
`App` class *subclasses* it (`App.swift:7` — `class App: AppCenterApplication`); Cocoa resolves the running
`NSApp` to the `App` subclass. Swapping `NSPrincipalClass` to `NSApplication` would unload
`AppCenterApplication`, breaking the `App` subclass chain and its bridging-header coupling — not just
AppCenter. The `init`-suppress above keeps `NSPrincipalClass = AppCenterApplication` and the framework
loaded, only skipping `AppCenter.start()` — strictly safer. Prefer it; do **not** swap `NSPrincipalClass`.

### Edit 4 (nag scheduler): NOT NEEDED

Once `state == .pro`, `ProTransitionManager.onLicenseStateChanged` takes the `.pro` branch (cancels the
scheduler, emits `dismissAllProWindows`); `onSwitcherShown`'s Day-X ladder only arms in trial/expired
states; and the Day-1 first-launch welcome in `App.swift:~206-207`
(`if case .pro = LicenseManager.shared.state { return false }`) suppresses itself. The nag scheduler goes
silent purely from Edit 1. Leaving it unpatched keeps that cold file at 0 fork-edits.

### Edit 5 (upsell UI): leave it, do NOT edit

Hiding the Menubar "Get Pro"/"My Account" items, the Settings Upgrade tab, and the Pro badges would
require edits to `Menubar.swift` (warm 3/2), `SettingsWindow.swift` (warm 14/2), and `Preferences.swift`
(warm 156/2). With `state == .pro` the badge dot goes dark, the upgrade button/refresh paths report
unlocked, and ghost/lock styling doesn't render. The residual surface is purely cosmetic — a "Get Pro"
item may remain present-but-inert (clicking reaches an already-Pro state). **Cosmetics are not worth
touching three warm files on every merge cycle.** If the owner later insists on hiding it, do it as a
*separate, clearly-marked optional patch* the maintainer can drop when it conflicts — keep it out of the
core de-paywall diff.

### Shipped-build surface — confirm what actually ships (owner sign-off)

Two surfaces must be consciously verified/accepted before first release (neither is per-merge):

- **Release configuration strips DEBUG.** `run_tests.sh` and `build_app.sh` build **`-configuration
  Release`**, so `#if DEBUG` code does not ship — including `QAMenu`'s manual mock-Pro / nag pokes and
  `mockProUser()` (`#if DEBUG`). **Confirm the release pipeline never builds Debug**, so those test hooks
  cannot reach end users.
- **Residual inert-but-visible Pro surface.** With `state == .pro`, badges go dark and upgrade paths report
  unlocked, but a present-but-inert **"Get Pro" menubar item** (and similar) may remain visible. The owner
  must **consciously accept** this cosmetic residue OR fold in the optional Edit-5 UI-hide patch. (Note:
  `_test-support/Mocks.swift:133` hardcodes the upstream bundle id — this is **test-only, out of scope** for
  the shipped build; called out so a reader cross-checking `AUDIT.md` §5 isn't left wondering.)

### Patch summary

| # | File | Cold/Hot | Edit | Lines |
|---|------|----------|------|------:|
| 1 | `src/pro/license/LicenseManager.swift` (`computeState`, body at 177) | **cold** 1/0 | wrap body in `if false { … }`, then `return .pro` | **~3** |
| 2 | `src/pro/license/LicenseCookie.swift` (`syncLicenseCookie`, body at 6) | **cold** 1/0 | wrap body in `if false { … }` | **2** |
| 3 | `src/vendors/AppCenterCrashes.swift` (`init`, body after `super.init()` at 9) | **cold** 1/0 | wrap body (lines 11-20) in `if false { … }` | **2** |

**Total: 3 files, ~7 inserted lines — all in COLD files with 0 commits since v11.0.0. Zero edits to any
hot file (`App.swift`, `project.pbxproj`), zero edits to warm files (`Menubar.swift`,
`SettingsWindow.swift`, `Preferences.swift`, `ci_cd.yml`); `src/pro/` stays physically intact so
`project.pbxproj` is untouched by the de-paywall patch.** The `if false { … }` wrap (not a bare
`return` above live code) is mandatory under `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` (`base.xcconfig:7`).
Prefix all three commits `depaywall:` so they're trivially locatable
(`git log --oneline --grep='^depaywall:'`).

---

## 3. Identity & branding overlay (merge-stable)

**Design principle:** the fork's identity diff must live in files **upstream never edits** so merges
stay clean. The repo already provides the seam — `config/local.xcconfig` is `#include?`'d **last** in
both `config/release.xcconfig:21` and `config/debug.xcconfig:13`, is already pbxproj-referenced, is
already `.gitignore`'d (`.gitignore:20`) and untracked, and CI already regenerates it. Because xcconfig
"last assignment wins," anything set there overrides `base.xcconfig` **without touching `base.xcconfig`.**
Everything else is achieved by overwriting the *content* of a file whose pbxproj reference path is
unchanged, or by the `DOMAIN` cascade. **Net pbxproj edits for the whole overlay: zero.**

### 3.1 Bundle id + PRODUCT_NAME + DOMAIN + signing — commit `config/local.xcconfig`

These live in `base.xcconfig:3` (`PRODUCT_NAME`), `:4` (`PRODUCT_BUNDLE_IDENTIFIER`), `:20-21`
(`DOMAIN`/`API_DOMAIN`), and `release.xcconfig:5` (`CODE_SIGN_IDENTITY`).

**Recommendation: un-gitignore and commit `config/local.xcconfig`** as the single source of identity
truth — do **not** edit `base.xcconfig`/`release.xcconfig` in place:

```
PRODUCT_NAME = <ForkName>
PRODUCT_BUNDLE_IDENTIFIER = <com.fork.app>
DOMAIN = <fork.example>
API_DOMAIN = <fork.example/api>
CODE_SIGN_IDENTITY = Developer ID Application: <Fork Org> (TEAMID)
APPCENTER_SECRET =                 // empty — telemetry off
```

> **CI caveat (verified, lines 7-10):** upstream's `scripts/replace_environment_variables_in_app.sh` does
> `cat > config/local.xcconfig` (a truncating **overwrite**) writing BOTH `CURRENT_PROJECT_VERSION` AND
> `APPCENTER_SECRET = $APPCENTER_SECRET` — which would clobber the committed identity block on every CI run.
> **A naïve `cat >` → `cat >>` (append) is NOT enough:** the committed identity block above ALSO sets
> `APPCENTER_SECRET =`, so an append yields **two `APPCENTER_SECRET` lines**. (xcconfig is last-wins, so the
> CI-appended empty value would win — harmless only because telemetry is off, which makes the
> "append won't collide" framing wrong, not safe.) **Fix robustly — do one of:**
> - **(preferred) Make the script write ONLY `CURRENT_PROJECT_VERSION` and append it** — drop its
>   `APPCENTER_SECRET` line entirely (telemetry is off, so the secret is unused). `CURRENT_PROJECT_VERSION`
>   is not in the committed block, so a single appended line is collision-free. OR
> - **Write `CURRENT_PROJECT_VERSION` into a separate `version.xcconfig`** that `local.xcconfig` `#include`s,
>   leaving the committed identity block untouched.
>
> (The fork rewrites CI anyway — §4.)

The cascade does most of the rest: `Info.plist` already pulls `$(PRODUCT_BUNDLE_IDENTIFIER)`,
`$(PRODUCT_NAME)`, `$(DOMAIN)`, `$(API_DOMAIN)` as build variables (`:7,:9,:76,:78`), and
`Endpoints.swift:4-5` reads `Domain`/`ApiDomain` from the bundle at runtime. **The `local.xcconfig`
lines rebrand the bundle id, app name, URL scheme, license/website/feedback/appcast hosts, AND the
keychain/UserDefaults suite names (`LicenseManager.swift:4-5` derive from `App.bundleIdentifier`) in one
shot — with zero edits to `Info.plist`, `Endpoints.swift`, or `base.xcconfig`.** Note the keychain-suite
consequence: pick the fork's bundle id **once and freeze it**, or every user's stored state orphans on the
next id change.

> **OWNER DECISION (one coherent call, not two scattered caveats) — bundle id + the `remembered*` data-loss
> scenario.** §3.1 says "freeze the bundle id once"; §5 says "fresh install, no migration." These are two
> facets of the SAME decision — resolve it explicitly:
> - **(a) Mint a FRESH bundle id (recommended; simplest).** The fork is a separate app with a clean
>   `UserDefaults`/keychain domain. **Consequence to accept and disclose:** existing AltTab users' prefs are
>   NOT inherited — it is a fresh install, not an in-place upgrade. No migration code. This is the default
>   this plan assumes.
> - **(b) Reuse an existing bundle id (only if deliberately upgrading installed AltTab users in place).**
>   Then a **one-time migration is REQUIRED**, because the leave-`read()`-intact de-paywall strategy (§2)
>   never restores Pro selections that the *paywalled* build downgraded: users who passed trial expiry have
>   their real Pro index parked in `proTransition.remembered*` keys (in the `.license` UserDefaults suite),
>   and `read()` returning the *stored* (downgraded) value silently keeps the free equivalent. Ship a
>   one-shot migration that, before first read, copies each `proTransition.remembered<Key>` index back to its
>   base key and clears the `proTransition.*` keys. (This is the same migration `AUDIT.md` §6/Risk flags.)
>
> Pick (a) or (b) at bootstrap; do not leave it implicit. Either way the choice must be frozen — a *later*
> bundle-id change orphans state regardless.

> **`local.xcconfig` alone is NOT enough — `ci_cd.yml` hardcodes `APP_NAME` (verified):** `ci_cd.yml:19`
> sets `APP_NAME: AltTab`, and `build_app.sh` checks `$APP_NAME.app/Contents/MacOS/$APP_NAME` while
> `package_and_notarize_release.sh` / `scripts/update_appcast.sh:8` zip/reference `$APP_NAME-$version.zip`.
> The built bundle name comes from `PRODUCT_NAME` (xcconfig). So setting `PRODUCT_NAME=<ForkName>` but
> leaving `APP_NAME=AltTab` makes `build_app.sh`'s existence check fail and the appcast/zip names mismatch
> the artifact. **`ci_cd.yml` is fork-owned (§3.5) — set its `APP_NAME` env equal to `PRODUCT_NAME`.**
> `PRODUCT_NAME` also does *not* touch the hardcoded `"AltTab"` UI strings — see the §3.2 string sweep.

> **Rejected — Option B (new `config/fork.xcconfig` + an `#include` appended to `base.xcconfig`):** that
> appended line is the only edit inside a file upstream *does* touch (20 commits), carrying a small
> recurring conflict risk on the tail of `base.xcconfig`. Option A has strictly zero edits to upstream
> files.

### 3.2 App name / icon (trademark)

- **Login Items origin string (re-sign resolves it — verify it).** `src/macos/LoginItem.swift:16` sets
  `AssociatedBundleIdentifiers = App.bundleIdentifier` precisely so System Settings → General → Login Items
  shows the app name rather than the **signer's Developer ID display name** ("Louis Pontoise" today, per the
  comment at `LoginItem.swift:14-15`). With the fork's own bundle id (§3.1) and the mandated fork re-sign
  (§3.3/§4.6), this resolves to the fork's identity automatically — but it is a *visible* origin/trademark
  surface, so add a bootstrap verification: after installing the fork build, open System Settings → Login
  Items and confirm it shows the **fork's** name/Developer ID, not "Louis Pontoise". (No code edit — this is
  a consequence of the bundle-id + re-sign, called out so it is checked, not assumed.)
- **Icon:** ships as a plain file `resources/icons/app/app.icns` (no asset catalog; only
  `Info.plist:18 CFBundleIconFile = app.icns` drives it), referenced in pbxproj by relative `path`.
  **Overwrite the bytes of `app.icns` and regenerate `app.iconset/*` in place** — the pbxproj path is
  unchanged, so **zero pbxproj edits**; git sees a binary blob change and any upstream icon change is a
  clean "both modified" the fork always resolves in its own favor.
- **`PRODUCT_NAME`** — handled by §3.1, **but it does NOT touch hardcoded brand strings.** `PRODUCT_NAME`
  only renames the bundle/`App.name`. **Verified counts (the plan elsewhere over-counts — correct them):**
  `grep -rn 'AltTab' src/ --include='*.swift'` returns **63 TOTAL hits**, but ~25 of those are comments /
  translator-note `comment:` strings that **do not render**; the actually-rendered surface is **~21
  `NSLocalizedString` literals containing "AltTab"** plus the l10n template. In
  `resources/l10n/Localizable.strings` there are **20 `AltTab` lines, of which 2 are `/* … */` comments → 18
  translatable entries** (replicated per `*.lproj`). A build with `PRODUCT_NAME=<ForkName>` still shows
  "AltTab" throughout the UI — exactly the trademark confusion §5 claims to avoid. **Required one-time string
  sweep,** classifying each hit (recurring but small merge surface on l10n + a few warm files thereafter):
  - **(i) User-visible non-`src/pro` `src/*.swift` literals to route through `App.name`** (verified examples):
    `Menubar.swift:43` (`About %@` — already uses `App.name`), `:52`, `:443`;
    `SettingsWindow.swift:304`; `AboutTab.swift:153` (`"You have used AltTab:"`);
    `AppearanceTab.swift:157`; `AppCenterCrashes.swift:62`; `PermissionsWindow.swift:36,:50`;
    `MoveToApplicationsFolder.swift:184`; `CustomRecorderControl.swift:110`; `FeedbackWindow.swift:100`
    (`"Help improve AltTab"`), `:239` (`"A new version of AltTab is available"`). Where a `%@`/`App.name`
    form already exists, prefer it so future renames are free (`App.name` is `App.swift:13`).
  - **(ii) `src/pro/*` literals that STILL render if any inert Pro UI is reachable** (verified): e.g.
    `ProPromptWindow.swift:12` / `UpgradeTab.swift:116` (`"AltTab Pro"`),
    `Day1WelcomeLetterWindow.swift:25-26`, `Day15ProactiveWindow.swift:23` /
    `Day15FullUpgradeWindow.swift:24`, `Day21ReminderPopover.swift:14`, `ProTransitionManager.swift:35`,
    `ProConversionCopy.swift:32,:39`. **DECISION REQUIRED:** §2/§5 tell the executor never to edit `src/pro`
    — so either (a) sweep these *despite* that rule (a deliberate, documented exception, accepting the
    `src/pro` merge surface), or (b) prove the inert-Pro UI is genuinely unreachable once `state == .pro`
    (the upsell windows are nag-scheduled, which never arms — but verify no other entry point renders them).
  - **(iii) NON-display literals that MUST NOT be renamed:** `PreferencesMigrations.swift:363` uses
    `"Screen showing AltTab"` as an OLD STORED preference-value KEY in a `migratePreferenceValue` map —
    renaming it breaks migration of existing users' `screensToShow` pref. (Note `MacroPreferences.swift:187`
    `.showingAltTab → NSLocalizedString("Screen showing AltTab")` is a *display* string and may be reworded,
    but the migration KEY at `PreferencesMigrations.swift:363` must stay literal.) Also leave `App.swift` log
    strings and any non-UI literals alone.
  - `resources/l10n/Localizable.strings` (and every `*.lproj` copy): the 18 translatable `AltTab` entries
    (2 of the 20 lines are comments). Note line 605 `"Screen showing AltTab"` mirrors the MacroPreferences
    display string, NOT the migration key — both happen to share the literal.
  - **Durable CI gate (recommended):** add a CI grep that fails if user-visible `"AltTab"` reappears in the
    swept `NSLocalizedString` literals, so the sweep doesn't silently regress on a future merge.
  - **CI gate consequence:** editing `src/*.swift` literals and the `.strings` files re-triggers
    `scripts/ensure_generated_files_are_up_to_date.sh` (regenerates l10n via `genstrings`; §4). Run
    `scripts/l10n/extract_l10n_strings.sh` and commit the regenerated `resources/l10n/*.strings` **before**
    pushing, or CI fails on the diff. The fork runner's Xcode/`genstrings` must match upstream's to keep
    this gate green.
- **Attribution (GPL-3 §5/§7 + trademark):** keep `LICENCE.md` byte-for-byte (never edit). Replace
  `README.md` with the fork's README, which **must** state: *"<ForkName> is a fork of
  [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos), © Louis Pontoise, licensed under
  GPL-3.0. This fork removes the Pro paywall; all features are free. Not affiliated with or endorsed by
  the original author."* Add the same credit to the in-app **About** tab (`AboutTab.swift` renders a
  `Website` hyperlink to `Endpoints.website`, which auto-repoints via the cascade).

### 3.3 Sparkle (auto-update)

- **EdDSA keypair:** generate a fresh one. **NOTE (verified): `vendor/Sparkle/bin/generate_keys` does NOT
  exist** — `vendor/Sparkle/bin/` ships only `sign_update`, because `vendor/scripts/update_sparkle.sh` step 10
  (line 191) deliberately drops `generate_keys`/`generate_appcast`/`BinaryDelta`. Obtain `generate_keys` by
  one of: (a) download the Sparkle 2.9.1 release tarball — the same `RELEASE_URL`
  (`https://github.com/sparkle-project/Sparkle/releases/download/2.9.1/Sparkle-2.9.1.tar.xz`)
  `update_sparkle.sh:14` uses — and run its bundled `bin/generate_keys`; (b) `brew install --cask sparkle`
  and use its `generate_keys`; or (c) temporarily un-drop `generate_keys` in `update_sparkle.sh` step 10.
  `SUPublicEDKey` is a literal `<string>` value (not a `$(VAR)`): the `<key>` is at `Info.plist:61`, the value
  at `:62`. **Write the public key to the value on `Info.plist:62`** (not the `<key>` on :61) — cold,
  merge-safe. Keep the **private** key in CI secrets (`SPARKLE_ED_PRIVATE_KEY`, consumed by
  `scripts/update_appcast.sh`).
- **Re-sign the bundled Sparkle helpers (one-time, MANDATORY for notarization):** the embedded
  `vendor/Sparkle/Helpers/Updater.app` and `vendor/Sparkle/Helpers/Autoupdate` are currently signed
  `Developer ID Application: Louis Pontoise (QXD7GW8FHY)` / `TeamIdentifier=QXD7GW8FHY` (verified with
  `codesign -dvv`). Apple notarization/Gatekeeper require **every nested Mach-O** to be Developer-ID-signed
  under a team consistent with the host app; a TeamIdentifier mismatch between the fork-signed `.app` and
  these lwouis-signed helpers causes notarization rejection or a Gatekeeper launch failure for end users
  (the `disable-library-validation` entitlement can mask it locally while notarization still rejects).
  **Action:** before first release, re-sign `Updater.app` + `Autoupdate` under the FORK's Developer ID
  (e.g. run `vendor/scripts/update_sparkle.sh` with the fork cert in the keychain / set the helper signing
  identity), re-commit them, and verify `codesign -dvv vendor/Sparkle/Helpers/Updater.app` shows the fork's
  TeamIdentifier. Re-do this on every Sparkle version bump. (See §4.0 — "reuse scripts verbatim" must NOT
  be read as "signing is untouched.")
  - **Where the helpers actually get embedded — `scripts/copy_sparkle_helpers.sh` (verified):** the build
    phase **"Copy Sparkle Helpers"** runs this script, which copies `vendor/Sparkle/Helpers/{Updater.app,
    Autoupdate}` into `Sparkle.framework/Versions/A/` inside the built `.app` and **re-seals
    `Sparkle.framework`** with the build's `CODE_SIGN_IDENTITY` (so `local.xcconfig`'s fork identity flows
    through automatically — no edit to this script). Critically, the script's own comment confirms it does
    **NOT** re-sign the nested `Updater.app`/`Autoupdate` — those keep their **vendor-time** signature. So the
    bootstrap re-sign of `vendor/Sparkle/Helpers/*` is exactly what determines the embedded helpers' team:
    if you skip it, this script embeds **lwouis-TeamID** helpers under a fork-TeamID framework — the precise
    notarization/Gatekeeper `TeamIdentifier` mismatch warned about above, with the copy site being
    `copy_sparkle_helpers.sh`.
  - **Post-build verification (REQUIRED):** after `build_app.sh`, run `codesign -dvv` on the
    `Sparkle.framework/Versions/A/Updater.app` **inside the built `.app`** (not just the vendored source
    copy) and confirm the fork's `TeamIdentifier`. Promote the parenthetical CI "TeamIdentifier-drift" check
    (§6.1 / below) to a **REQUIRED** gate that **fails the build** if any nested Mach-O's `TeamIdentifier` ≠
    `APPLE_TEAM_ID`.
- **Feed URL:** `Endpoints.appcastUrl = "\(website)/appcast.xml"` (`Endpoints.swift:7`, where
  `website = "https://\(domain)"`) — repoints via the `DOMAIN` cascade automatically; no code edit.
  **Precondition:** the fork must own a web host that actually serves `https://<DOMAIN>/appcast.xml` (or
  accept a `github.io` value for `DOMAIN` and CNAME a gh-pages branch). The Sparkle feed URL is fixed by
  the `DOMAIN` cascade, so a bare release-asset URL won't match unless `<DOMAIN>` serves `/appcast.xml`.
- **`appcast.xml` — the conflict trap (verified tracked):** `appcast.xml` is committed and contains
  upstream's EdDSA-signed release history. If the fork keeps signing into the same file, *every* upstream
  release and *every* fork release edits it → guaranteed conflicts, plus the fork would serve entries
  signed with lwouis's key its public key can't verify. This is **one coupled bootstrap change** with
  three parts that must all land together — removing the file alone breaks the build:
  1. **`git rm appcast.xml`** + add `/appcast.xml` to `.gitignore`, and publish the feed out-of-tree
     (gh-pages branch or a release asset).
  2. **Rewrite `scripts/update_appcast.sh`.** As shipped it edits an in-tree `appcast.xml`:
     `set -exu` (line 3) makes a missing file a HARD failure, and line 26
     (`sed -i '' -e "/<\/language>/r ITEM.txt" appcast.xml`) appends into the tracked file. The rewrite
     must (a) check out / fetch the gh-pages copy of the feed, append `ITEM.txt` there, and push it to the
     publish location; (b) fix the **enclosure URL** on **line 18**
     (`github.com/lwouis/alt-tab-macos/releases/download/...` → the fork's releases — also flagged
     §4.0/§4.3 as the single most safety-critical edit); and (c) fix the **`releaseNotesLink` on line 16**
     (`https://alt-tab.app/changelog-bare` → a fork URL or drop it).
  3. **Remove `'appcast.xml'` from the `@semantic-release/git` `assets` array in `release.config.js`**
     (lines 20-26 — currently `['changelog.md', 'appcast.xml', 'README.md']`). Otherwise semantic-release
     tries to commit the now-untracked file back every release. NOTE: `release.config.js` is upstream-tracked
     (so this is a small recurring conflict surface — flag it as "keep ours").

### 3.4 Endpoints + Secrets + telemetry

`Endpoints.swift` is cold and entirely derived from `Domain`/`ApiDomain`. Once `state == .pro`, the
checkout/account UI paths and the periodic revalidation are never invoked — but the `activate` POST is
**not** state-gated (it's reachable any time via `<bundleid>://activate`, see §2) and it **exfiltrates the
machine hardware UUID** (`RemoteLicenseClient.swift:18` → `MachineFingerprint.swift:13`, `kIOPlatformUUIDKey`),
so **handling the `activate` surface is required, not optional.** **The `activate` fingerprint POST is closed
by neutralizing `handleCustomUrl` (§2 default), NOT by where `API_DOMAIN` points** — decoupling the two so
that the feedback decision below cannot re-arm fingerprint exfiltration. `API_DOMAIN` is still *shared* with
the live feedback POST, and the choice of its value is purely a *feedback* decision (the routability tension is
about feedback working vs. not — the `activate` surface is handled separately). Per-URL disposition:

| URL (`Endpoints.swift`) | Consumer | Disposition |
|---|---|---|
| `licenseApiBaseUrl` :11 | `RemoteLicenseClient.activate/validate/deactivate` | `validate`/`deactivate` are dead (need a keychain key). `activate` is **NOT dead** — the `<bundleid>://activate` handler (`App.swift:474-481`) is scheme-gated, not state-gated, and POSTs the **machine hardware UUID** (`RemoteLicenseClient.swift:18`→`MachineFingerprint.swift:13`) here. **REQUIRED (default): neutralize `handleCustomUrl`** (drop the `activate` host) so the POST is dead *regardless of `API_DOMAIN`* — do NOT rely on a non-routable `API_DOMAIN`, which silently re-arms the fingerprint POST to the fork's own backend if feedback option (a) makes `API_DOMAIN` routable. |
| `checkoutUrl` :9, `accountUrl` :10 | nag scheduler / Upgrade UI | **Dead** (never armed / UI quiet). |
| `website` :6 | About tab, cookie | **Repoints** via `DOMAIN`. Automatic. |
| `supportUrl` :8 | `App.swift` (`supportProject` / Menubar "Support" item) | Derives from `website` (`= https://\(DOMAIN)/support`), so it repoints via the `DOMAIN` cascade to `https://<DOMAIN>/support`. **Owner decision (state it, don't leave implicit):** either (a) serve a real `/support` page on `<DOMAIN>`, or (b) the in-app "Support" affordance 404s. Note this is a *distinct* surface from `.github/FUNDING.yml` (the repo Sponsor button, §3.5) — both must be consciously pointed at the fork (or removed), or one silently keeps pointing at the upstream author. |
| `feedbackUrl` :12 | `FeedbackWindow` | **The one runtime POST that still fires** (user-initiated feedback). `FeedbackWindow.prepareRequest()` (line 445) POSTs JSON `{title, body, kind, debugProfile}` — `DebugProfile.make()` carries versions/settings/hardware — to a backend that owns the GitHub-issue rendering server-side. **A non-routable `API_DOMAIN` makes every submission fail (`showSubmitFailureAlert`, line 409): this DISABLES a user-visible feature, it is not dead code.** See the §3.4 decision below — pick a real option, don't default to non-routable here. |
| `appcastUrl` :7 | `SparkleDelegate.feedURLString` | **Recurring GET on every scheduled check** (`Info.plist` `SUEnableAutomaticChecks`, `SUScheduledCheckInterval=604800`), independent of license state. `SparkleDelegate` appends `version`/`macos`/`arch`/`lang` query params (`SparkleDelegate.swift:33-36`). Repoints via `DOMAIN` (§3.3). **If `<DOMAIN>` is not fork-owned and serving `appcast.xml`, update checks 404 or leak a coarse system profile to a third party.** |

**§3.4 decision — the `activate` fingerprint POST is closed independently of `API_DOMAIN`:**
- **`licenseApiBaseUrl` / the `<bundleid>://activate` POST** — closed by the §2 **`handleCustomUrl`
  neutralization** (drop the `activate` host), which kills the hardware-UUID POST *regardless of where
  `API_DOMAIN` points.* Do **NOT** rely on a non-routable `API_DOMAIN` for this: a non-routable host only
  dead-ends the POST as a side-effect, and that protection silently **re-arms** the moment feedback option (a)
  below makes `API_DOMAIN` routable (the crafted `activate` link then POSTs the fingerprint to the *fork's
  own* backend). **A routable `API_DOMAIN` alone does NOT make `activate` safe — the handler edit does.**
- **`feedbackUrl` / FeedbackWindow** — `API_DOMAIN` drives this; choose its value purely on the feedback
  decision below. Because `activate` is already neutralized at the handler, you may now make `API_DOMAIN`
  *routable* (option a) without re-opening any fingerprint surface. A non-routable host still **breaks the
  feedback feature** (every submit fails) — a user-visible regression, not dead-code cleanup. Pick **one**
  honestly and document it:
  - **(a) Stand up a fork feedback backend** at `API_DOMAIN` that accepts the `{title, body, kind,
    debugProfile}` POST and files/forwards issues. Keeps the feature; most work.
  - **(b) Rewrite `FeedbackWindow.submit`/`prepareRequest`** to build a prefilled
    `https://github.com/<fork>/issues/new?title=…&body=…` URL **client-side** and `NSWorkspace.shared.open`
    it (dropping the JSON POST + `debugProfile` attach). **Scope honestly: this is a REAL edit to a warm
    file** — the current code constructs no client-side GitHub URL and the backend owns issue rendering, so
    this is a rewrite of `FeedbackWindow.swift`, not a "small/localized" one-liner.
  - **(c) Hide the feedback entry point** entirely.
  Whichever you choose, the `activate`-POST fingerprint surface is **already** closed by the §2
  `handleCustomUrl` neutralization, independent of `API_DOMAIN` — the two decisions are decoupled.

`Secrets.swift` reads only `AppCenterSecret` from the bundle. **Telemetry kill:** set
`APPCENTER_SECRET =` (empty) in `local.xcconfig` (AppCenter init no-ops on an empty secret), reinforced by
Edit 3 (§2).

> **Owner acknowledgment — "no telemetry" means "telemetry disabled, SDK still linked," not "AppCenter
> removed."** This plan deliberately keeps `src/pro`/`src/vendors` physically present (the merge-surface
> argument, §0), so the AppCenter SDK — which is **End-of-Life** (`AUDIT.md` §1/§2/§6) — remains **linked
> into the binary but inert** (empty secret + Edit-3 `init` suppression + upstream's
> `networkRequestsAllowed = false`). A privacy-conscious user reading "no telemetry" should understand the
> SDK is not *excised*; it is *prevented from starting*. If the owner wants the EoL SDK fully out of the
> binary, that is the full-excision path (`PLAN-republish-free.md` / `AUDIT.md` §5), which this plan rejects
> for the tracked-fork goal. State this so "no telemetry" is not over-claimed. **Do NOT also swap `NSPrincipalClass` (`Info.plist` key:36/value:37).** The principal class is
**`AppCenterApplication`** (verified — `Info.plist:37` value, a vendored `NSApplication` subclass), and the
app's own `App` class *subclasses* it (`App.swift:7`); swapping to `NSApplication` would unload
`AppCenterApplication` and break the `App` subclass chain + bridging-header coupling, not just AppCenter.
Edit 3's `init`-suppress already achieves telemetry-off without that risk; they are not equivalent. Drop the
fork's CI use of `upload_symbols_to_appcenter.sh` and `update_website.sh`.

### 3.5 Identity overlay file set

**Fork-owned (upstream never touches → zero conflict):**
- `config/local.xcconfig` — un-gitignore + commit (`PRODUCT_NAME`, bundle id, `DOMAIN`, `API_DOMAIN`,
  `CODE_SIGN_IDENTITY`, empty `APPCENTER_SECRET`).
- `README.md` — full replacement with GPL-3 + fork attribution.
- Fork-owned CI workflow + rewritten `scripts/update_appcast.sh` / `replace_environment_variables_in_app.sh`.

**Upstream-tracked file that funnels money/identity to lwouis — repoint or remove (`AUDIT.md` §5):**
- **`.github/FUNDING.yml`** (verified: `github: lwouis`, `patreon: alt_tab_macos`, `ko_fi: alt_tab`, and a
  lwouis PayPal `hosted_button_id`). Left as-is, GitHub renders a **"Sponsor" button on the fork's repo that
  routes every donation to the author the fork just de-paywalled** — an identity/phone-home surface and a
  recurring conflict file (every upstream edit to it collides). **Bootstrap action:** either `git rm
  .github/FUNDING.yml`, or rewrite it to the fork's own sponsorship (or leave it empty). Add it to the §6.2
  "keep ours" recurring-conflict set alongside `ci_cd.yml` / `update_appcast.sh` / `release.config.js`.

**Content-overwrite by stable path (zero pbxproj edits, "fork always wins" on conflict):**
- `resources/icons/app/app.icns` + `app.iconset/*`.

**Tracked-file removal:** `git rm appcast.xml` + `/appcast.xml` in `.gitignore`; CI publishes the feed out-of-tree.

**Minimal in-place edits to COLD dormant lines (merge-safe):**
- `Info.plist:62` (`SUPublicEDKey` **value**; the `<key>` is on :61).
- `src/App.swift:16` — `static let repository = "https://github.com/lwouis/alt-tab-macos"` → the fork's
  GitHub URL. This is the **in-app GPL §6 corresponding-source pointer**: it is consumed by
  `AboutTab.swift:19` (the in-app "Source code" link) and `FeedbackWindow.swift:136` (`App.repository +
  "/issues"`). Left as-is, the fork's "Source code" link misdirects users to lwouis's paywalled tree
  rather than the fork's source — a GPL §6 compliance gap, not just cosmetics. This is the ONE cold-line
  `src/App.swift` divergence (the file is hot — 5 commits since v11.0.0 — but line 16 has not moved); it
  is a one-time bootstrap edit, not per-merge. Optionally relocate `repository` to a fork-owned file to
  zero out even that. Decide whether `FeedbackWindow`'s `/issues` should follow the same repoint.
- Optionally `FeedbackWindow.swift` `feedbackUrl` (only if no fork feedback backend — see §3.4 table).

**Do NOT edit:** `Info.plist:36/37` `NSPrincipalClass` (value = `AppCenterApplication`, which `App`
subclasses — see §3.4; swapping it is not equivalent to Edit 3, and breaks the `App` subclass chain).

**Untouched — DO NOT edit (cascade does the work):** `config/base.xcconfig`, `config/release.xcconfig`,
`src/api/Endpoints.swift`, `src/api/Secrets.swift`, `project.pbxproj`, all upsell-UI files.

**Attribution-preserve set — the surfaces where the binding GPL §5/§7 attribution actually lives; keep
verbatim, NEVER swept or deleted (`PLAN-republish-free` §A item 2). Stripping or displacing any of these
would *terminate the GPL license* under §8:**

> **CORRECTION (verified — AltTab uses NO per-file copyright headers).** An earlier draft told the executor to
> "preserve all source-file copyright headers verbatim (e.g. the upstream header in `src/App.swift`)" and
> attached the §8-termination warning to that. **There is no such header.** `grep -rln -iE
> 'copyright|SPDX|Licensed under|Pontoise|GPL' src/ --include='*.swift'` matches only **2 of 205** swift
> files, and **neither is a header**: `src/App.swift`'s hits are the runtime accessors `static let licence =
> Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright")` (line 15) and `static let repository`
> (line 16) — `App.swift` begins with `import Cocoa`, no copyright block — and `src/macos/LoginItem.swift`'s
> hit is an inline code comment. So a per-merge "confirm source copyright headers survived" check verifies
> *nothing* while creating false confidence. The binding attribution surface is the four items below, not
> per-file headers. **Rule: preserve whatever headers exist (currently none of substance), and never ADD a
> fork-only copyright that displaces upstream attribution** (e.g. do not prepend a "© <Fork> " header to
> source files — that would be the actual §8-termination risk).

- **(a) `LICENCE.md`** (GPL-3 text — required for compliance). Keep byte-for-byte; never edit.
- **(b) `Info.plist:21` `NSHumanReadableCopyright = "GPL-3.0 licence"`** (verified — `<key>` at :20, value at
  :21), surfaced at runtime via `App.licence` (`App.swift:15`) and rendered by `AboutTab.swift:17`. This is
  the in-app §5(d) "Appropriate Legal Notices" string — do NOT remove or overwrite it with a fork-only
  notice; it must keep stating GPL-3.
- **(c) the README / About-tab fork credit** — "<ForkName> is a fork of `lwouis/alt-tab-macos`, © Louis
  Pontoise, GPL-3.0" (§3.2). This is the prominent §5(a)/(b) attribution; the §3.2 brand sweep must never
  delete it (nominative fair use, REQUIRED by §5 — see the sweep boundary below).
- **(d) `docs/contributors.md`** (lists upstream developers + translators) and **`docs/acknowledgments.md`**
  (third-party library credits) — both exist in-tree today and the deferred §A baseline explicitly says they
  MUST be retained. `docs/acknowledgments.md` is **also rendered in-app** (`AcknowledgmentsTab.swift` loads
  `acknowledgments.md` from the bundle, surfaced via `MacroPreferences`'s Acknowledgments tab), so deleting
  or breaking it also breaks a visible UI panel.
- **Trademark-sweep boundary (§3.2):** the §3.2 brand-string sweep MUST touch ONLY the product-name brand
  strings ("AltTab" as a rendered product name). It MUST NOT over-sweep **author-name attribution** — e.g.
  "© Louis Pontoise", the `lwouis/alt-tab-macos` repo reference in the README/About credit, or the
  contributor names. "fork of AltTab" / "based on AltTab by Louis Pontoise" in the attribution is **lawful
  nominative fair use** and is REQUIRED by §5; do not let an over-eager `grep -r 'AltTab'` sweep delete it.

**Net recurring identity conflict surface per merge:** the only in-tree upstream files edited are
`Info.plist` (~2-3 dormant lines, 0 commits since v11.0.0) and optionally one `FeedbackWindow.swift` line.
Identity is as merge-stable as the de-paywall patch.

### 3.6 Distribution & first-run UX (how a NEW user gets and trusts the first build)

§3.3 covers *auto-update* in depth, but the plan otherwise never says how a brand-new user **obtains** the
first build or **gets past Gatekeeper** the first time — auto-update only takes over after install. Decide
these at bootstrap (they are owner decisions, not per-merge work):

- **(a) Primary download channel.** Pick one and link it from the README and `<DOMAIN>`:
  - **GitHub Releases** (simplest; the pipeline already publishes a notarized `.zip` there via
    `softprops/action-gh-release` — §4.0). Link `https://github.com/<fork>/releases/latest` from the README.
    This is the recommended default.
  - **Homebrew Cask** (better discovery). **Cost to absorb in the loop:** a Cask is a *recurring
    upstream-tracking task of its own* — every fork release must bump the cask's `version`/`sha256`
    (auto-PR via a bumper bot, or manual). Only adopt if the owner accepts that recurring cost; otherwise
    defer it.
  - The repointed **`<DOMAIN>` site** as a download landing page (it must exist anyway to serve
    `/appcast.xml` — §3.3 — so a download link there is cheap).
- **(b) Tie the download URL to the same `<DOMAIN>`/appcast host §3.3 already requires** so the first-install
  link and the auto-update feed are one consistent origin (avoids a second host to keep alive).
- **(c) Gatekeeper first-run story.** The build is **notarized + stapled** (§3.3/§4.0) but signed by an
  *unknown* (non-App-Store, fork) developer, so on first launch macOS still shows a "downloaded from the
  internet" prompt. Notarization + stapling is **necessary** (without it Gatekeeper hard-blocks on recent
  macOS); document in the README the expected first-run flow (right-click → Open, or System Settings →
  Privacy & Security → Open Anyway). Do NOT promise an App-Store-grade silent first launch — that requires
  identifiers the fork doesn't have. The post-build `notarytool` + staple verification (§3.3 / §6.1) is what
  guarantees this prompt is the *only* friction, not an outright block.

#### 3.6.1 Steady-state fork-to-fork auto-update (the upgrade the perpetual-republish promise depends on)

§3.6(a)-(c) cover a *brand-new* install; §4.6 covers the Sparkle private-key break-glass. But the
"continuously republish" promise lives or dies on a **different** path: a user already running **fork build
N** must actually receive **fork build N+1 via Sparkle**. Nothing in the plan validates this end-to-end, and
a silently-broken Sparkle upgrade strands existing fork users on a stale build **with no signal** (the
appcast GET succeeds, but the enclosure/signature/version handling fails quietly). This is the *upgrade
analogue* of the §4.4 feature-unlock check and must be proven, not asserted. The four things that must hold,
all of which the fork now controls (so all of which can break on a fork-side mistake):
1. **Enclosure URL resolves to the FORK's release** — `update_appcast.sh:18` enclosure points at
   `github.com/<fork>/releases/download/...` (the §4.0 "single most safety-critical edit"); a leftover lwouis
   URL silently pulls the upstream *paywalled* binary as the "update."
2. **EdDSA signature verifies against the EMBEDDED fork public key** — the running build N embeds the fork's
   `SUPublicEDKey` (`Info.plist:62`); N+1's appcast entry must be signed with the matching fork private key
   (`SPARKLE_ED_PRIVATE_KEY`). A key mismatch makes Sparkle reject the update silently.
3. **`SUVersion`/version ordering is monotonic** — the fork's `v100.0.0` offset (§4.3) must keep
   `sparkle:version` strictly increasing across fork releases so Sparkle offers N+1 over N (and an upstream
   `v11.x`/`v12.x` numeric never out-sorts a fork version).
4. **Gatekeeper is the only friction** — the in-place upgrade installs with the notarized/stapled build, the
   same single prompt as first run, nothing harder.

This is validated by the §6.1 bootstrap acceptance step and re-checked per release (§6.2 step 10) below.

---

## 4. Maintenance model & auto-republish pipeline

### 4.0 What the fork inherits vs. owns

Upstream's pipeline is one workflow, `.github/workflows/ci_cd.yml`, triggered `on: push: branches: [master]`
**ONLY** (verified — no `pull_request:` trigger; it is the *sole* workflow, so the sync PR runs no CI until
the fork adds one — §4.2), running on `macos-15`, chaining the `scripts/`: `print_env` → `npm ci` →
`commitlint` → `ensure_generated_files_are_up_to_date.sh` → `determine_next_version.sh`
(semantic-release dry-run) → `replace_environment_variables_in_app.sh` (writes `local.xcconfig`) →
`codesign/setup_ci_master.sh` → `run_tests.sh` (`xcodebuild test -scheme Test`) → `build_app.sh` (the
**"Copy Sparkle Helpers"** build phase runs `scripts/copy_sparkle_helpers.sh`, which embeds the
`vendor/Sparkle/Helpers/*` binaries into `Sparkle.framework` and re-seals the framework — §3.3) →
`package_and_notarize_release.sh` (zip → notarytool → stapler) → `upload_symbols_to_appcenter.sh` →
`update_appcast.sh` (Sparkle `sign_update`) → `update_readme_and_website.sh` → `npx semantic-release`
(line 59) → `extract_latest_changelog.sh` (line 61 — sets the `tag_name`/`body` outputs for the release
step) → `softprops/action-gh-release` (line 62, `body: …`, `files: …/*.zip`) → `update_website.sh` (line 67).
**Insert the §4.4 Guard B + Guard C greps as the FIRST steps of this push job — before `run_tests.sh`
(line 53), so they run before `update_appcast.sh` (57, Sparkle `sign_update`), `npx semantic-release`
(59, which pushes the `vX.Y.Z` tag to `master`), and `softprops/action-gh-release` (62). Placing them only
"before line 62" is too late: by line 62 the tag is already pushed and the binary already signed (§4.4
"Where the guards run"). Keep a second copy before line 62 as belt-and-suspenders.** Dropping
`update_readme_and_website.sh` leaves `extract_latest_changelog.sh` in place (it still feeds the release body
— inject the §5 source link there).

Secrets consumed: `GITHUB_TOKEN`, `APPCENTER_SECRET`, `APPCENTER_TOKEN`, `APPLE_ID`, `APPLE_PASSWORD`,
`APPLE_TEAM_ID`, `APPLE_P12_CERTIFICATE`, `SPARKLE_ED_PRIVATE_KEY`, `WEBSITE_DISPATCH_TOKEN`.

Three lwouis hardcodes are the fork's hard divergence points (independent of the chokepoints):
- **`scripts/update_appcast.sh:18`** — enclosure URL
  `github.com/lwouis/alt-tab-macos/releases/download/...`. **Must** point at the fork's releases or every
  Sparkle auto-update pulls upstream's signed, **paywalled** binary. **Single most safety-critical edit.**
- **`scripts/update_website.sh:5`** — `gh api repos/lwouis/alt-tab-website/dispatches`. Drop this step.
- **`scripts/update_readme_and_website.sh`** — pulls lwouis stars/downloads for README SVGs. Cosmetic; neuter or drop.

**Verdict: adapt, don't reinvent.** Reuse the build/sign/notarize/appcast scripts' *structure*, changing
those three URLs, the secret values, `APP_NAME` (§3.1), and the appcast publish target (§3.3). **"Reuse
verbatim" does NOT mean signing is untouched:** the embedded Sparkle helpers under
`vendor/Sparkle/Helpers/` are signed with lwouis's Developer ID and MUST be re-signed under the fork's cert
before first release (§3.3) or notarization/Gatekeeper rejects the build. **`scripts/copy_sparkle_helpers.sh`
is the build phase that embeds those helpers into `Sparkle.framework` and re-seals the framework** with
`CODE_SIGN_IDENTITY` (so `local.xcconfig`'s fork identity flows through — no edit to this script); but per
its own comment it does **not** re-sign the nested helpers, so the *bootstrap* re-sign of
`vendor/Sparkle/Helpers/*` is what determines the embedded helpers' TeamID (§3.3). Also note `ci_cd.yml`
ships **with no `pull_request:` trigger** (so the sync PR runs no CI — §4.2), without `permissions:`, and
with `environment: production` (§4.3) — all three need fork-side setup or the PR gate / release push /
publish silently fails (no pre-merge guard, 403, or stall).

### 4.1 Git model — merge (recommended)

**Use merge, not rebase/patch-queue.** The de-paywall change is a handful of edits to four cold files
with zero upstream commits since v11.0.0 — the base under the patch is dead-still, so a patch-queue's
clean-linear-history benefit buys nothing while its cost (re-applying `format-patch` atop a pinned ref
every cycle, re-resolving fuzz whenever any nearby line shifts) is pure overhead. Merge keeps the fork's
identity/CI commits as durable history that 3-way merge reconciles automatically, and surfaces a
chokepoint collision exactly once as a normal conflict in a known file — the loud failure we want.

> **Rejected alternative — "contribute an upstream build-flag seam" (a `#if FREE_BUILD` / paywall-off
> compile flag merged INTO upstream).** On paper this would make the fork a zero-conflict config toggle. It
> is a non-starter: **lwouis sells Pro**, so a maintainer whose revenue depends on the paywall will not merge
> a first-class switch that turns it off — the PR would be declined, and pursuing it wastes effort and tips
> the fork's hand. The fork therefore cannot rely on upstream cooperation for the de-paywall seam; the thin
> inert patch on dormant lines (§2) is the right design precisely *because* it needs no upstream buy-in.

**One-time setup:**
```bash
git remote add upstream https://github.com/lwouis/alt-tab-macos.git
git fetch upstream --tags
```

**Per-release sync (steady state):**
```bash
git fetch upstream --tags
git switch -c sync/upstream-v11.4.0 master
git merge v11.4.0        # 3-way merge upstream's tag
# expected: clean, OR conflicts ONLY in identity/CI files we own
```
The four chokepoints are dormant upstream, so the `depaywall:` commits don't conflict on a normal sync.
The files that *can* conflict are the ones the fork intentionally diverged — `Info.plist`,
`scripts/update_appcast.sh`/`update_website.sh`, `.github/workflows/ci_cd.yml` — and those resolutions are
mechanical ("keep ours").

**When upstream DOES touch a chokepoint** (rare; zero occurrences so far): the merge halts with a
conflict in the chokepoint file. Confirm it's a chokepoint (`git diff --name-only --diff-filter=U`),
re-apply the de-paywall intent on top of upstream's new code, run the anti-relock test locally until
green (§4.4), **then** commit. Even a mis-resolution can't ship — the §4.4 test fails CI before any
signed build.

### 4.2 Trigger / cadence — scheduled cron opening a sync PR

A scheduled GitHub Actions job beats `repository_dispatch`/webhooks: the fork can't add a webhook to
upstream, polling tags on a cron needs no upstream cooperation, and a reviewable PR lets a human eyeball
the merge + the §4.4 test before it ships. Keep this **separate** from `ci_cd.yml` — new workflow
`.github/workflows/upstream_sync.yml`:

```yaml
name: upstream-sync
on:
  schedule: [{ cron: '0 7 * * *' }]   # daily; cheap, idempotent
  workflow_dispatch: {}
permissions:                           # GITHUB_TOKEN is read-only by default; PR + push need these
  contents: write
  pull-requests: write
jobs:
  sync:
    runs-on: ubuntu-latest             # pure git, no Xcode
    env:
      # CRITICAL — do NOT use ${{ github.token }} here. A branch push / PR authored with the
      # default GITHUB_TOKEN does NOT trigger other workflows (GitHub's documented recursion
      # prevention), so guard.yml and ci_cd.yml's pull_request checks would NEVER fire on the
      # sync PR — the entire pre-merge gate would silently never run (see the blocking note below).
      # Use a fork-owned credential that re-triggers workflows: a GitHub App installation token
      # (preferred) or a classic/fine-grained PAT, stored as a repo/Environment secret.
      GH_TOKEN: ${{ secrets.SYNC_BOT_TOKEN }}   # GitHub App installation token (preferred) or PAT
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
          # Persist the fork-owned credential (NOT the default GITHUB_TOKEN) as the push
          # credential, so the branch push below re-triggers guard.yml / ci_cd.yml's PR checks.
          token: ${{ secrets.SYNC_BOT_TOKEN }}
      - name: Add upstream + fetch tags
        run: |
          git remote add upstream https://github.com/lwouis/alt-tab-macos.git
          git fetch upstream --tags
      - name: Find newest upstream tag not yet merged
        id: tag
        run: |
          # UPSTREAM-ONLY: `git tag -l 'v*'` would also match the FORK's OWN semantic-release tags
          # (the fork cuts vX.Y.Z every sync — §4.3), so the "newest tag" could be a fork tag, not
          # upstream's. List tags from the upstream remote explicitly instead.
          latest="$(git ls-remote --tags --refs upstream 'v*' \
                     | awk -F/ '{print $NF}' | sort -V | tail -1)"
          # GUARD 1 — already merged: bail if it's already an ancestor of master, else the cron
          # re-opens the same PR every day until the next upstream tag ships.
          # `origin/master` exists after actions/checkout@v6 with fetch-depth:0; if in doubt use
          # `git rev-parse HEAD` (the checked-out master tip).
          if git merge-base --is-ancestor "refs/tags/$latest" HEAD; then
            echo "Already merged: $latest"; echo "skip=true" >> "$GITHUB_OUTPUT"; exit 0
          fi
          # GUARD 2 — a prior sync is still OPEN (stalled/blocked): do NOT skip the stranded tag and
          # leap to the newest one. An open sync/* PR means an earlier upstream tag is unmerged; merging
          # the newest tag straight onto master would abandon the intermediate tag/PR and silently drop
          # the commits in between. Bump/notify the existing PR instead, and let the human resolve it
          # before the next tag is synced (resolve-in-order). See the §4.2 stalled-sync semantics below.
          open_sync="$(gh pr list --state open --label sync --json headRefName,number,createdAt \
                        --jq 'sort_by(.createdAt) | .[0]')"
          if [ -n "$open_sync" ] && [ "$open_sync" != "null" ]; then
            echo "A prior sync PR is still open: $open_sync"
            echo "skip=true" >> "$GITHUB_OUTPUT"
            echo "stalled=true" >> "$GITHUB_OUTPUT"   # liveness alert keys off this (below)
            exit 0
          fi
          echo "latest=$latest" >> "$GITHUB_OUTPUT"
      - name: Merge onto a sync branch (real merge commit, conventional message)
        if: steps.tag.outputs.skip != 'true'
        id: merge
        run: |
          git config user.name  "fork-sync-bot"
          git config user.email "fork-sync-bot@users.noreply.github.com"
          git switch -c "sync/${{ steps.tag.outputs.latest }}"
          # NO --no-commit: let git author a real merge commit with a CONVENTIONAL message
          # so commitlint/semantic-release stay happy (see §4.3). On conflict, commit the
          # conflicted tree so the PR shows the markers for a human to resolve.
          if git merge --no-ff -m "chore(sync): merge upstream ${{ steps.tag.outputs.latest }}" "${{ steps.tag.outputs.latest }}"; then
            echo "conflicts=false" >> "$GITHUB_OUTPUT"
          else
            git add -A && git commit -m "chore(sync): merge upstream ${{ steps.tag.outputs.latest }} (CONFLICTS — resolve before merge)" --no-verify
            echo "conflicts=true"  >> "$GITHUB_OUTPUT"
          fi
          git push origin "HEAD:sync/${{ steps.tag.outputs.latest }}"
      - name: Open PR
        if: steps.tag.outputs.skip != 'true'
        run: |
          gh pr create \
            --head "sync/${{ steps.tag.outputs.latest }}" \
            --base master \
            --title "sync: merge upstream ${{ steps.tag.outputs.latest }}" \
            --body "Automated upstream sync. Verify green CI (incl. anti-relock test) before merge." \
            --label "${{ steps.merge.outputs.conflicts == 'true' && 'sync,conflict' || 'sync' }}"
```

Why this shape (verified against `ci_cd.yml` + `release.config.js`):
- **No `--no-commit`.** The original `git merge --no-commit --no-ff` then handing a dirty tree to
  `create-pull-request` would let that action author ONE squashed, **non-conventional** commit, discarding
  upstream's commits and the merge commit. `commitlint` lints the whole pushed range (`ci_cd.yml:48`,
  `--from "$GITHUB_EVENT_BEFORE" --to "$GITHUB_EVENT_AFTER"`) and `@semantic-release/commit-analyzer`
  needs conventional commits, so that squashed/non-conforming commit would fail the release job or yield a
  wrong bump. Authoring a real `chore(sync):` merge commit and pushing it ourselves avoids this.
- **Upstream-only tag selection + the `merge-base --is-ancestor` guard.** Enumerate tags from the
  **upstream remote** (`git ls-remote --tags upstream`), NOT `git tag -l 'v*'` — the latter also matches the
  fork's OWN release tags (the fork cuts `vX.Y.Z` every sync, §4.3), so "newest tag" could be a fork tag.
  Without the ancestor guard the newest tag is selected unconditionally, so after merging `v11.4.0` the cron
  re-creates `sync/v11.4.0` and re-opens an identical PR every day until `v11.5.0` ships — training the
  maintainer to ignore the review gate.
- **Explicit `permissions:` + `gh pr create`.** GitHub defaults the workflow `GITHUB_TOKEN` to read-only;
  push and PR creation need `contents: write` + `pull-requests: write`. **But `permissions:` is necessary,
  not sufficient — see the blocking token note immediately below: the credential used to push the branch and
  open the PR must NOT be the default `GITHUB_TOKEN`, or no pre-merge check ever runs.**

> **BLOCKING — the pre-merge gate never fires if the sync bot authors with the default `GITHUB_TOKEN`.**
> By GitHub's documented recursion-prevention rule, *a branch push or PR created by a workflow using the
> ambient `GITHUB_TOKEN` does NOT trigger other workflow runs* (no `push`/`pull_request` events fire from
> it). So if `upstream_sync.yml` pushes `sync/*` and runs `gh pr create` with `${{ github.token }}`, then
> **`guard.yml` and `ci_cd.yml`'s `pull_request:` checks never run on the sync PR** — and the §6.2 "verify
> the PR's CI is green" gate the reviewer relies on has ZERO checks to look at. The architecture then
> silently degrades to exactly the unsafe state §4.2 warns about: the only surviving guard is the
> release-time Guard B/C grep in `ci_cd.yml`, which runs **post-merge** — but, wired as the FIRST push-job
> step (§4.4), it still aborts the job **before** `update_appcast.sh`/`semantic-release` push the tag or sign
> the binary, so a relock/conflict-laden tree is blocked rather than shipped (the failure mode is degraded —
> no PR review — but still fail-closed). **Fix at the design level — the sync bot MUST author the push and the PR with a credential that
> re-triggers workflows:**
> - **(preferred) A GitHub App installation token** scoped to this repo (least-privilege, short-lived,
>   auto-rotating) stored as `SYNC_BOT_TOKEN`. Used as the `actions/checkout` `token:` (so the push
>   re-triggers) and as `GH_TOKEN` for `gh pr create`.
> - **(acceptable) A fork-owned classic/fine-grained PAT** with `contents`+`pull-requests` write, stored as
>   `SYNC_BOT_TOKEN`. Simpler but it expires and becomes a new silent SPOF (see §4.6), and if leaked it can
>   push to `master` — prefer the App token.
> - **(alternative) Self-author the push with the default token, then explicitly re-dispatch** the guard
>   checks via `workflow_dispatch`/`repository_dispatch` carrying the bot's own token. More moving parts than
>   the App token; only choose it if a token cannot be provisioned.
>
> **Acceptance test (do once at bootstrap):** open a sync PR *through the bot* and confirm the `guard.yml`
> AND `ci_cd.yml` `pull_request:` checks actually APPEAR and run on it — not merely that a hand-pushed
> branch goes red. A bot PR with no checks attached means the token is wrong and the gate is disarmed.

**Stalled / skipped-sync semantics (define this, don't leave it to chance).** The `merge-base
--is-ancestor HEAD` guard only suppresses re-opening an *already-merged* tag; it says nothing about an
*open* sync PR that a human hasn't merged yet. Two upstream tags can ship before the maintainer resolves the
first PR — and if the cron then merged the newest tag straight onto `master`, it would **abandon the
stranded intermediate tag/PR and silently drop the commits between them.** The loop MUST therefore pick one
defined behavior when an open `sync/*` PR already exists (this plan adopts (a)):
- **(a) Resolve-in-order (default).** While any `sync/*` PR is open, the cron does NOT open a new one — it
  bails (Guard 2 above) and the liveness alert escalates on the stale-open trigger. The maintainer merges
  the open PR first; the next cron run then syncs the next tag. Simple, never drops commits, but a backlog
  pauses syncing until the human acts.
- **(b) Merge intermediate tags in sequence.** Instead of leaping to the newest tag, merge the *oldest
  unmerged* upstream tag onto the existing sync branch (or chain branches), so no tag is skipped. More
  automation, more conflict surface, but keeps moving without a human.
Do **not** silently fast-forward to the newest tag and abandon a stranded prior PR — that is the one
behavior that loses upstream commits. The §6.2 runbook carries a "a previous sync is still open/blocked"
branch with this resolve-in-order-vs-fast-forward decision, and the §4.5 table notes that a paused backlog
compounds the next merge's conflict effort (two upstream deltas resolved at once).

> **BLOCKING gap — a CLOSED-unmerged sync PR silently defeats resolve-in-order and drops commits; and the
> labels must exist and fail closed.** The two guards above are insufficient on their own: Guard 1 skips only
> an *already-merged* tag, and Guard 2 bails only while a sync PR is *open*. So if a maintainer **closes** a
> noisy/conflicted sync PR to defer it (instead of leaving it open), the intervening tag is neither an
> ancestor of `master` **nor** open — both guards pass, the next cron leaps to the **newest** tag, and the
> closed tag's commits (including the security fixes that are the whole reason — §0 — to track upstream) are
> **silently dropped**. Separately, Guard 2 *and* the §0.1 trip-wire query the `sync`/`conflict`/
> `chokepoint-refresh` labels, but `gh pr list --label sync` returns an **empty list, not an error**, for a
> label that was never created — so on a fresh repo Guard 2 silently no-ops until someone creates the label.
> Both failures are silent and surface only as missing upstream fixes much later — the worst class for a
> set-and-forget loop. **Harden the design so the loop never relies on PR open-state to decide what to sync:**
> - **(a) Track the last-SYNCED upstream tag in a committed state file** (`.fork-sync-state`), advanced ONLY
>   when a sync PR merges to `master` (a tiny `ci_cd.yml` push-job step writes the merged tag and commits it).
>   The cron then syncs the **oldest upstream tag strictly newer than the recorded tag** — *not* "newest tag
>   minus `--is-ancestor`". A closed-unmerged PR can no longer cause a skip (the state file didn't advance, so
>   that tag is still "next"), and resolve-in-order holds *by construction*. This subsumes Guard 1.
> - **(b) Create the labels at bootstrap** (`gh label create sync|conflict|chokepoint-refresh`, §6.1) and make
>   Guard 2 / the trip-wire **fail closed**: if the label query errors OR the label is absent, **bail and
>   alert**, never treat an empty result as "no open sync."
> - **(c) A deferred sync PR must be left OPEN** — never closed-and-forgotten. If it genuinely must be closed,
>   the recorded tag in `.fork-sync-state` is *not* advanced (it only advances on merge), so the next cron
>   re-opens that same tag rather than skipping it. The §6.2 runbook states this explicitly.

> **CRITICAL — the in-repo `schedule:` trigger silently auto-disables after 60 days of repo inactivity.**
> GitHub Actions disables a `schedule:` trigger defined in a repository that has had **no commit activity for
> 60 days**, with no error, no PR, and no notification. This failure is **self-camouflaging**: the quieter
> upstream is, the more likely a low-effort fork goes 60 days without a commit, and that is *exactly* when the
> cron stops firing — so the fork can fall arbitrarily far behind on upstream **security/bug fixes** with no
> signal, directly contradicting "continuously merge … indefinitely." **The cron alone is an unmonitored
> single point of failure.** Pick at least one durability mechanism (recommend the first two together):
> - **Heartbeat / re-arm.** A lightweight scheduled job that keeps the repo "active" — e.g. a periodic no-op
>   commit to a tracking file, or a `gh workflow enable` re-arm call — so the 60-day clock never expires.
>   (A heartbeat job is itself a `schedule:` and can also be disabled; prefer the external scheduler below as
>   the primary, with the heartbeat as belt-and-suspenders.)
> - **Liveness alert (two triggers, not one).** Fail loudly if EITHER: (i) **no sync PR has appeared in N
>   days** (e.g. N=45, inside the 60-day window) — catches a dead cron; OR (ii) **the oldest OPEN `sync/*` PR
>   is older than M days** (e.g. M=14) — catches a sync that opened but then stalled/blocked, which the
>   "no PR in 45 days" trigger alone would NOT see (an open-but-stale PR keeps resetting the "newest PR"
>   clock while no upstream commits actually land). Without trigger (ii) a zombie PR keeps the alert silent
>   while the fork falls behind. A tiny job opens an issue / sends a notification on either condition.
> - **External scheduler (most robust — RECOMMENDED PRIMARY).** Move the trigger off in-repo `schedule:`
>   entirely — an org-level scheduled dispatch, a separate always-active scheduler repo, or an external cron
>   hitting `repository_dispatch`. An out-of-repo trigger is not subject to the 60-day in-repo inactivity
>   rule. **For a set-and-forget loop this is the default to pick**, for two reasons: (1) it is the only
>   option immune to the 60-day auto-disable, and (2) if the external trigger **carries its own credential**,
>   it composes naturally with the `SYNC_BOT_TOKEN` fix above (the same fork-owned credential that re-triggers
>   the guard/CI checks) — one credential solves both "the cron stays alive" and "the PR runs CI." Keep the
>   in-repo `schedule:` + heartbeat + liveness alert as **belt-and-suspenders**, not as the sole mechanism.
>
> At minimum, **document the 60-day auto-disable as a known failure mode** in the runbook (§6.2) and add the
> liveness alert; treating the bare cron as "set and forget" is unsound for an indefinite tracking loop.

> **CRITICAL — the sync PR currently runs NO CI (verified):** upstream's `ci_cd.yml` is triggered
> `on: push: branches: [master]` ONLY — there is **no `pull_request:` trigger** and `ci_cd.yml` is the
> **sole** workflow (`grep -rln pull_request .github/workflows/` returns nothing). As shipped, therefore,
> **the §4.4 anti-relock test (Guard A) and the §4.4 marker grep (Guard B) never run on the sync PR.** They
> run only *post-merge*, on the push to `master` — the *same* push that proceeds straight through
> build → sign → notarize → `semantic-release` → `softprops/action-gh-release`. There is no pre-merge
> automated gate and no green check for the human reviewer to rely on. **A relock would therefore be caught
> only after the release has already been cut.** This must be fixed before the strategy is safe (see the
> required `pull_request:` trigger below); until then, "the PR's CI gates the release" is FALSE.

**MANDATORY BOOTSTRAP DELIVERABLE (not a "required fix" footnote) — make the release gate real.** The
entire "resolve-and-ship with confidence" strategy (§4.1/§6.2) leans on a pre-merge gate that does NOT exist
as upstream ships `ci_cd.yml`. Two pieces, both first-class bootstrap items with an acceptance test:

**(1) Add a `pull_request:` trigger to the fork's `ci_cd.yml` and gate EVERY release-side step.**

```yaml
on:
  push:
    branches: [master]
  pull_request:
    branches: [master]
```

**Gate the COMPLETE set of release/push-only steps under `if: github.event_name == 'push'` — derived
line-by-line from the actual workflow** (verified ordering, `ci_cd.yml:47-67`):

| Step (`ci_cd.yml` line) | On `pull_request`? | Why |
|---|---|---|
| `npm ci` (:47) | **runs** | needed to install commitlint/semantic-release tooling |
| `commitlint --from "$GITHUB_EVENT_BEFORE" --to "$GITHUB_EVENT_AFTER"` (:48) | **GATE or fix** | `$GITHUB_EVENT_BEFORE`/`AFTER` (`env`, :14-15) are **push-context** and **empty on `pull_request`**, so this lints an empty/garbage range and goes red for reasons unrelated to a relock |
| `ensure_generated_files_are_up_to_date.sh` (:49) | **runs** | legitimate PR check (catches an un-regenerated l10n diff — §4.5) |
| `determine_next_version.sh` (:50, semantic-release `--dry-run`) | **GATE** | a dry-run against a PR head is meaningless and can fail/mis-bump; it is release-path, not a gate |
| `replace_environment_variables_in_app.sh` (:51) | GATE | writes build config; release-only |
| `setup_ci_master.sh` (:52) | GATE (use `setup_ci_pr.sh` if a PR build is wanted — `scripts/codesign/setup_ci_pr.sh` exists) | signing setup |
| Guard B + Guard C greps (inserted, FIRST — before :53) | **runs** | marker + conflict-marker greps; placed first so on the push path they abort before `update_appcast`/`semantic-release` sign/push (§4.4) |
| `run_tests.sh` (:53) — **Guard A** | **runs** | the anti-relock unit test; the behavioral gate |
| `build_app.sh` (:54) | GATE | build |
| `package_and_notarize_release.sh` (:55) | GATE | notarize |
| `upload_symbols_to_appcenter.sh` (:56) | drop entirely | telemetry — removed |
| `update_appcast.sh` (:57) | GATE | publishes feed |
| `update_readme_and_website.sh` (:58) | GATE/drop | website |
| `npx semantic-release` (:59) | GATE | cuts release |
| `extract_latest_changelog.sh` (:61) | GATE | sets release-body outputs |
| `softprops/action-gh-release` (:62) | GATE | creates release |
| `update_website.sh` (:67) | GATE/drop | website dispatch |

> **The idealized "PR path runs only `npm ci` → `ensure_generated` → `run_tests` → grep" sentence in earlier
> drafts was WRONG:** `commitlint` (:48) and `determine_next_version` (:50) sit *in front of* `run_tests`
> (:53) and misbehave on PR events. **Either gate them under `if: github.event_name == 'push'` too, or give
> them PR-safe variants** — for commitlint, lint a base..head range valid on PR context
> (`--from ${{ github.event.pull_request.base.sha }} --to ${{ github.sha }}`, paired with the §4.3 `ignores`
> predicate) or `npx commitlint --last`; do NOT leave them running over an empty push-range on PR events, or
> **the PR check goes red for non-relock reasons** — which either blocks every clean sync or trains the
> maintainer to merge past a red check (defeating the whole gate). **The exact ordered PR-event step list is:
> Guard B + Guard C greps (first, near-instant) → `npm ci` → `ensure_generated_files_are_up_to_date.sh` →
> (commitlint, PR-safe variant or gated) → `run_tests.sh` (Guard A).** (On the PR path nothing is signed or
> pushed, so grep ordering is less critical there than on the push path — but keeping the greps first is
> consistent with the push job and gives the fastest red signal.)

**Acceptance test for this deliverable (do it once, at bootstrap):** push a branch that deliberately reverts
the `computeState() → .pro` flip and open a PR; **confirm the PR check is RED** (Guard A fails, or Guard B's
marker grep fails) *before* any merge. A green check on a relocked branch means the gate is not wired and the
bootstrap is incomplete.

**(2) Add a SEPARATE fork-owned guard workflow `.github/workflows/guard.yml` on `pull_request`** that runs
Guard A + Guard B independently of `ci_cd.yml`. Rationale: `ci_cd.yml` is the one file most likely to take an
upstream conflict, and a careless "keep ours/theirs" resolution could silently strip the `pull_request:`
trigger or the gating — at which point the §4.4 guards would stop gating PRs with no error. A guard workflow
that does **not** inherit `ci_cd.yml`'s trigger survives that. Pair it with the §6.2 recurring check that the
`pull_request:` trigger still exists in `ci_cd.yml` post-merge. **And independently, wire the Guard B + Guard C greps
into `ci_cd.yml` as the FIRST push-job steps — before `run_tests.sh`, and therefore before `update_appcast.sh` (Sparkle sign), `semantic-release` (tag push), and `softprops/action-gh-release` (§4.4)** — so that
**even with no PR gate at all, a relock or conflict-laden tree aborts the job before the tag is pushed or the
binary signed.** Placing the grep only just before `action-gh-release` is too late (the tag is already
pushed by `semantic-release` at line 59 — §4.4 "Where the guards run"); running it first makes "a relock can
never ship" robust to a missing or misconfigured trigger, not contingent on it.

A release fires only when the PR merges to `master`. The `sync` vs. `sync,conflict` label tells the
maintainer whether it's a 5-minute approval or a chokepoint refresh.

### 4.3 Auto build → sign → notarize → appcast → release

Keep `ci_cd.yml`'s skeleton; change secrets, identity URLs, versioning scope — and add two pieces of
fork-side plumbing the upstream workflow assumes exist:

**Workflow permissions + Environment (verified gaps):**
- `ci_cd.yml` has **no `permissions:` key**. `@semantic-release/git` pushes commits+tags to `master` and
  `softprops/action-gh-release@v3` (line 62) creates the release (`release.config.js` has no
  `@semantic-release/github` plugin, so softprops is the sole release-creator). Both need
  `contents: write`. GitHub defaults the workflow `GITHUB_TOKEN` to read-only since 2023, so without write
  perms the push and the gh-release creation 403 → no tag, no release, and the appcast enclosure
  (`releases/download/v$version/…`) then 404s for auto-update. **Add `permissions: { contents: write }` to
  the fork's `ci_cd.yml`** (or set the repo default workflow token to read-write).
- `ci_cd.yml:23` sets `environment: production`. **Create a GitHub Environment named `production`** in the
  fork and attach `APPLE_P12_CERTIFICATE` / `APPLE_ID` / `APPLE_PASSWORD` / `APPLE_TEAM_ID` /
  `SPARKLE_ED_PRIVATE_KEY` there (matching the `environment:`), with **no required-reviewer protection**
  that would stall releases.

**Node version (verified mismatch — do NOT treat as a one-line bump):** `ci_cd.yml:43` pins
`node-version: 16` while `package.json` requires `"node": ">=18.0.0"`. **But `npm ci` only *warns* on an
`engines` mismatch — it does not hard-fail unless `engine-strict=true` is set (it is not).** And the release
toolchain pinned in `package.json` is 2018-2019-era: `semantic-release ^15.13.24`, `@commitlint/cli ^8.1.0`,
`husky ^3.0.4` (all consistent with the node-16 pin). `semantic-release` v15 and commitlint v8 were never
validated on Node 18/20, and both run on the **critical release path** (`npx semantic-release`,
`commitlint`), so a naïve node bump can trade a benign warning for a `semantic-release` crash *after*
build/notarize already ran. **Choose one, don't present node-18 as a one-liner:**
- **(lower-risk) KEEP `node-version: 16`** and delete the bump — the engines mismatch only warns; OR
- **If bumping**, treat it as a toolchain-upgrade subtask: bump `semantic-release` (→ v22+), commitlint
  (→ v18+, which changes the config format — coordinate with the §4.3 commitlint `ignores` fix), and husky
  (→ v9) **together**, and re-validate the entire release chain on the first run.

**`APP_NAME`:** set `ci_cd.yml:19` `APP_NAME` equal to `PRODUCT_NAME` (§3.1) or the build/package/appcast
scripts mismatch the artifact.

**Secrets — same names, fork's values** (repo Settings → Secrets → Actions, and the `production`
Environment above):
- `APPLE_P12_CERTIFICATE`, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` — the **fork owner's** Developer
  ID Application cert + notarization credentials. `setup_ci_master.sh` and
  `package_and_notarize_release.sh` consume them unchanged. Per the AGENTS.md invariant, the Developer ID
  / TeamID / bundle id must stay stable across the fork's own builds or every user's license keychain item
  orphans — freeze the fork identity once.
- `SPARKLE_ED_PRIVATE_KEY` — **new EdDSA keypair** for the fork; public half goes to the `SUPublicEDKey`
  value on `Info.plist:62` (`<key>` is on :61). Mandatory: Sparkle verifies the appcast against the
  embedded public key.
- `APPCENTER_SECRET`/`APPCENTER_TOKEN` — leave unset; drop `upload_symbols_to_appcenter.sh`.
- `WEBSITE_DISPATCH_TOKEN` — drop with the `update_website.sh` step.

**Identity/script edits:** `local.xcconfig` `DOMAIN` (§3.1); `scripts/update_appcast.sh:18` enclosure URL
→ the fork's releases (**safety-critical**); remove/repoint `update_website.sh` + the lwouis API calls in
`update_readme_and_website.sh`.

**Versioning + commitlint (verified, operationalized):** `release.config.js` has no `repositoryUrl` pin
and `@semantic-release/git` commits back to the CI branch, so semantic-release versions off the **fork's
own** tags. **Fork versions are independent and each `chore(sync)` merge intentionally cuts a fork release:**
`release.config.js` maps `chore` → `patch` (line 12), so the synthetic `chore(sync): merge upstream` commit
forces *at least* a patch bump, and the merged upstream `feat:`/`fix:` commits in the range drive the bump
type. `sparkle:version` (from `VERSION.txt` via `update_appcast.sh`) tracks the fork tag. (1) The fork's
extra `depaywall:`/identity commits guarantee a version `>` the synced upstream tag, so no special suffix is
needed for ordering — **but the fork's own `vX.Y.Z` tags will diverge from / leapfrog upstream's, so a future
`git merge v11.X.0` can collide in the tag namespace if the fork already cut its own `v11.X.0`.** A collision
**hard-stops a sync** (`git merge` of an upstream tag whose name the fork already owns), so this must be
**decided at bootstrap, not left optional.**
> **DECISION (bake this in at §6.1, do not defer):** adopt a **permanent fork version offset** — the fork's
> release line starts at **`v100.0.0`** and semantic-releases from there, so a fork tag and an upstream
> `v11.x`/`v12.x` tag can never share a name for the foreseeable future. (Alternative if a distinct prefix is
> preferred: configure semantic-release's `tagFormat` to a `fork-vX.Y.Z` namespace; the offset is simpler
> and keeps Sparkle's numeric `sparkle:version` ordering monotonic.) Set this once and the sync loop can
> never deadlock on a namespace clash. A trailing `+fork` build-metadata suffix is NOT sufficient on its own
> — SemVer ignores build metadata for precedence and `git tag` names still collide on the `vX.Y.Z` stem. (2) `commitlint` lints the *whole pushed range* (`ci_cd.yml:48`,
`--from "$GITHUB_EVENT_BEFORE" --to "$GITHUB_EVENT_AFTER"`); a merged upstream tag drags in upstream's
commit messages, some non-conforming → commitlint fails the build (blocking the release job) and/or
`commit-analyzer` mis-bumps.

**Concrete fix (PRIMARY — `commitlint.config.js` ignores; verify on the FIRST sync):** the fork's
`commitlint.config.js` currently just `extends: ['@commitlint/config-conventional']` (verified). Add an
`ignores` predicate that drops the synthetic merge commit AND any commit reachable only through the merge's
second parent (i.e. upstream's own messages), while keeping `defaultIgnores: true` so `config-conventional`'s
built-in "Merge …" ignore still applies:

```js
module.exports = {
    extends: ['@commitlint/config-conventional'],
    defaultIgnores: true,
    ignores: [
        (msg) => /^chore\(sync\): merge upstream /.test(msg),  // our synthetic merge commit
        (msg) => /^Merge /.test(msg),                          // belt-and-suspenders
        // upstream messages we don't author and can't conform — match the patterns your
        // upstream actually uses, or pair this with the --last range narrowing below.
    ],
}
```

> **Do NOT use `--from HEAD~1 --to HEAD` (verified BROKEN).** Over a `--no-ff` merge, `HEAD~1` resolves to
> the FIRST parent (the fork tip), and `git rev-list HEAD~1..HEAD` enumerates the merge commit PLUS every
> newly-reachable upstream commit through the second parent — empirically 3 commits in a scratch test
> (`chore(sync): merge upstream v11.4.0`, `WIP messy upstream commit`, `feat: upstream A`), not 1. commitlint
> reads the same `from..to` range, so a non-conforming upstream commit still fails the job. This form does
> NOT lint "only the merge commit."

**If a range-narrowing command is still wanted** (e.g. to lint just the synthetic merge subject), use one
that lints exactly one message: `npx commitlint --last --verbose` (lints HEAD only) — not a `..` range over a
merge. Because the push re-lints the whole range, the §6.2 conflict-resolution commits must also stay
conventional.

**Net diff vs. upstream `ci_cd.yml`:** identical skeleton; drop `upload_symbols_to_appcenter.sh` +
`update_website.sh`; `softprops/action-gh-release` publishes to the fork's repo via the ambient
`GITHUB_TOKEN`; secret *values* differ; add the anti-relock test step (§4.4).

### 4.4 Safety — anti-relock smoke test (the backstop)

A bad merge that re-introduces a working paywall must never **push a tag, sign a binary, or write an appcast
entry** — not merely "never reach `action-gh-release`." (The irreversible side-effects happen at
`update_appcast.sh`/`semantic-release`, lines 57/59, *before* `action-gh-release` at 62; the greps therefore
run FIRST — see "Where the guards run" below.) Two independent, cheap guards — a unit test that exercises the
patched producer, **plus** a target-independent CI grep:

#### Guard A — unit test (append to the EXISTING `LicenseManagerTests.swift`; zero pbxproj edits)

> **The obvious test does NOT work — verified four ways. Do not write it.** A naïve
> `AntiRelockTests` that (1) references `ProFeature.*.attemptUse()` won't even **link**: `ProFeature.swift`
> is in the **app** target's Sources phase (`project.pbxproj:1970`), NOT the `unit-tests` phase
> (`BF0C80F5`, lines 1829-1900) — that phase has `LicenseManager.swift`, `LicenseState.swift`,
> `Endpoints.swift`, `RemoteLicenseClient.swift` but **no `ProFeature.swift`**. (2) Asserting on
> `LicenseManager.shared` fails even on a CORRECTLY patched build: `.shared` is never `initialize()`d in
> tests (the only caller is `App.swift:460`), so its `state` stays at the `.trialExpired` default
> (`LicenseManager.swift:51`) → `isProLocked == true`. The patch flips `computeState()`, which the test
> never invokes. (3) `LicenseManager.shared`'s lazy init eagerly builds
> `RemoteLicenseClient(baseUrl: Endpoints.licenseApiBaseUrl)`, and `Endpoints.swift:4-5` force-unwraps
> `Bundle.main.object(forInfoDictionaryKey: "Domain"/"ApiDomain") as! String`. The `unit-tests` target has
> `GENERATE_INFOPLIST_FILE = YES` and no `TEST_HOST`/`BUNDLE_LOADER` (`project.pbxproj:2473,2477`) → a
> standalone xctest bundle whose auto-generated Info.plist has no `Domain` key → **`fatalError` / crash**.
> (4) `!Endpoints.licenseApiBaseUrl.contains("alt-tab.app")` is trivially true once §3.1 repoints
> `API_DOMAIN` (and the base value is `alt-tab.app/api`, so the substring match is fragile anyway).
> Net: that test turns CI permanently red on **every** sync, not just on a relock.

Instead, **exercise the patched producer on a mock-injected instance** — exactly the pattern the existing
tests use (`LicenseManagerTests.setUp`, lines 11-19). Add these methods **to the existing
`src/pro/license/LicenseManagerTests.swift`** (already in the `unit-tests` Sources phase,
`project.pbxproj:1892`), so **no new file and no pbxproj edit** is needed, and the "zero pbxproj edits"
invariant stays literally true:

```swift
// alt-tab-free [depaywall]: anti-relock backstop. If a merge re-arms the paywall, these fail
// BEFORE build/sign/notarize (run_tests.sh runs the Test scheme before build_app.sh).
// Uses a fresh mock-injected manager (NOT LicenseManager.shared, which is never initialize()d in
// tests and would force-unwrap Bundle.main "Domain" in the host-less xctest bundle). All symbols
// here (LicenseManager, LicenseState, MockClock, MockKeychain, MockLicenseAPI) ARE in the unit-tests
// target; ProFeature is NOT, so do not reference it. Use the existing MockClock fixture (not
// SystemClock()) so the trial-expiry math is deterministic, not wall-clock-dependent.
// Use the EXISTING MockClock fixture (LicenseManagerTests.swift:475 — already in this file/target), NOT
// SystemClock(), so trial math is deterministic and not coupled to wall-clock time.
func testDepaywallProNeverLocked() {
    // LOAD-BEARING assert: on unpatched code a fresh MockKeychain → computeTrialState() → .trial(14),
    // so this fails iff the forced `return .pro` is missing.
    let m = LicenseManager(clock: MockClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
                           keychain: MockKeychain(),
                           api: MockLicenseAPI(),
                           defaults: UserDefaults(suiteName: "depaywall-\(UUID().uuidString)")!)
    m.initialize()  // routes through the patched computeState()
    XCTAssertEqual(m.state, .pro,
                   "PAYWALL RELOCKED: computeState() no longer returns .pro — refresh the de-paywall patch.")
}

// SECOND, DISCRIMINATING test: inject an EXPIRED trial so isProLocked is meaningful. On a fresh
// MockKeychain the day-0 trial is .trial(14) — for which isProLocked==false and isProAvailable==true
// REGARDLESS of the patch — so asserting them on a fresh manager proves nothing. Force a long-past
// trialStartDate (well beyond trialDuration=14) so the UNPATCHED computeTrialState() returns
// .trialExpired (isProLocked==true, isProAvailable==false); only the forced .pro makes these pass.
// MockClock pins "now" so the expiry is deterministic regardless of when CI runs.
func testDepaywallStillProAfterTrialExpiry() {
    let defaults = UserDefaults(suiteName: "depaywall-\(UUID().uuidString)")!
    defaults.set(Date(timeIntervalSince1970: 0).timeIntervalSince1970, forKey: "trialStartDate") // ~1970 → expired
    let m = LicenseManager(clock: MockClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
                           keychain: MockKeychain(),
                           api: MockLicenseAPI(),
                           defaults: defaults)
    m.initialize()
    XCTAssertEqual(m.state, .pro, "PAYWALL RELOCKED: expired trial no longer forced to .pro.")
    XCTAssertFalse(m.isProLocked, "PAYWALL RELOCKED: isProLocked true on an expired trial.")
    XCTAssertTrue(m.isProAvailable, "PAYWALL RELOCKED: isProAvailable false on an expired trial.")
}
```

A fresh `MockKeychain` has no license key, so on the *unpatched* code `computeState()` would fall to
`computeTrialState()` → `.trial` (day 0) and the assert on `.pro` fails loudly — i.e. the first test
genuinely detects a relock and passes only when the forced `return .pro` is present. **Verified subtlety:**
on a *day-0* trial `isProLocked == false` and `isProAvailable == true` even on unpatched code (`.trial`
returns false/true in `LicenseManager.swift:69` / `LicenseState.swift:8`), so asserting those two on a fresh
manager is **non-discriminating** — that is why the load-bearing assert is `state == .pro`, and the second
test injects an expired `trialStartDate` to make `isProLocked`/`isProAvailable` meaningful. It depends only on the chokepoint
*behavior* via the public producer, so it survives upstream refactors that don't re-lock. **Do not** call
`mockProUser()` (it is `#if DEBUG`; `run_tests.sh` builds `-configuration Release`, which strips DEBUG —
the call site would not compile). **Do not** reference `LicenseManager.shared`, `Endpoints.*`, or
`ProFeature.*` (the four traps above).

#### Guard B — target-independent CI grep (catches what a unit test structurally can't)

The `unit-tests` target deliberately excludes `ProFeature`/`ProTransitionManager`/`PreferenceDefinition`
(pure `*Testable` shims), so a unit test can only ever cover `LicenseManager`-level behavior. Add a
build-target-independent step to the fork's `ci_cd.yml` **as the FIRST step of the push job — before
`run_tests.sh` (line 53), and therefore before `update_appcast.sh` (57, Sparkle sign), `npx semantic-release`
(59, tag push), and `softprops/action-gh-release` (62)** — that fails the job if the forced flip is missing.
**Placement matters: a grep that runs only at line 62 fires after the tag is already pushed and the binary
already signed (see §4.4 "Where the guards run"), so it must run first to actually prevent a relock from
shipping. The grep is near-instant, so running it first is free:**

> **Verified pitfall — a bare `return .pro` grep matches the UNPATCHED file.** `computeState()` already
> contains `return .pro` at `LicenseManager.swift:187` (the keychain-valid branch) on a fully *relocked*
> tree, so `grep -Eq 'return[[:space:]]+\.pro'` passes even when the paywall is armed — it is **not**
> load-bearing. The **only** load-bearing grep is the `depaywall` marker. Make the forced-return check
> co-locate with the marker (e.g. require the marker line *and* an `if false` guard in the same file) so it
> actually distinguishes patched from unpatched:
>
```yaml
      - name: anti-relock — verify de-paywall marker present
        run: |
          grep -q 'alt-tab-free \[depaywall\]' src/pro/license/LicenseManager.swift \
            || { echo "PAYWALL RELOCKED: depaywall marker missing from computeState()"; exit 1; }
          # The marker proves the patch is present; pair with the if-false guard the wrap introduces.
          grep -Eq 'if[[:space:]]+false[[:space:]]*\{' src/pro/license/LicenseManager.swift \
            || { echo "PAYWALL RELOCKED: 'if false { … }' wrap missing from computeState()"; exit 1; }
```
> Do NOT rely on a bare `return .pro` grep (it matches the unpatched line 187).

#### Guard C — conflict-marker gate (keeps a conflicted tree from ever being published)

The §4.2 cron deliberately commits a **conflicted tree** (markers included, `--no-verify`) to the sync
branch and pushes it for a human to resolve. Nothing in the design otherwise guarantees the human's
resolution removed *every* marker before merge — and a markers-laden intermediate commit, if merged, becomes
a **permanent ancestor of the published tag**, contradicting §5(1)'s "the tag tree IS the Corresponding
Source" claim (you'd be shipping un-compilable source). Add a cheap tree-wide conflict-marker grep to BOTH
`guard.yml` (pre-merge) and `ci_cd.yml` **as a first push-job step — before `run_tests.sh`/`update_appcast.sh`/`semantic-release` (NOT merely before `softprops/action-gh-release`, which runs after the tag is
already pushed — §4.4 "Where the guards run")**:

```yaml
      - name: anti-conflict — no unresolved merge markers
        run: |
          if git -c grep.lineNumber=false grep -nE '^(<<<<<<<|=======|>>>>>>>)' -- . ':(exclude)docs/'; then
            echo "UNRESOLVED CONFLICT MARKERS present — resolve before merge/release"; exit 1
          fi
```
(Exclude `docs/` so this plan's own literal examples of markers don't trip it; tune the pathspec to taste.)
Define in §6.2 that conflict resolution **amends/replaces or squashes out the bot's `--no-verify` conflict
commit** so the published tag history is clean — the conflicted commit must not survive into `master`.

This avoids the pbxproj-membership and `Bundle.main`-plist pitfalls entirely and gives an extra-loud signal
a skipped/disabled unit test can't silently bypass. (The §2 endpoint surface — the
`<bundleid>://activate` handler, where the registered scheme is `$(PRODUCT_BUNDLE_IDENTIFIER)`, is
scheme-gated, not state-gated, so it stays live and POSTs the machine hardware UUID — is handled by
**neutralizing `handleCustomUrl`** (§2 default), independent of `API_DOMAIN`, not by a network assertion
here.)

#### Where the guards run — defense in depth (so a missing trigger can't unship the safety)

The guards are wired in **three** places so no single misconfiguration disarms them:

1. **`.github/workflows/guard.yml` (fork-owned, `on: pull_request`)** — runs Guard A (`run_tests.sh` or a
   focused `xcodebuild test`) + Guard B grep + Guard C conflict-marker grep. This is a SEPARATE workflow that does **not** inherit
   `ci_cd.yml`'s trigger, so an upstream `ci_cd.yml` conflict resolved "keep ours/theirs" that accidentally
   strips the `pull_request:` trigger cannot silently disable the PR gate. This is the reviewer's primary
   green/red signal.
   > **Guard A MUST run on `macos-15` (the pinned Xcode), NOT ubuntu.** `run_tests.sh` is
   > `xcodebuild test` — it only runs on a macOS runner with the §4.5/§6.1-pinned Xcode (`Xcode_26.0.1`). If
   > `guard.yml` is left on the cheaper `ubuntu-latest`, **Guard A silently degrades to grep-only** (the
   > xcodebuild step can't run), leaving the behavioral relock test unexecuted — the exact silent-disarming
   > class this plan is otherwise careful about. Split the workflow if you want speed: run Guard B/C greps on
   > `ubuntu-latest` (near-instant) as one job, and Guard A (`xcodebuild test`) on `macos-15` as a separate
   > job. **Bootstrap assertion:** on the deliberately-relocked acceptance PR (§4.2), confirm `guard.yml`
   > actually executed a *build+test* on `macos-15` (not just the greps) — i.e. Guard A produced a real test
   > result, red on the relock.
2. **`ci_cd.yml` `pull_request:` path (§4.2)** — the same guards, in the fork's main workflow, for the
   complete CI signal on the PR.
3. **`ci_cd.yml` push path, Guard B + Guard C greps wired in as the FIRST job steps — before `run_tests.sh`
   (line 53), and therefore unconditionally before `update_appcast.sh` (line 57, Sparkle `sign_update` +
   appcast `ITEM` append), `npx semantic-release` (line 59, which pushes the `vX.Y.Z` tag to `master`), and
   `softprops/action-gh-release` (line 62)** — the **release-time** backstop, placed so it aborts the job
   *before any irreversible side-effect.* This one is the safety net that makes the failure mode
   *fail-closed*: even if BOTH PR-trigger paths above were misconfigured or stripped, a relocked tree
   (Guard B) or a tree still carrying conflict markers (Guard C) aborts the run **before the tag is pushed and
   before any binary is signed.**
   > **WHY THE PLACEMENT IS LOAD-BEARING (verified `ci_cd.yml` ordering — this corrects an earlier draft).**
   > An earlier version of this plan placed Guard B/C "immediately before `softprops/action-gh-release` (line
   > 62)" and claimed that made *"even with no PR gate, a relock cannot ship."* **That claim was FALSE as
   > written.** Verified step order in the push job: `run_tests.sh` (53) → `update_appcast.sh` (57, which runs
   > Sparkle `sign_update` and appends the signed `ITEM` to the appcast feed) → `npx semantic-release` (59,
   > which via `@semantic-release/git` commits and **pushes the `vX.Y.Z` tag to `master`**) → `extract_latest_changelog.sh` (61) → `softprops/action-gh-release` (62). So a grep firing only at line 62 runs
   > **after** the tag is already an immutable ancestor of `master` and **after** the binary is already
   > EdDSA-signed and the appcast entry written — i.e. the exact §5(1) "shipping un-compilable Corresponding
   > Source" / paywalled-relock outcome has *already happened* before the grep fires; only the GitHub Release
   > *object* and the website dispatch would be blocked, not the tag push or the in-process appcast signing.
   > Because Guard B/C are target-independent greps that run in well under a second, **running them as the
   > job's first steps costs nothing** and is the only placement that makes the "cannot ship" guarantee
   > literally true (the job aborts pre-tag-push, pre-sign). **Keep a second copy of the greps immediately
   > before `action-gh-release` (line 62) as belt-and-suspenders**, but the load-bearing copy is the one at
   > the top of the job.

   State this explicitly: *Guard B + Guard C run as the first push-job steps, before `run_tests`/`update_appcast`/`semantic-release`, so even with no PR gate a relocked or conflict-laden tree aborts the
   job before the tag is pushed or the binary signed — it cannot ship.* The §6.2 runbook adds a recurring
   check that the `pull_request:` trigger still exists post-merge, so the pre-merge layers don't silently rot.

#### Per-release feature-unlock acceptance check (positive proof the gates are actually open)

Guard A asserts only at the `LicenseManager` layer and Guard B/C are greps — but §2 itself warns the
gate-*consumers* (`ProFeature` / `PreferenceDefinition` / `ShortcutAction` / `TilesView`) are **NOT in the
`unit-tests` target** and can silently re-lock while Guard A stays green (a new entitlement check, a gate
re-pointed off `state`, a new `LicenseState` case). The compile + Guard A **provably cannot** cover those
consumers. Close the gap with a short **positive** acceptance checklist on each release — confirm each
headline Pro feature is actually FREE in the BUILT app, not just that `state == .pro` in a mock:
- Assign a **9th+ custom shortcut** (free users were hard-capped at 1 — `AUDIT.md`/`ControlsTab.swift`).
- **Type-to-search** in the switcher works.
- A **Pro appearance style** (e.g. a gated `appearanceStyle`/`appearanceSize`) is selectable and sticks.
- At least one other gated feature from the §4 audit list of your choosing.
- **No inert Pro UI renders an "AltTab" brand string** — since §2 Edit-5 deliberately leaves some inert
  upsell UI present-but-unreachable, spot-check that no still-visible Pro surface (e.g. a residual "Get Pro"
  menubar item) shows the upstream product name. If one does, either it is reachable (a relock/feature bug)
  or the §3.2 inert-UI-unreachable assumption is wrong — both warrant action.
This is manual or UI-level (XCUITest if the owner wants it automated later); it is fast and it is the only
layer that exercises the consumers end-to-end. The §6.2 gate-consumer review (step 5) is promoted from
conditional-manual to a **mandatory per-release item** for the same reason — see §6.2.

### 4.5 Effort estimate

| Case | Frequency | Per-sync effort | What happens |
|---|---|---|---|
| **Cold path** (chokepoints untouched) | Overwhelming majority — 34/34 commits since v11.0.0 left all four at zero edits | **~5–15 min, mostly review** | Cron opens a clean (or identity-only-conflict) PR; maintainer resolves any `local.xcconfig`/`Info.plist`/CI/`update_appcast.sh`/`release.config.js` collisions ("keep ours"), confirms green CI incl. anti-relock test + grep, merges. Pipeline auto-releases. **If the sync touched any `src/*.swift` with `NSLocalizedString` (e.g. an upstream string change near a swept literal), re-run `scripts/l10n/extract_l10n_strings.sh` and commit the regenerated `resources/l10n/*.strings` or the `ensure_generated_files_are_up_to_date.sh` gate (`ci_cd.yml:49`) fails the PR.** |
| **Identity-conflict subset** | Whenever upstream edits a line the fork also changed | included above | `git checkout --ours` on those files, re-confirm fork URLs/keys, commit. No code logic. |
| **Chokepoint-moved path** | Rare — zero so far | **~30–90 min** | Merge halts in the chokepoint file (loud, by design). Re-apply de-paywall intent, run anti-relock test locally until green, commit. The test guarantees a mis-resolution can't ship. |
| **l10n-regeneration (BASELINE, not a caveat)** | Recurs whenever a sync touches any of the ~18 swept `src/*.swift` files near an `NSLocalizedString`, or the `.strings` files | **+ time per affected sync** | The §3.2 string sweep makes ~18 `src/*.swift` files + l10n entries **warm**. `ensure_generated_files_are_up_to_date.sh` (`ci_cd.yml:49`) **hard-fails on any uncommitted regenerated diff**, and the regeneration must byte-match upstream's output — so the **fork runner's Xcode/`genstrings` must match upstream's pinned Xcode** (`ci_cd.yml:45`, `Xcode_26.0.1`). Re-run `scripts/l10n/extract_l10n_strings.sh` and commit the regenerated `resources/l10n/*.strings` before pushing. **Minimize the sweep** to shrink this warm surface. |

> **Baseline note:** the l10n-regeneration cost above is a *consequence of the trademark sweep* and recurs
> on the cold path too — it is part of the steady-state baseline, not a rare edge case. Pinning the fork
> runner's Xcode to upstream's (`ci_cd.yml:45`) and keeping the sweep minimal are the levers that keep it
> cheap.

> **CI-minutes note (macOS-runner cost per sync, not wall-clock effort).** Guard A in `guard.yml` runs
> `xcodebuild test` on **`macos-15`** (§4.4 layer 1), and the `ci_cd.yml` PR path builds too — macOS runner
> minutes are ~10× the ubuntu rate on GitHub-hosted runners. Every sync PR therefore consumes a macOS build,
> and a re-pushed conflict resolution consumes another. The §4.2 cron Guards 1/2 (skip already-merged tags;
> don't re-open while a PR is open) are what keep this from multiplying into a daily no-op macOS build —
> without them the daily cron would burn a macOS build every day. Budget for "a macOS build per sync PR plus
> re-pushes," and keep the greps on `ubuntu-latest` so a relock fails before the expensive macOS job starts.

### 4.6 Credential / cert / Sparkle-key lifecycle (periodic overhead, independent of merge cadence)

The merge loop is not the only recurring cost. Three credentials expire or can break on their own clock,
**unrelated to upstream activity**, and an unhandled lapse silently breaks releases or auto-update. Track
them as a separate "periodic overhead" bucket (fold into the §4.5 effort picture, do not hide inside the
per-merge estimate):

- **Developer ID Application cert (~yearly) + Apple Developer Program membership (yearly) +
  app-specific password.** On expiry, notarization/signing fails and no release can be cut. **On cert
  rotation:** re-export the new p12 → base64 → update the `APPLE_P12_CERTIFICATE` secret in the `production`
  Environment, and **re-sign + re-notarize** — note this **intersects the §3.3 Sparkle helper re-sign**: the
  bundled `vendor/Sparkle/Helpers/*` must be re-signed under the *new* cert too, or the nested-Mach-O
  `TeamIdentifier` check fails. Keep the AGENTS.md identity invariant in mind: the **TeamID/bundle id stay
  frozen** across cert renewals (a renewed cert under the same Team is fine; a *new Team* orphans every
  user's keychain/identity).
- **Sparkle EdDSA key — break-glass plan (there is no clean rotation).** The public key is baked into shipped
  binaries (`Info.plist:62 SUPublicEDKey`); a **compromised or lost private key cannot be rotated without
  orphaning every already-installed client**, because existing installs only trust the embedded public key
  and will reject an appcast signed by a new key. **Plan:** store `SPARKLE_ED_PRIVATE_KEY` durably (the loss
  case is unrecoverable), and document that recovery from a lost/compromised key requires shipping a
  **hard-coded migration build** out-of-band (a new download users must install manually, carrying the new
  public key) — auto-update cannot bridge the gap. This is a known, accepted single point of failure;
  back up the key.
- **Notarization credential drift.** `APPLE_ID` / `APPLE_PASSWORD` (app-specific password) get revoked when
  the Apple ID password changes or the app-specific password is regenerated; refresh the secret when that
  happens, or `package_and_notarize_release.sh` fails at the notarytool step.
- **Sync-bot credential (`SYNC_BOT_TOKEN`) — a new silent SPOF (§4.2).** The GitHub App installation token /
  PAT that authors the sync push + PR expires (PATs on their set lifetime; App tokens auto-rotate but the App
  install can be revoked). On expiry the cron's push/PR-create starts failing — but **the more dangerous
  failure is silent**: if it falls back to (or is mis-set to) the default `GITHUB_TOKEN`, the PR still opens
  but **runs no checks** (the §4.2 blocking issue). Prefer the short-lived, least-privilege GitHub App token
  over a classic PAT (a leaked PAT can push to `master`). **Rotation runbook (a botched swap silently
  degrades to the default `GITHUB_TOKEN` — the §4.2 blocking failure — so do it deliberately):**
  - **PAT:** set a **calendar reminder ahead of the PAT's expiry** (with lead time) to mint the replacement,
    swap the `SYNC_BOT_TOKEN` secret, and confirm the cron's next run still opens a PR with **live** checks —
    so there is no window where the cron silently falls back to `GITHUB_TOKEN`. Never let it expire unattended.
  - **GitHub App installation token:** the token auto-rotates, but the *App install / permissions* can be
    revoked or narrowed. **After any change to the App's installation or permissions, re-run the §4.2
    acceptance test** (open a bot PR; confirm `guard.yml`/`ci_cd.yml` PR checks actually appear) — a silently
    de-permissioned App produces a PR with no checks, exactly the disarmed-gate failure.
  Either way, the §4.2 acceptance test (a bot PR must show live checks) is the canary, and it is part of the
  §4.6 positive heartbeat (above).

**Cadence:** review these once per quarter (a calendar reminder), and unconditionally on any release failure
at the sign/notarize/appcast steps.

> **POSITIVE loop-health heartbeat (consolidate the ~6 silently-failing mechanisms into one monitored
> surface).** The steady-state loop depends on at least six independent pieces that each fail *silently*:
> the `SYNC_BOT_TOKEN` expiring (§4.2), the in-repo `schedule:` auto-disabling after 60 days (§4.2), the
> fork-runner Xcode pin drifting from upstream (§4.5), the Developer ID cert / Sparkle key lapsing (§4.6),
> commitlint `ignores` going stale (§4.3), and the Sparkle-helper re-sign being missed on a bump (§3.3). The
> §4.2 liveness alert is **absence-only** — it fires when a PR *doesn't* appear — and so **cannot distinguish
> "healthy and quiet" from "the alerting job itself died."** Add a single **positive** heartbeat that must
> *affirmatively* report green on a schedule (a monthly issue comment or a status badge), proving: (1) the
> cron fired within the last N days; (2) the most recent bot PR had **live** `guard.yml`/`ci_cd.yml` checks
> attached (the §4.2 token canary); (3) the Developer ID cert, Apple membership, and notarization credential
> are not within X days of expiry; (4) the fork runner's Xcode pin matches upstream's `ci_cd.yml` value. A
> heartbeat that goes *quiet* is itself the alarm (a dead monitor is observable), which absence-only alerting
> can never achieve — and it doubles as the §0.2 successor-handoff "is this loop actually healthy?" dashboard.

---

## 5. GPL-3 compliance recap

The work remains GPL-3.0 (AltTab is GPL-3.0; see `docs/PLAN-republish-free.md` §A for the full treatment,
which this plan does not duplicate).

> **Which license actually governs — resolve the GPL-vs-MIT contradiction (do not leave it implicit).**
> `LICENCE.md` is verbatim GNU GPL v3, but `package.json:6` declares `"license": "MIT"` **for the application
> itself** (name `alt-tab-macos`, not a dependency) — a conflicting, machine-readable, public license artifact
> (most plausibly a stale `semantic-release`/npm scaffold default that upstream never reconciled). Every
> obligation below rests on "this is GPL-3.0," so the plan must reason to that conclusion *against* the in-repo
> statement that says otherwise: an unaddressed MIT declaration muddies which terms govern, hands the upstream
> author a colorable "licensing is ambiguous / the tooling says MIT" argument in a C&D, and is exactly what a
> GitHub DMCA reviewer would surface.
> - **Documented position (the basis for §5 below):** the GPL-3.0 `LICENCE.md` **plus** the in-app
>   `NSHumanReadableCopyright = "GPL-3.0 licence"` notice (`Info.plist:21`, surfaced via `App.licence`) govern
>   the *software*; the `package.json` `license` field is a stray scaffold value, not a grant of MIT terms to
>   the application.
> - **Fork's corrective (bootstrap, §6.1):** set the fork's `package.json` `license` to `"GPL-3.0"` to match
>   the actual grant, and add `package.json` to the §6.2 **"keep ours"** recurring set so a future merge cannot
>   re-introduce the MIT string.
> - **Which grant to carry forward:** the bare **`GPL-3.0`** the in-app notice states is the safe floor. Do
>   **not** assume an "or-later" relicensing right unless upstream's intended "version 3 only" vs "version 3 or
>   later" can be confirmed from an authoritative source — inventing an "or-later" right would itself be a
>   licensing misstatement.

The three obligations, briefly:

1. **Keep it open / same license.** The fork's source stays public under GPL-3.0; ship the corresponding
   source for every binary released. Keep `LICENCE.md` **byte-for-byte** (never edit). **§6
   corresponding-source mechanic (corrected):** the release asset is **binary-only** — `ci_cd.yml:66`
   attaches `files: ${{ env.XCODE_BUILD_PATH }}/*.zip` (the notarized `.app` only), and
   `update_appcast.sh:18` points the Sparkle enclosure at that same binary zip. **The binary enclosure URL
   does NOT convey source.** The §6(d) corresponding-source *vehicle* is **GitHub's auto-generated
   "Source code (tar.gz)" snapshot at the SAME release tag** as the binary.
   - **Make source-equivalence guaranteed, not asserted (the naïve "tag tree == built sources" claim is
     FALSE as the repo ships).** Verified: `scripts/replace_environment_variables_in_app.sh` does a
     truncating `cat > config/local.xcconfig` writing `CURRENT_PROJECT_VERSION` + `APPCENTER_SECRET` at build
     time, and `config/local.xcconfig` is `.gitignore`'d (`.gitignore:20`) — so the upstream tag tree is
     *missing* a build input Xcode consumes, and the §3.1 plan to *commit* `local.xcconfig` collides with that
     truncating write. Close the gap with the §3.1 fixes so the equivalence actually holds:
     (a) **commit `config/local.xcconfig`** (un-gitignore per §3.1) so the identity/build config is in the
     tag tree; (b) **make CI append-not-clobber** (§3.1 — write only `CURRENT_PROJECT_VERSION`, drop the
     `APPCENTER_SECRET` line) so the build does not overwrite the committed block with an out-of-tree value;
     (c) state that the ONLY build inputs deliberately NOT in the tag are **secrets** — the Developer-ID
     signing cert, the Sparkle EdDSA private key, and the Apple notarization credentials — which GPL does not
     require to be conveyed.
   - **Therefore the precise claim is:** *"the tag tree plus the committed build config IS the Corresponding
     Source; only signing/notarization secrets differ"* — not "the tag snapshot equals the built sources."
   Satisfy GPL-3 **§6(d)**'s "clear directions next to the object code saying where to find the Corresponding
   Source" by **injecting a source pointer into BOTH §6(d) conveyance channels** (GitHub Release AND Sparkle,
   since each is an independent object-code delivery path): (a) the **Sparkle** appcast
   `<sparkle:releaseNotesLink>`/description (rewritten in §3.3) and (b) the **GitHub Release** body — the
   `extract_latest_changelog.sh` output that feeds `softprops/action-gh-release`'s `body` (`ci_cd.yml:60-65`),
   e.g. `Corresponding source: https://github.com/<fork>/archive/refs/tags/v$version.tar.gz`. The Sparkle
   pointer is non-optional: users who receive object code **only via auto-update** (`SUEnableAutomaticChecks`,
   `SUScheduledCheckInterval=604800`) otherwise get a §6(d) object-code delivery with no source pointer at all.
   - **Conveyance durability — do NOT rely on the transient §6(d) auto-tarball alone (decision required).**
     **One event — a repo/org takedown (the C&D scenario the §5 risk note flags) — triggers THREE coupled
     failures at once:** (1) the GitHub auto-tarball `…/archive/refs/tags/v$version.tar.gz` vanishes, (2)
     every already-auto-updated client is left pointing at that now-dead source location — a **persisting GPL
     §6 violation after the fact** (the obligation outlives the repo), and (3) clients keep pinging a now-dead
     appcast and silently stop updating. The mitigation must therefore put **both the source mirror AND the
     appcast host on infrastructure NOT tied to the takedown-able GitHub repo/org** (a separate host/org, a
     CDN, or a software-archive), so a takedown degrades the fork to **"stale, not retroactively
     non-compliant"** (§0.2) rather than knocking out source, updates, and compliance together. Harden it:
     - **(preferred where practical) Convey source under §6(a)/(b):** attach the **source tarball as a
       release asset** alongside the `.app` `.zip` (so the source physically *accompanies* the object code on
       the same release), e.g. `git archive --format=tar.gz -o <fork>-v$version-src.tar.gz "v$version"`
       added to `softprops/action-gh-release`'s `files:`. This survives even if the auto-tarball endpoint
       changes, because the source is a first-class asset of the same release.
     - **And/or, if relying on §6(d):** commit in the runbook to keeping the source location **live for at
       least as long as any released binary is still offered or auto-updatable** (GPL §6(d) requires the
       source stay available as long as you convey the object code), plus a **takedown-contingency mirror**
       (a second host / org / archive) so the pointer survives a repo takedown. Note in §6.2 that a repo
       rename/move requires re-pointing or preserving the old source URLs the shipped binaries already carry.
2. **Attribution + note changes + prominent notices + in-app legal notices.** Retain lwouis's copyright;
   state prominently in `README.md` and the in-app About tab that this is a fork of `lwouis/alt-tab-macos`
   © Louis Pontoise, GPL-3.0, that the Pro paywall has been removed (all features free), and that it is not
   affiliated with or endorsed by the original author (§3.2).
   - **GPL §5(a) change-marking — a LIVING document, not a one-time file:** the `depaywall:` commit prefixes
     alone are thin. Add a top-level `NOTICE.md` (none exists in-tree today; `changelog.md` is the
     auto-generated semantic-release file and is not a substitute) stating: *"Forked from lwouis/alt-tab-macos
     v11.x; removed the Pro paywall. Changed: `LicenseManager.computeState` (forced `.pro`), `syncLicenseCookie`
     (no-op), `AppCenterCrash.init` (telemetry off). Date: <date>."* **GPL §5(a)'s "carry prominent notices
     stating that you modified it, and giving a relevant date" goes STALE if the fork's modification surface
     grows** (e.g. a `FeedbackWindow` rewrite per §3.4, a new edit forced by a chokepoint refactor). Add a
     §6.2 runbook step: whenever a sync changes the fork's *modification surface* (not on every routine sync),
     update `NOTICE.md`'s change list and date. The `pop--release-notes`/changelog is not a substitute — it
     records versions, not the GPL §5(a) modification statement.
   - **GPL §5(b) — "prominent notices stating that it is released under this License":** `README.md` and
     `NOTICE.md` must state the fork is released under GPL-3.0.
   - **GPL §5(d) — interactive UIs must "display Appropriate Legal Notices" (compliance CHECK, not a
     cosmetic repoint):** the only in-app legal string today is `App.licence` (`App.swift:15`, sourced from
     `Info.plist:21` `NSHumanReadableCopyright = "GPL-3.0 licence"`), surfaced by `AboutTab.swift:17`. After
     the `App.swift:16` `repository` repoint (§3.5), **verify** that AboutTab still renders the GPL notice
     (`AboutTab.swift:17` → `App.licence`) **and** that the "Source code" `HyperlinkLabel`
     (`AboutTab.swift:19` → `App.repository`) now points at the FORK's source — that link is also the in-app
     §6 source pointer (§3.5), so a fork-repoint here is a *required* compliance step, not cosmetics.
3. **Trademark / non-confusion.** Rebrand name, bundle id, icon, and update feed (§3) so the fork is not
   passed off as the original. **GPL-3 §7(e) clarifies that trademark rights are NOT conveyed by the
   copyright license — so renaming is required under trademark law *independent of* GPL, not merely
   "permitted" by it.** **`PRODUCT_NAME` is not sufficient** — of the **63 total `grep` hits** for "AltTab"
   in `src/*.swift` (~25 are non-rendering comments), the rendered surface is **~21 `NSLocalizedString`
   literals** plus **18 translatable `Localizable.strings` entries** (2 of the 20 lines are comments); these
   render verbatim and ARE the trademark-confusion surface. The §3.2 string sweep is the actual mitigation
   (mind the `src/pro/*` strings and the `PreferencesMigrations.swift:363` stored-value KEY that must NOT be
   renamed — §3.2); without it the "rebrand" premise is false.

> **Risk note (non-legal-advice):** redistributing a de-paywalled build of lwouis's *current commercial*
> product invites cease-and-desist / takedown pressure even where GPL-permitted, and residual `AltTab`
> trademark strings sharpen that lever. Make the C&D posture actionable:
> - The §3.2 string sweep + a **"not affiliated with / not endorsed by the original author" disclaimer in
>   README, the in-app About tab, AND release notes** are the core mitigations.
> - The **§3.3 Sparkle helper re-sign is also a trademark/origin mitigation** — shipping lwouis-signed
>   helpers (TeamID `QXD7GW8FHY`) inside a fork-branded app misrepresents the binary's origin; re-signing
>   under the fork's Developer ID removes that.
> - Be **DMCA counter-notice ready** (GPL-3 redistribution is a lawful basis), and keep the GPL §6
>   corresponding-source link (§5(1)) and §5 attribution current so a takedown can be rebutted on the merits.
> - **Bundle-id consequence (no migration story exists):** changing `PRODUCT_BUNDLE_IDENTIFIER` (§3.1) makes
>   the fork a *separate app* — existing AltTab users' `UserDefaults`/keychain prefs are **NOT inherited**,
>   and this plan defines no migration. Freeze the fork bundle id once (the keychain-suite invariant, §3.1)
>   and disclose to users that it is a fresh install, not an in-place upgrade of AltTab.
>
> The owner should accept this exposure consciously before publishing.

See `docs/PLAN-republish-free.md` §A for "what you MUST do / MUST NOT do" specifics.

---

## 6. Bootstrap checklist + per-sync runbook

### 6.1 One-time bootstrap

- [ ] **OWNER SIGN-OFF — conscious go/no-go on redistributing a de-paywalled build (gate everything below
  this).** This is the single highest-level decision in the plan and is a *legal/posture* call, not a
  technical one: the fork **knowingly redistributes a de-paywalled build of lwouis's current commercial
  revenue product.** GPL-3 permits it (§5), but it invites C&D / takedown pressure (§5 risk note). Before any
  other bootstrap work, the owner must explicitly accept this exposure and the mitigations (§3.2 brand sweep,
  the "not affiliated / not endorsed" disclaimer in README + About + release notes, DMCA counter-notice
  readiness, the §5 off-repo source-mirror + appcast-host durability so a takedown degrades to "stale" not
  "non-compliant"). Record the decision (and date) — do not let it remain implicit prose.
- [ ] **Upstream remote:** `git remote add upstream https://github.com/lwouis/alt-tab-macos.git && git fetch upstream --tags`.
- [ ] **De-paywall patch (3 commits, prefixed `depaywall:`):** Edit 1 `LicenseManager.computeState()` — wrap body in `if false { … }`, then `return .pro`; Edit 2 `LicenseCookie.syncLicenseCookie` — wrap body in `if false { … }`; Edit 3 `AppCenterCrash.init` — wrap lines 11-20 in `if false { … }`. **Use the `if false` wrap, NOT a bare `return` above live code** — `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (`base.xcconfig:7`) makes "code after return" a build error. Build and confirm clean. Keep the literal token `depaywall` in the `computeState()` comment (Guard B greps for it).
- [ ] **`activate` fingerprint neutralization (§2 default — independent of `API_DOMAIN`):** add the 1-line `handleCustomUrl` early-return that drops the `activate` host, so the still-live, scheme-gated `<bundleid>://activate` handler (`App.swift:474-481`) can't POST the **machine hardware UUID** (`RemoteLicenseClient.swift:18`→`MachineFingerprint.swift:13`) anywhere — including to the fork's own backend. **Do NOT rely on a non-routable `API_DOMAIN` for this** (it silently re-arms if feedback option (a) makes `API_DOMAIN` routable). This is a one-time bootstrap edit, not per-merge.
- [ ] **Feedback decision (§3.4 — now decoupled from `activate`):** choose the `API_DOMAIN` value purely on feedback: (a) fork-owned feedback backend (routable — safe now that `activate` is closed at the handler), (b) rewrite `FeedbackWindow` to open a client-side `github.com/<fork>/issues/new?…` URL (a real warm-file edit), or (c) hide feedback. A non-routable `API_DOMAIN` disables the feedback feature; pick consciously. **RECOMMENDED DEFAULT: (c) hide feedback** — it is the lowest *recurring* merge surface. Option (b) makes `FeedbackWindow.swift` a warm fork-edited file that conflicts whenever upstream touches it (eroding the merge-clean economics); option (a) is the most ongoing work (a backend to run). Adopt (a)/(b) only if the owner explicitly wants in-app feedback to keep working and accepts the recurring cost.
- [ ] **Identity overlay:**
  - [ ] Un-ignore: remove `/config/local.xcconfig` from `.gitignore:20`, then create + commit `config/local.xcconfig` (`PRODUCT_NAME`, bundle id, `DOMAIN`, `API_DOMAIN`, `CODE_SIGN_IDENTITY`, empty `APPCENTER_SECRET`).
  - [ ] **`APP_NAME` = `PRODUCT_NAME`:** set `ci_cd.yml:19` `APP_NAME` to the fork name (build/package/appcast scripts depend on it — §3.1).
  - [ ] Replace `README.md` (GPL-3 + fork attribution); add the credit line to the About tab. Add a top-level `NOTICE.md` (GPL §5(a) change-marking — §5; keep it current per §6.2 when the modification surface grows).
  - [ ] **`package.json` license correction (§5 — resolve the GPL-vs-MIT contradiction):** set `package.json:6` `"license"` from `"MIT"` to `"GPL-3.0"` so the machine-readable metadata matches `LICENCE.md` and the in-app GPL notice. Add `package.json` to the §6.2 "keep ours" recurring set so a merge cannot re-introduce the MIT string.
  - [ ] **Attribution-preserve set (§3.5 — keep verbatim, do NOT sweep/delete):** confirm the FOUR binding surfaces are intact — (a) `LICENCE.md` byte-for-byte; (b) `Info.plist:21` `NSHumanReadableCopyright = "GPL-3.0 licence"` (surfaced via `App.licence`/`AboutTab.swift:17`); (c) the README/About-tab "fork of `lwouis/alt-tab-macos`, © Louis Pontoise, GPL-3.0" credit; (d) `docs/contributors.md` + `docs/acknowledgments.md` (the latter also rendered in-app via `AcknowledgmentsTab.swift`). **NOTE: AltTab uses NO per-file copyright headers (verified — `App.swift` opens with `import Cocoa`); there is nothing to "preserve" per-file, so do NOT add a fork-only copyright header to source files (that WOULD risk §8 termination by displacing upstream attribution).** The §3.2 brand sweep touches product-name strings ONLY — never author-name attribution / contributor names / "fork of AltTab" (nominative fair use, required by §5). Stripping or displacing any of (a)-(d) breaches the attribution terms and can trigger termination under GPL §8 — which (per `LICENCE.md`) also provides for cure and reinstatement once the violation is corrected, so the never-strip rule stands on its own merits without relying on cure.
  - [ ] **`.github/FUNDING.yml` (§3.5):** `git rm` it OR rewrite to the fork's own sponsorship (currently routes `github`/`patreon`/`ko_fi`/PayPal to lwouis). Add to the §6.2 "keep ours" recurring-conflict set.
  - [ ] **Support/donation disposition (§3.4):** decide whether `<DOMAIN>/support` (drives `Endpoints.supportUrl` + the in-app "Support" item) serves a real page or is removed/accepted-as-404 — separate from FUNDING.yml.
  - [ ] **Trademark string sweep (§3.2):** sweep the rendered "AltTab" surface — **~21 `NSLocalizedString`
    literals** + plain literals (MainMenu.swift:65/76/260, FeedbackWindow.swift:100/239, Menubar,
    SettingsWindow, AboutTab:153, AppearanceTab:157, PermissionsWindow:36/50, MoveToApplicationsFolder:184,
    CustomRecorderControl:110, …) — and the **18 translatable entries** in
    `resources/l10n/Localizable.strings` (20 lines, 2 comments; + every `*.lproj` copy); prefer routing
    through `App.name`. **DECIDE on the `src/pro/*` AltTab strings** (UpgradeTab:116, ProPromptWindow:12,
    Day1/Day15/Day21 windows, ProTransitionManager:35, ProConversionCopy:32/39): **RECOMMENDED DEFAULT —
    prove the inert Pro UI is genuinely unreachable once `state == .pro`** (the nag windows are
    nag-scheduled, which never arms; verify no other entry point renders them), and leave the `src/pro/*`
    strings untouched. Sweeping them is a **direct exception to this plan's own "never edit `src/pro`"
    invariant** (§2/§5) and re-introduces the `src/pro` merge surface the whole strategy avoids — adopt it
    only if a reachable inert-Pro string is actually found. **Do NOT rename `PreferencesMigrations.swift:363`
    `"Screen showing AltTab"` (stored-value migration KEY).** Then
    run `scripts/l10n/extract_l10n_strings.sh` and commit the regenerated `resources/l10n/*.strings` (else
    the `ensure_generated_files_are_up_to_date.sh` gate, `ci_cd.yml:49`, fails). Consider a CI grep gate to
    keep the sweep durable across merges.
  - [ ] **GPL §6 source link:** edit `src/App.swift:16` `repository` → fork's GitHub URL (in-app "Source code" link / Feedback `/issues`); see §3.5.
  - [ ] Overwrite `resources/icons/app/app.icns` + regenerate `app.iconset/*`.
  - [ ] `Info.plist:62` `SUPublicEDKey` **value** → fork's EdDSA public key (the `<key>` is on :61). **Do NOT** swap `Info.plist:37` `NSPrincipalClass` (value = `AppCenterApplication`, which `App` subclasses; swapping breaks the subclass chain — not equivalent to Edit 3 — §3.4).
- [ ] **Sparkle keypair:** obtain `generate_keys` (NOT vendored — `vendor/Sparkle/bin/` has only `sign_update`; download the Sparkle 2.9.1 tarball per `update_sparkle.sh:14`, or `brew install --cask sparkle`, or temporarily un-drop it in `update_sparkle.sh` step 10), run it; public key → `Info.plist:62` value; private key → CI secret `SPARKLE_ED_PRIVATE_KEY`.
- [ ] **Re-sign bundled Sparkle helpers (MANDATORY for notarization — §3.3):** re-sign `vendor/Sparkle/Helpers/Updater.app` + `vendor/Sparkle/Helpers/Autoupdate` under the FORK's Developer ID (currently lwouis QXD7GW8FHY), re-commit, and verify `codesign -dvv vendor/Sparkle/Helpers/Updater.app` shows the fork's TeamIdentifier. **These vendored binaries are what `scripts/copy_sparkle_helpers.sh` embeds into `Sparkle.framework` at build time** (it re-seals the framework with the fork identity but does NOT re-sign the nested helpers — §3.3), so the vendored re-sign is load-bearing. **Post-build verification (REQUIRED):** `codesign -dvv` the `Sparkle.framework/Versions/A/Updater.app` INSIDE the built `.app`, plus `codesign --verify --deep --strict` on the `.app` and a `notarytool` dry run. Re-do per Sparkle bump. **Add a REQUIRED CI gate** that fails the build if any nested Mach-O's TeamIdentifier ≠ `APPLE_TEAM_ID`.
- [ ] **appcast out-of-tree (coupled — §3.3, all three):** (a) `git rm appcast.xml` + `/appcast.xml` in `.gitignore` + set up the publish host that serves `https://<DOMAIN>/appcast.xml` (gh-pages + CNAME, or accept a `github.io` `DOMAIN`); (b) rewrite `scripts/update_appcast.sh` to append to the gh-pages feed copy (not in-tree, `set -exu` would hard-fail on the removed file), fixing the enclosure URL on **line 18** → fork releases (safety-critical) and the `releaseNotesLink` on **line 16**; (c) remove `'appcast.xml'` from the `@semantic-release/git` `assets` array in `release.config.js` (lines 20-26).
- [ ] **Fork-to-fork auto-update acceptance (§3.6.1 — prove the republish loop reaches EXISTING users):** before relying on the loop, install fork release **N**, publish a throwaway release **N+1**, and confirm the running app **auto-updates N→N+1 cleanly** — (1) Sparkle resolves the enclosure to the *fork's* release (not lwouis's), (2) the EdDSA signature **verifies against the embedded fork `SUPublicEDKey`**, (3) `sparkle:version` ordering is monotonic over the `v100.0.0` offset, (4) Gatekeeper is the only friction. A silent failure here strands every existing fork user on a stale build with no signal. This is the upgrade analogue of the feature-unlock check.
- [ ] **Bundle-id / in-place-upgrade decision (§3.1 owner decision):** choose (a) FRESH bundle id (default — fresh install, no migration, disclose to users) or (b) reuse an existing id WITH a one-time `proTransition.remembered*` → base-key migration (else paywalled-build users silently lose their Pro selections). Freeze the choice. **(Distinct from the §3.6.1 fork-to-fork auto-update above: that is fork-N→fork-N+1 for the fork's own users; this is the AltTab→fork one-time cutover for legacy upstream users.)**
- [ ] **Fork version-offset (§4.3 — bake in, don't defer):** start the fork's semantic-release line at `v100.0.0` (or set a `fork-vX.Y.Z` `tagFormat`) so a future `git merge v11.X.0` can never collide with a fork tag of the same name.
- [ ] **Developer ID:** obtain the fork owner's Developer ID Application cert; freeze bundle id + TeamID (license-keychain invariant). Export p12 → base64 → CI secret.
- [ ] **Credential lifecycle tracking (§4.6):** record expiry dates for the Developer ID cert (~yearly), the Apple Developer Program membership, and the app-specific password; back up `SPARKLE_ED_PRIVATE_KEY` durably (a lost/compromised Sparkle key has no clean rotation — recovery needs a hard-coded migration build). Set a quarterly review reminder.
- [ ] **CI secrets + Environment + permissions (§4.3):** create a GitHub **Environment named `production`** (matches `ci_cd.yml:23`) with no blocking required-reviewers, and attach `APPLE_P12_CERTIFICATE`, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`, `SPARKLE_ED_PRIVATE_KEY` there. Add `permissions: { contents: write }` to the fork's `ci_cd.yml` (else semantic-release push + gh-release 403). Leave `APPCENTER_*` and `WEBSITE_DISPATCH_TOKEN` unset.
- [ ] **Fork CI:** adapt `ci_cd.yml` — **decide on node:** either KEEP `node-version: 16` (the `package.json` `>=18` mismatch only *warns* under `npm ci`, no hard-fail) OR bump to ≥18 *as a coordinated toolchain upgrade* of `semantic-release`/commitlint/husky (§4.3 — do NOT bump node alone, the pinned v15 semantic-release / v8 commitlint were never validated on node 18/20 and run on the release path); drop `upload_symbols_to_appcenter.sh` + `update_website.sh`; `softprops/action-gh-release` → fork repo; fix `replace_environment_variables_in_app.sh` so it preserves the committed `local.xcconfig` identity block (§3.1 — write only `CURRENT_PROJECT_VERSION`, append, and drop its `APPCENTER_SECRET` line); fix `commitlint` via `commitlint.config.js` `ignores` (PRIMARY — §4.3; do NOT use `--from HEAD~1 --to HEAD`, which is broken over a `--no-ff` merge — use `--last` if a one-message range is wanted); add the `pull_request:` trigger + `if: github.event_name == 'push'` gates on the COMPLETE release-step set including `commitlint` and `determine_next_version` (which misbehave on PR events — §4.2) so the anti-relock guards run pre-merge and the PR check is cleanly green/red. **Acceptance test:** open a PR that reverts the `computeState()→.pro` flip and confirm the PR check goes RED before merge.
- [ ] **Pin the fork runner's Xcode to upstream's value (BOOTSTRAP INVARIANT, not a lever — §4.5):** match `ci_cd.yml`'s `xcode-select` line to upstream's pinned `Xcode_26.0.1`. `scripts/extract_l10n_strings.sh` regenerates l10n from ALL `*.swift` files via `genstrings`, and `ensure_generated_files_are_up_to_date.sh` (`ci_cd.yml:49`) **hard-fails on any byte-diff** (including BOM/encoding differences a different `genstrings` emits). If the fork runner's Xcode drifts from upstream's, that gate reds **every** PR on a genstrings diff the maintainer didn't cause and can't easily diagnose. Treat the Xcode pin as a monitored invariant; re-pin it on every upstream Xcode bump (§6.2 step 8).
- [ ] **Anti-relock backstop (§4.4):** (Guard A) append BOTH mock-injected tests to the EXISTING `src/pro/license/LicenseManagerTests.swift` (already in the `unit-tests` target — **no new file, no pbxproj edit**): `testDepaywallProNeverLocked` (load-bearing `state == .pro` assert) AND `testDepaywallStillProAfterTrialExpiry` (inject an expired `trialStartDate` so `isProLocked`/`isProAvailable` become discriminating — a day-0 trial makes them non-discriminating). **Use the existing `MockClock` fixture (not `SystemClock()`)** so the trial math is deterministic. Do NOT reference `LicenseManager.shared`, `Endpoints.*`, or `ProFeature.*`. (Guard B) add the `grep` step to `ci_cd.yml` **as the FIRST push-job step — before `run_tests.sh` (line 53), so it aborts before `update_appcast.sh` (57, Sparkle sign), `semantic-release` (59, tag push), and `action-gh-release` (62)**; placing it only before `action-gh-release` is too late, since the tag is already pushed by line 59 (§4.4). Grep for the **`depaywall` marker** + the **`if false {` wrap**, NOT a bare `return .pro` (which matches the unpatched `LicenseManager.swift:187`). Optionally keep a second copy before line 62 as belt-and-suspenders. (Guard C) add the **conflict-marker grep** at the same first-step position and to `guard.yml` (a `--no-verify` conflict commit must never reach a published tag — §4.4). **Also add a SEPARATE fork-owned `.github/workflows/guard.yml` (`on: pull_request`)** running Guards A+B+C independently of `ci_cd.yml`, so a careless `ci_cd.yml` conflict resolution can't silently strip the PR gate (§4.4). For the full `ci_cd.yml` PR signal, the `pull_request:` trigger must be added (§4.2); the in-`ci_cd.yml` release-time greps mean a relock/conflicted-tree cannot ship even if a PR gate is missing. Confirm `run_tests.sh` runs Guard A.
- [ ] **Per-release feature-unlock acceptance check (§4.4 — the consumers aren't unit-testable):** establish the short manual/UI checklist confirming each headline Pro feature is FREE in the BUILT app (9th+ shortcut, type-to-search, a Pro appearance style, one more gated feature). This is mandatory on every release (§6.2 step 5), since Guard A structurally cannot reach `ProFeature`/`PreferenceDefinition`/`ShortcutAction`/`TilesView`.
- [ ] **Sync workflow:** add `.github/workflows/upstream_sync.yml` (daily cron + `workflow_dispatch`, with `permissions: { contents: write, pull-requests: write }`, **state-file-driven tag selection** — sync the oldest upstream tag strictly newer than `.fork-sync-state`, *not* "newest tag minus `--is-ancestor`" (§4.2) — a real `chore(sync):` merge commit, and `gh pr create`).
- [ ] **Sync labels (§4.2 — Guard 2 and the §0.1 trip-wire depend on them existing):** `gh label create sync`, `gh label create conflict`, `gh label create chokepoint-refresh`. Make Guard 2 / the trip-wire **fail closed** — bail + alert if a label query errors or the label is absent; never treat an empty `gh pr list --label …` result as "no open sync" (an empty list is what a *missing* label returns).
- [ ] **`.fork-sync-state` (§4.2 — the never-drop-commits invariant):** commit a state file recording the last-MERGED upstream tag, advanced ONLY on merge to `master` (a tiny `ci_cd.yml` push-job step). The cron syncs the oldest upstream tag strictly newer than it, so a sync PR that is **closed-without-merge or abandoned cannot cause its tag to be silently skipped** (the state file simply didn't advance). A deferred sync PR is therefore left OPEN, never closed (§6.2).
- [ ] **Cron durability (§4.2 — the in-repo `schedule:` auto-disables after 60 days of repo inactivity):** **primary = an external scheduler hitting `repository_dispatch` carrying the `SYNC_BOT_TOKEN`** (immune to the 60-day auto-disable AND composes with the workflow-re-trigger token fix below); keep the in-repo `schedule:` + a heartbeat re-arm as belt-and-suspenders. **Add a two-trigger liveness alert** (open an issue / notify if (i) no `sync/*` PR in ~45 days OR (ii) the oldest OPEN `sync/*` PR is older than ~14 days — §4.2). Do not ship the bare in-repo cron as set-and-forget.
- [ ] **Sync-bot credential (§4.2 — BLOCKING):** provision `SYNC_BOT_TOKEN` — a GitHub App installation token (preferred; least-privilege, short-lived) or a fork-owned PAT — and use it as `actions/checkout`'s `token:` and as `GH_TOKEN` for `gh pr create` in `upstream_sync.yml`. **Do NOT author the sync push/PR with the default `GITHUB_TOKEN`** or GitHub's recursion rule means `guard.yml`/`ci_cd.yml` PR checks never fire and the pre-merge gate silently never runs. Add this token to the §4.6 credential-lifecycle bucket (it expires; can push to `master` if leaked). **Acceptance test:** open a sync PR through the bot and confirm the guard/CI PR checks actually appear.

### 6.2 Per-sync runbook (the repeating loop)

1. Cron (or `workflow_dispatch`) fetches upstream tags, attempts `git merge` of the **oldest upstream tag
   strictly newer than `.fork-sync-state`** (§4.2 — not "the newest tag") onto a `sync/<tag>` branch, and
   opens a PR labeled `sync` (clean) or `sync,conflict`.
2. **If `sync`:** verify the PR's CI is green — the `guard.yml` PR check (Guards A + B + C) is the primary
   signal; the `ci_cd.yml` `pull_request:` path (§4.2) gives the full CI. **First confirm the checks
   ACTUALLY RAN** (a bot PR with no checks = the `SYNC_BOT_TOKEN` is mis-set to the default `GITHUB_TOKEN`
   and the gate is disarmed — §4.2). **All three guards require the `pull_request:` trigger / guard workflow +
   the workflow-re-triggering token added at bootstrap; the release-time Guard B/C greps in `ci_cd.yml` are
   the fail-closed backstop if a PR gate is missing.** Resolve any identity/CI conflicts with "keep ours" —
   the recurring set: `local.xcconfig`, `Info.plist`, `.github/workflows/ci_cd.yml`, **`.github/FUNDING.yml`**,
   `scripts/update_appcast.sh`/`update_website.sh`, `release.config.js`, `package.json` (§5 license field); approve + merge. The pipeline
   auto-builds → signs → notarizes → publishes the appcast → cuts the GitHub release. (~5–15 min, plus the
   step-5 acceptance check.)
3. **If a previous sync is still open/blocked (stalled — §4.2):** the cron will NOT have opened a new PR
   (resolve-in-order, default). **Resolve the open `sync/*` PR first** — do NOT fast-forward to the newest
   upstream tag and abandon the stranded one (that drops the intervening commits). **And do NOT *close* a
   deferred sync PR to silence it:** a closed-unmerged PR escapes both cron guards, but because
   `.fork-sync-state` only advances on *merge*, leaving the PR open is what keeps its tag "next" — a close
   without a state-file reset is the one move that silently skips a tag (§4.2). Once it merges, the next
   cron run syncs the next tag; if you must catch up faster, merge the *oldest* unmerged tag next, not the
   newest. The liveness alert's stale-open trigger (§4.2) is what surfaces this; a paused backlog compounds
   the next merge's conflict effort (§4.5).
4. **If `sync,conflict`:** inspect `git diff --name-only --diff-filter=U`.
   - *Identity/CI files only* → `git checkout --ours`, re-confirm fork URLs/keys, commit, let CI verify.
   - *A chokepoint file* (`LicenseManager`/`ProFeature`/`PreferenceDefinition`/`ProTransitionManager`) →
     re-apply the de-paywall intent on top of upstream's new code (the `if false { … }` wrap); run the
     anti-relock test locally until green; commit; push; let CI re-verify. (~30–90 min.) **Add the
     `chokepoint-refresh` label to this PR** (`gh pr edit <n> --add-label chokepoint-refresh`) so the §0.1
     trip-wire A tally is the query `gh pr list --label chokepoint-refresh --search 'merged:>=<12mo>'` and
     never depends on someone remembering. (≥3 such merged PRs in 12 months → reconsider strategy.)
   - *A swept brand-string file* (`src/*.swift` literal or `Localizable.strings`) → re-apply the fork name,
     then **re-run `scripts/l10n/extract_l10n_strings.sh` and commit the regenerated `*.strings`** or the
     `ensure_generated_files_are_up_to_date.sh` gate (`ci_cd.yml:49`) fails the PR.
5. **Gate-consumer review + feature-unlock acceptance check (MANDATORY every release — the compile + Guard A
   provably can't cover the consumers, §2/§4.4):** (i) if the sync touched `ProFeature` /
   `PreferenceDefinition` / `ShortcutAction` / `TilesView` (the gate consumers, which upstream churns),
   **confirm the gates still consult `state`** and that no NEW `LicenseState` case, per-feature entitlement
   check, or moved state-producer re-arms the paywall; AND (ii) **run the §4.4 positive feature-unlock
   acceptance checklist on the built app** (9th shortcut, type-to-search, a Pro appearance style, one more
   gated feature) so a silent consumer-level relock is caught end-to-end. This is no longer conditional —
   the unit-test target structurally excludes these consumers, so this manual layer is the only one that
   exercises them.
6. **Periodic commercial-surface re-audit:** if the sync touched `src/pro/`, `src/api/`, `src/vendors/`, or
   `Info.plist` network keys, **re-audit the network/gate/telemetry surface** — the 3-edit + 2-test + 1-grep
   backstop targets v11.0.0's shape and would NOT detect a new gate/endpoint/telemetry path upstream
   introduces (feeds the §0.1 trip-wire C).
7. **Functional / compatibility-breaking sync (§0.1 trip-wire D — "keep the app working", not just "keep Pro
   free"):** the Guards + the step-5 feature-unlock check prove Pro is FREE, **not** that the app still
   launches on the supported macOS range. If this sync touches `MACOSX_DEPLOYMENT_TARGET`
   (`config/base.xcconfig:5`) / `LSMinimumSystemVersion`, any `Info.plist` permission/entitlement key,
   `PreferencesMigrations.swift`, or bumps a major upstream version, then before merging: (i) **smoke/launch
   test the built app on the supported macOS floor** (confirm it launches, the switcher works, permissions
   prompt correctly); (ii) **review the README/system-requirements** and update them if the floor moved;
   (iii) for a **major version bump**, an explicit **owner go/no-go** (confirm the `v100.0.0` offset still
   orders correctly and that no user-facing behavior change needs a release-note callout). A
   `git diff --name-only <last-synced-tag>..<new-tag> -- config/base.xcconfig Info.plist src/preferences/PreferencesMigrations.swift` surfaces this branch deterministically.
8. **NOTICE.md (GPL §5(a)) + attribution-preserve check:** (i) if this sync changed the fork's
   *modification surface* (a new edit, a `FeedbackWindow` rewrite, a chokepoint-refresh edit), update
   `NOTICE.md`'s change list + date (§5); (ii) **confirm the FOUR-surface attribution-preserve set survived
   the merge** — (a) `LICENCE.md`, (b) `Info.plist:21` `NSHumanReadableCopyright` GPL string, (c) the
   README/About fork credit, (d) `docs/contributors.md` + `docs/acknowledgments.md` are still present and
   intact, and the §3.2 brand sweep did not over-sweep the "fork of AltTab / © Louis Pontoise" attribution or
   contributor names (§3.5). **(Do NOT check for "source copyright headers" — there are none; that earlier
   check verified nothing.)** A merge that adds upstream contributors should keep them.
9. **Guard durability + Xcode-pin checks (cheap, periodic — not every sync):** confirm the `pull_request:`
   trigger still exists in `ci_cd.yml` and `guard.yml` is intact (an upstream `ci_cd.yml` conflict resolved
   "keep theirs" can strip the trigger — §4.4); watch the **60-day cron auto-disable** — if no `sync/*` PR
   has appeared in ~45 days, the cron may be disabled, re-arm it (§4.2); and **whenever a sync bumps
   upstream's pinned Xcode (`ci_cd.yml` `xcode-select` line, currently `Xcode_26.0.1`), re-pin the fork
   runner to match** (§4.5 / §6.1 invariant) before the next l10n regeneration, or `ensure_generated_files`
   reds every PR on a genstrings byte-diff the maintainer didn't cause.
10. Merge to `master` triggers `ci_cd.yml` → release. **After the release publishes, run the §3.6.1
    fork-to-fork auto-update check** (install the prior release, confirm it auto-updates to this one cleanly —
    see §6.1 bootstrap and §3.6.1). Done until the next upstream tag.
11. **Rollback runbook — a shipped release regressed (relock slipped a guard, a feature broke, a dead source
    link, a bad enclosure URL):** (i) **stop the bleed** — delete or mark the bad GitHub Release as a
    pre-release/draft so the auto-tarball and download stop being offered; (ii) **un-offer it via Sparkle** —
    remove the bad `<item>` from the published appcast feed (the out-of-tree gh-pages copy, §3.3) so clients
    that have not yet pulled it stop seeing it; clients that *already* auto-updated need a **new higher
    version** to recover, so (iii) **roll forward, don't roll back** — cut a fixed `vN+1` (Sparkle only moves
    forward via monotonic `sparkle:version`; you cannot push a *lower* version to already-updated clients,
    §3.6.1). (iv) If the regression was a relock that the guards missed, treat it as a guard gap: add a
    behavioral assertion before the next release. Note Sparkle has **no remote kill-switch** — already-updated
    users stay on the bad build until `vN+1` reaches them on their next scheduled check
    (`SUScheduledCheckInterval=604800`, i.e. up to a week), so a fast `vN+1` is the only real remediation.

---

## Appendix — cross-references

- **`docs/AUDIT.md`** — Master Paywall Audit. §3 "The paywall, anatomized" (the chokepoints); §4 "The
  complete set of Pro-gated features"; §5 "The complete removal surface" (the *deletion* surface — note the
  audit recommends full excision; this plan deliberately diverges to leave-`src/pro`-inert for the
  tracked-fork goal, reusing the audit's churn/isolation data but not its conclusion); §6 "Notable findings,
  risks, open questions".
- **`docs/PLAN-republish-free.md`** — the one-shot full-excision plan that this document supersedes for the
  tracked-fork goal. §A Licensing & Ethics (the GPL-3 source for §5 here); §B Removal strategies; §C-D
  excision execution + re-identity; §E risks/testing.
- **`docs/GRAPHS.md`** — dependency/call graphs of the paywall subsystem.
- **`docs/audit/01-core-architecture.md`** — App lifecycle, the `App.swift` spine and its license fan-out.
- **`docs/audit/03-preferences-and-gating.md`** — `PreferenceDefinition.read()` gate + degradable prefs.
- **`docs/audit/04-license-subsystem.md`** — `LicenseManager`, `computeState()`, `RemoteLicenseClient`,
  `LicenseCookie`, `MachineFingerprint` (the primary chokepoint + network side-effects).
- **`docs/audit/05-trial-nag-scheduling.md`** — `ProTransitionManager` (nag scheduler; inert via the flip).
- **`docs/audit/06-profeature-and-copy.md`** — `ProFeature.attemptUse()` (hard-gated features).
- **`docs/audit/07-pro-ui-and-menubar.md`** — upsell UI (Menubar / SettingsWindow / Upgrade tab).
- **`docs/audit/08-build-release-distribution.md`** — `ci_cd.yml`, scripts, Sparkle/appcast, signing.
- **`docs/audit/09-telemetry-and-upstream.md`** — AppCenter telemetry, endpoints, upstream-tracking notes.
