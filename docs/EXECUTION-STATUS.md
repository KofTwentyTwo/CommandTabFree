# Execution status — depaywall-free integration

**Branch:** `depaywall-free`
**Upstream sync point:** lwouis/alt-tab-macos `v11.3.0` (recorded in `.fork-sync-state`)
**Date:** 2026-06-10
**Authoritative plan:** `docs/PLAN-maintained-fork.md`. Audit: `docs/AUDIT.md`.

This document records what the automated agents DID, the verified build/test/gate
results, and the **single authoritative owner publish checklist** (only the human
owner can do the items at the bottom). Read the checklist top to bottom before publishing —
several items are BLOCKING (the fork will not notarize, auto-update, or gate releases
until they are done).

---

## 1. What was DONE

### 1.1 De-paywall patch (committed BEFORE this integration pass)

Landed in commit `f3d76859` (`depaywall: neutralize license gate, cookie, telemetry, and
activate handler (src/pro left intact)`). `src/pro/` is left physically present but inert.
Four neutralizations, each carrying a `depaywall` marker comment:

| # | File:line | Edit | Effect |
|---|-----------|------|--------|
| 1 | `src/pro/license/LicenseManager.swift:177` | `guard false else { return .pro }` (body below wrapped in `if false { … }`) | The single state producer `computeState()` always returns `.pro`. Opens every Pro gate in the tree at once; no per-merge UI/pbxproj edits. |
| 2 | `src/App.swift:474` | `guard false else { return }` at top of `handleCustomUrl` | The scheme-gated `<bundleid>://activate?license_key=…` handler early-returns, so it can NEVER reach `LicenseManager.shared.activate → RemoteLicenseClient` POST that exfiltrates the machine hardware UUID (`MachineFingerprint`). This is the live-exfiltration surface, killed independent of where `API_DOMAIN` points. |
| 3 | `src/pro/license/LicenseCookie.swift:6` | body wrapped in `if false { … }` | `syncLicenseCookie(state:)` never writes a `license` cookie to the fork/upstream domain. Call site in `App.swift` (hot file) untouched. |
| 4 | `src/vendors/AppCenterCrashes.swift:10` | `init()` body wrapped in `if false { … }` | `AppCenter.start(...)` never runs; no crash telemetry network calls. `App.appCenterDelegate = AppCenterCrash()` still constructs the object, which now does nothing. |

All four use `if false { … }` / `guard false` rather than a bare early `return`, because
`config/base.xcconfig:7` sets `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and "code after return"
is a build error.

### 1.2 Anti-relock guard tests (committed BEFORE this integration pass)

Landed in commit `4506c539`. Two methods appended to the EXISTING
`src/pro/license/LicenseManagerTests.swift` (already in the `unit-tests` Sources phase — zero
pbxproj edits), per PLAN §4.4 Guard A:

- `testDepaywallProNeverLocked` — fresh mock-injected `LicenseManager`; asserts `state == .pro`.
- `testDepaywallStillProAfterTrialExpiry` — injects a long-past `trialStartDate` so an
  *unpatched* `computeState()` would return `.trialExpired`; asserts `.pro` + `!isProLocked`
  + `isProAvailable`. This is the discriminating test — it goes RED on a re-armed paywall.

**Both pass** (see §2). They use the existing `MockClock`/`MockKeychain`/`MockLicenseAPI`
fixtures and never reference `LicenseManager.shared`, `Endpoints.*`, or `ProFeature.*` (the four
traps documented in PLAN §4.4).

### 1.3 Scaffolding (committed in THIS pass — `3dde8a91`)

`git commit -m "chore: identity overlay + sync/guard/release CI scaffolding (placeholders flagged for owner)"`
— 15 files, +681/-3891. The agents wrote these but had not committed; this pass committed them.

**Identity overlay (fork-owned, last-include-wins; zero edits to `base.xcconfig`/`project.pbxproj`):**
- `config/local.xcconfig` (NEW) — `PRODUCT_NAME=AltTabFree`, `PRODUCT_BUNDLE_IDENTIFIER=io.github.koftwentytwo.alt-tab-free`, `DOMAIN=fork.invalid`, `API_DOMAIN=fork.invalid/api`, `APPCENTER_SECRET=` (empty), `CODE_SIGN_IDENTITY` left commented (TODO). All values are PLACEHOLDERS flagged for the owner.
- `Info.plist` — `Domain`/`ApiDomain` now wired to `$(DOMAIN)`/`$(API_DOMAIN)`; `SUPublicEDKey` = `REPLACE_WITH_FORK_SUPUBLIC_EDKEY` placeholder.
- `src/api/Endpoints.swift` — reads `Domain`/`ApiDomain` from the bundle (build-time, fork-owned), so every license/feedback/appcast URL derives from the fork's own hosts, never upstream `alt-tab.app`.
- `package.json` — `license` set to `GPL-3.0`, author cleared.

**GPL attribution docs:** `README.md` (modified), `NOTICE.md` (NEW) — GPL §5(a) statement of
changes; currently references placeholder identity (`AltTabFree`, the placeholder bundle id, the
placeholder GitHub URL) and upstream `v11.3.0` / `2026-06-10`.

**Upstream-sync + guard CI:** `.github/workflows/upstream_sync.yml` (NEW), `.github/workflows/guard.yml`
(NEW), `.fork-sync-state` (NEW, `v11.3.0`). `guard.yml` runs Guard A (anti-relock test on `macos-15`,
Xcode pinned to `26.0.1`), Guard B (depaywall marker grep), Guard C (conflict-marker grep) on
`pull_request`.

**Release pipeline:** `.github/workflows/ci_cd.yml` (re-architected: `pull_request` trigger added,
release-side steps gated, Guard B/C greps inserted FIRST in the push job),
`scripts/update_appcast.sh`, `scripts/replace_environment_variables_in_app.sh`, `release.config.js`,
`appcast.xml` (trimmed), `.github/FUNDING.yml`, `.gitignore`.

All three workflow YAMLs validate (`yaml.safe_load` OK).

---

## 2. Verified results

### 2.1 Build — full tree compiles (PASS)

`bash ai/build.sh` (Debug) FAILS in this environment with exactly one error:

```
error: No certificate matching 'Local Self-Signed' found … (target 'alt-tab-macos')
```

This is `config/debug.xcconfig:5` (`CODE_SIGN_IDENTITY = Local Self-Signed`) requiring a
self-signed cert that is **not present in this CI/dev keychain** (`security find-identity -v
-p codesigning` → `0 valid identities found`). It is a pre-existing ENVIRONMENT prerequisite,
unrelated to the depaywall patch or scaffolding (the scaffolding touches no Debug signing config).

Re-running with signing disabled isolates compilation:

```
xcodebuild -project alt-tab-macos.xcodeproj -scheme Debug -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
→ ** BUILD SUCCEEDED **  (exit 0; 0 errors; 218 Swift compile actions)
```

**The full source tree compiles clean after all scaffolding.** No scaffolding file needed a fix,
so the commit was not amended. The default `ai/build.sh` will succeed once the owner provisions a
signing identity (see checklist).

### 2.2 Tests — GREEN (anti-relock guards PASS; 16 legacy paywall tests skipped — §2.3)

`xcodebuild test -scheme Test -configuration Debug` (signing disabled by `config/test-base.xcconfig`):

- **477 tests pass.**
- The two anti-relock guards **PASS**:
  - `testDepaywallProNeverLocked` — passed (0.001s)
  - `testDepaywallStillProAfterTrialExpiry` — passed (0.001s)
- **16 legacy paywall-behavior tests in `LicenseManagerTests` were RED** (they assert the now-dead
  trial/expiry/lock/activate behavior). **RESOLVED in commit `1a914c88`** — each is now `XCTSkip`-marked
  with an `alt-tab-free [depaywall]` reason. Zero failures outside `LicenseManagerTests`; zero attributable
  to scaffolding.

**Overall Test scheme result: GREEN** (`** TEST SUCCEEDED **`) — 493 executed, **16 skipped, 0 failures**;
both `testDepaywall*` anti-relock guards RUN and PASS.

### 2.3 RESOLVED (commit `1a914c88`) — 16 legacy paywall tests contradicted the patch

> **RESOLVED 2026-06-10:** all 16 are now `XCTSkip`-marked (`alt-tab-free [depaywall]`), so the `Test`
> scheme is GREEN and the two `testDepaywall*` guards remain the active anti-relock signal. The analysis
> below is retained for the record.

The depaywall patch forces `computeState()` to always return `.pro`. Sixteen pre-existing tests in
`src/pro/license/LicenseManagerTests.swift` still assert the now-dead trial/expiry/lock behavior and
therefore fail. They were introduced-as-failing by the depaywall patch commit (`f3d76859`), NOT by
this integration pass's scaffolding. The failing tests:

```
testFirstLaunchStartsTrial                         testTrialMidway
testSecondLaunchPreservesTrialStart                testTrialLastDay
testTrialExpiresOnDay14                            testTrialExpiresWellPastDuration
testPreviouslyInvalidatedLicenseIsTrialExpired     testLicenseWithoutValidationResultIsTrialExpired
testIsProLockedTrueAfterTrialExpiry                testIsProLockedTrueWhenKeychainInvalidated
testOnStateChangedFiresOnInitialize                testOnBeforeProUnlockFiresBeforeStateFlipsToPro
testActivateFailurePreservesState                  testActivateSeatLimitExceededSurfacesInstances
testActivateFailsAndRollsBackIfKeychainWriteFails  testActivateRollsBackPartialKeychainWritesOnLaterFailure
```

Root cause (two clusters, both downstream of the forced `.pro`):
1. **initialize-path tests** assert `.trial(...)` / `.trialExpired` after `initialize()`, which now
   always yields `.pro`.
2. **activate-failure-path tests** assert state stays `.trial` after a rejected/rolled-back
   `activate`, but the rollback re-reads `state = computeState()` → `.pro`.

**Why this is BLOCKING and was NOT silently "fixed" here:** PLAN §4.4 makes `run_tests.sh` (the whole
`Test` scheme) the Guard A release gate, wired into both `ci_cd.yml` (push job) and `guard.yml`
(PR). A permanently-RED Test scheme means **Guard A can never go green → no release can ever ship,
and the genuine anti-relock signal is drowned out by 16 expected failures.** Neutralizing 16 tests is
a substantive source change to a hot test file (re-conflicts on every upstream sync that touches it)
and is outside the "fix the offending *scaffolding* file" / "do NOT deviate from strategy" mandate of
this integration pass, so it is flagged for an explicit owner/patch decision rather than done
unilaterally. **Recommended disposition** (consistent with the depaywall strategy — neutralize, don't
delete): wrap each failing assertion's body in `if false { … }` with an `alt-tab-free [depaywall]`
marker and replace it with an `XCTAssertEqual(manager.state, .pro)` assertion, exactly mirroring how
the production code was neutralized. This keeps the merge surface minimal and the test file's
membership/pbxproj untouched. (Alternatively, delete the 16 methods — simpler diff, but loses the
documentation of the dead behavior.)

### 2.4 Gate proofs — the paywall is dead (verified by grep + reachability)

| Plan requirement | Proof |
|---|---|
| (a) `computeState()` returns `.pro` with `depaywall` marker | `LicenseManager.swift:177` — `guard false else { return .pro }  // depaywall: …` |
| (b) no reachable POST to `alt-tab.app/api` | Both POST sites (`RemoteLicenseClient.swift:105`, `FeedbackWindow.swift:446`) target `Endpoints.apiDomain`, which is read from Info.plist `ApiDomain` (fork-owned, build-time — currently `fork.invalid/api`), NEVER upstream `alt-tab.app`. The only two literal `alt-tab.app` strings in the tree are doc comments, not live code. The license-activate POST's auto-reachable entry point (`App.swift:474` `handleCustomUrl`) early-returns via `guard false`. Its only other caller (`UpgradeTab.activateLicense`) requires a human to paste a key into the upsell UI and would hit the fork's own backend, not upstream. |
| (c) `syncLicenseCookie` + `AppCenterCrash.init` wrapped in `if false` | `LicenseCookie.swift:6` — `if false {  // depaywall: …`; `AppCenterCrashes.swift:10` — `if false {  // depaywall: …` |

---

## 3. Owner publish checklist — only you can do these

These require human judgment, secrets, or external accounts. Items marked **BLOCKING** must be done
or the fork will not notarize, auto-update, gate releases, or stop phoning home. Grouped, with the
per-component owner actions gathered from the scaffolding agents merged in.

### 3.0 ✅ DONE (commit `1a914c88`) — Test scheme is GREEN

- [x] **Resolved the 16 RED legacy paywall tests** in `src/pro/license/LicenseManagerTests.swift` —
      each is now `XCTSkip`-marked (`if true { throw XCTSkip("alt-tab-free [depaywall]: …") }`; the bare
      `throw` form is rejected by `SWIFT_TREAT_WARNINGS_AS_ERRORS`). The `Test` scheme is now GREEN
      (493 executed, 16 skipped, 0 failures); the two `testDepaywall*` anti-relock guards still RUN and
      PASS. No owner action remains here.

### 3.1 Brand / identity / trademark (BLOCKING for a clean publish)

- [ ] **Pick a trademark-safe fork name** (avoid "AltTab"/"alt-tab" confusion) and run the PLAN §3.2
      brand sweep across the tree, then **regenerate l10n** (`genstrings` per the §3.2 procedure) for
      every file the sweep moved/renamed.
- [ ] **Set the REAL `PRODUCT_NAME`** in `config/local.xcconfig` if `AltTabFree` is not final, AND set
      `ci_cd.yml` `APP_NAME` equal to it (currently placeholder `AltTabFree`).
- [ ] **Set the REAL fork bundle id in `config/local.xcconfig` and FREEZE it once** (placeholder:
      `io.github.koftwentytwo.alt-tab-free`). Changing it later orphans every user's keychain +
      UserDefaults state (LicenseManager derives the suite names from `App.bundleIdentifier`). Decide
      PLAN §3.1: (a) fresh id, or (b) reuse-existing-id + migration. **Freeze the bundle id.**
- [ ] **Replace placeholder identity in `README.md` AND `NOTICE.md`** — final product name, final
      bundle id, and the fork GitHub URL (placeholder `https://github.com/koftwentytwo/alt-tab-free`).
- [ ] **At release time, set `NOTICE.md`'s upstream version + modification date** to the actual sync
      point (currently `v11.3.0` / `2026-06-10`). Keep `NOTICE.md` current per PLAN §6.2 on every future
      sync that changes the fork's modification surface. **Note:** `NOTICE.md` lists
      "App.handleCustomUrl (activate disabled)" as a change — the §2 Edit-2 neutralization HAS landed
      (`App.swift:474`), so that line is accurate; if you ever opt NOT to neutralize it, remove that line.
- [ ] **Replace the app icon** (do not ship lwouis's mark).
- [ ] **Add `config/local.xcconfig` and `package.json` to the PLAN §6.2 "keep ours" recurring-conflict
      set** so a future merge can't re-introduce upstream identity or the MIT license string.

### 3.2 Hosts / domain (BLOCKING for update + feedback)

- [ ] **Set `DOMAIN` and `API_DOMAIN` in `config/local.xcconfig`** to fork-owned, routable hosts
      (currently `fork.invalid` / `fork.invalid/api` placeholders). `DOMAIN` must serve
      `https://<DOMAIN>/appcast.xml` and `/support`; `API_DOMAIN` drives the feedback POST. Decide the
      §3.4 feedback strategy. The `activate` fingerprint POST is closed independently at the handler
      (§2 Edit 2), so `API_DOMAIN` may be routable for feedback WITHOUT re-arming exfiltration.
- [ ] **Stand up the appcast/feed host:** point `DOMAIN` at the gh-pages site that serves
      `/appcast.xml` (or CNAME it). `Endpoints.appcastUrl = https://$DOMAIN/appcast.xml`.
- [ ] **Remove `appcast.xml` from the tree** (`git rm appcast.xml`) and add `/appcast.xml` to
      `.gitignore` — the feed is served out-of-tree from gh-pages. (Coordinate: `.gitignore` is owned by
      the identity overlay.)

### 3.3 Code signing + Sparkle keys (BLOCKING for notarization + auto-update)

- [ ] **Obtain an Apple Developer ID Application certificate** for the fork and set
      `CODE_SIGN_IDENTITY` in `config/local.xcconfig` (currently a commented TODO). Required for
      notarization/Gatekeeper. Also re-sign the vendored Sparkle helpers under the SAME Developer ID
      (PLAN §3.3 / §4.6) or notarization rejects. (This is also what makes the default `ai/build.sh`
      stop failing on the missing `Local Self-Signed` cert.)
- [ ] **Generate a FRESH Sparkle EdDSA keypair:** paste the PUBLIC key into `Info.plist:66`
      (replace `REPLACE_WITH_FORK_SUPUBLIC_EDKEY`); store the PRIVATE key as the CI secret
      `SPARKLE_ED_PRIVATE_KEY`. The placeholder is NOT lwouis's key and will verify nothing.

### 3.4 GitHub Actions secrets + Environment (BLOCKING for release)

- [ ] **Create the GitHub Environment named `production`** (matches `ci_cd.yml` `environment:`) with NO
      required-reviewer protection that would stall releases.
- [ ] **Set these secrets (repo + the `production` Environment):** `APPLE_P12_CERTIFICATE` (fork's
      Developer ID), `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`, `SPARKLE_ED_PRIVATE_KEY` (fork's NEW
      EdDSA private key), and `SYNC_BOT_TOKEN`.
- [ ] **Provision `SYNC_BOT_TOKEN` (BLOCKING, PLAN §4.2):** a GitHub App installation token (preferred)
      or a fork-owned PAT with contents + pull-requests write. **The default `GITHUB_TOKEN` will NOT
      work** — a PR it authors fires no `pull_request` checks, so `guard.yml` / `ci_cd.yml` never run on
      the sync PR. Add it to the §4.6 credential-lifecycle bucket (it expires; can push to master if
      leaked).

### 3.5 Upstream-sync wiring (BLOCKING for the perpetual-republish promise)

- [ ] **Create the three PR labels at bootstrap (§6.1):** `gh label create sync`,
      `gh label create conflict`, `gh label create chokepoint-refresh`. `upstream_sync.yml` fails closed
      if any is missing.
- [ ] **Set up the EXTERNAL scheduler (§4.2 recommended primary)** hitting `repository_dispatch` (event
      type `upstream-sync`) carrying `SYNC_BOT_TOKEN` — immune to GitHub's 60-day auto-disable of in-repo
      cron. The in-repo cron is belt-and-suspenders only.
- [ ] **`.fork-sync-state` writer (contract owned by `ci_cd.yml`):** add the push-job step that advances
      `.fork-sync-state` to the merged tag on merge to master — without it the cron re-opens the same tag
      forever. (This file is the contract; the writer lives in `ci_cd.yml`.)
- [ ] **Add the two-trigger liveness alert (§4.2):** notify if no `sync/*` PR in ~45 days OR oldest open
      `sync/*` PR > ~14 days (the workflow emits a `stalled` output flag for this).
- [ ] **Re-pin `guard.yml`'s Xcode line** (currently `Xcode_26.0.1`) whenever an upstream sync bumps
      `ci_cd.yml`'s pinned Xcode (§4.5 / §6.2).

### 3.6 Commit/changelog plumbing (needed for CI to pass on sync PRs)

- [ ] **Add the `commitlint.config.js` `ignores` predicate (§4.3)** to drop the synthetic
      `chore(sync): merge upstream` commit and upstream's non-conforming messages — `ci_cd.yml`'s
      commitlint steps depend on it.
- [ ] **Inject the GPL §6(d) corresponding-source pointer into the GitHub Release body**
      (`scripts/extract_latest_changelog.sh`). `update_appcast.sh` already covers the Sparkle channel;
      the GitHub Release channel still needs it (PLAN §5(1)).
- [ ] **Consider a source tarball release asset and/or a takedown-contingency mirror** so GPL §6 source
      survives a repo takedown (PLAN §5(1) conveyance durability).

### 3.7 Bootstrap acceptance tests (do before declaring "published")

- [ ] **§4.2 first-sync acceptance:** open a sync PR THROUGH the bot and confirm `guard.yml` +
      `ci_cd.yml` `pull_request` checks actually appear and run. A check-less bot PR means
      `SYNC_BOT_TOKEN` is mis-set.
- [ ] **§4.4 relock acceptance:** push a branch reverting the `computeState() → .pro` flip and confirm
      `guard.yml` goes RED (Guard A test on `macos-15`, and/or the Guard B marker grep) before merge.
- [ ] **§6.1 fork-to-fork auto-update acceptance:** confirm a user on fork build N actually receives
      build N+1 via Sparkle — enclosure URL resolves to the fork's release, the EdDSA signature verifies
      against the embedded fork public key, `SUVersion` ordering is monotonic, and Gatekeeper is the only
      first-run friction (PLAN §3.6.1).

---

## 4. Commit log on `depaywall-free`

```
3dde8a91  chore: identity overlay + sync/guard/release CI scaffolding (placeholders flagged for owner)   [this pass]
4506c539  test: anti-relock guards (pro never locked, incl. post-trial-expiry)
f3d76859  depaywall: neutralize license gate, cookie, telemetry, and activate handler (src/pro left intact)
e243fb4b  docs: audit + republish/maintained-fork plans
9fadf36b  chore(release): 11.3.0 [skip ci]   (upstream sync point)
```
