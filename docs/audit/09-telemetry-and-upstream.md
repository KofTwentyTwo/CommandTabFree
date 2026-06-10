# 09 — Telemetry / Analytics & Relationship to Upstream

Audit scope: every network/telemetry surface in the app, the fork's divergence from
upstream AltTab (`lwouis/alt-tab-macos`), and every branding/identity string that ties
this binary to the paywalled "AltTab Pro" product. Read-only analysis; no source was
modified. All paths are relative to the repo root unless noted.

---

## 1. Executive summary

- There is **no third-party analytics or product-tracking SDK** in this app. A broad
  sweep for Mixpanel / Amplitude / Sentry / Firebase / Crashlytics / Segment / PostHog /
  Datadog / Heap / Matomo / Plausible / Google Analytics found **nothing** in shipped
  source, `Info.plist`, or xcconfig.
- The only vendored telemetry SDK is **Microsoft AppCenter**, and only its **Crashes**
  module is used — there is no `import AppCenterAnalytics` anywhere. Crash reporting is
  **opt-in / ask-by-default** and is deliberately wired so AppCenter makes **no network
  request at all** unless the user agrees to send a specific crash report.
- The app makes network calls from exactly **four** places, all to first-party
  `alt-tab.app` infrastructure or to AppCenter:
  1. AppCenter crash uploads (opt-in).
  2. The license backend (`alt-tab.app/api/v1/license/*`) — part of the paywall.
  3. The feedback form (`alt-tab.app/api/v1/feedback`) — posts to a server that opens a
     public GitHub issue.
  4. Sparkle auto-update (`alt-tab.app/appcast.xml`), which sends a small system profile
     and a per-license-tier cookie.
- **This repo is a near-verbatim copy of upstream `lwouis/alt-tab-macos`, not a
  diverged fork.** Every one of the last 40 commits is authored by `lwouis` or
  `semantic-release-bot`; there are **no fork-specific commits**. The entire paywall was
  introduced **upstream** by lwouis in a single commit, `9147a4a8 "feat: introducing
  alt-tab pro!"` (v11.0.0, 2026-04-05). The "alt-tab-free" repo has only re-hosted the
  code under `KofTwentyTwo/alt-tab-free` — **no code-level rebrand has happened yet**:
  bundle id, app name, domain, GitHub URL, and SUPublicEDKey are all still the upstream
  `com.lwouis.alt-tab-macos` / `alt-tab.app` / `lwouis/alt-tab-macos` values.

This has a major strategic implication discussed in §6: because upstream is alive,
GPL-3.0, and is the source of both the features *and* the paywall, the cleanest path may
be to **rebase a free build on a pre-11.0.0 upstream tag** rather than surgically
extracting the paywall from this snapshot.

---

## 2. Telemetry / crash reporting (AppCenter)

### 2.1 What is vendored

- `vendor/AppCenter/` — Microsoft AppCenter SDK, version pinned in
  `vendor/AppCenter/UPSTREAM`:
  - `VERSION=appcenter-4.3.0 + PLCrashReporter-1.11.1`
  - `SOURCE=https://github.com/microsoft/appcenter-sdk-apple.git`
  - `DATE=2026-05-12`
- `vendor/AppCenter/Package.swift` declares **only two** products/targets:
  `AppCenter` and `AppCenterCrashes` (plus the `PLCrashReporter` binary target). The
  **Analytics** module is not vendored at all (`Package.swift:8-9`). So even if someone
  wanted product analytics, the SDK pieces are not present.

### 2.2 The wrapper — `src/vendors/AppCenterCrashes.swift`

This is the single integration point. Key behaviors:

- `src/vendors/AppCenterCrashes.swift:6` — `static let secret = Secrets.appCenterSecret`
  reads the AppCenter app secret from `Info.plist` (see §5).
- `src/vendors/AppCenterCrashes.swift:14` —
  `AppCenter.networkRequestsAllowed = false` is set **before** `AppCenter.start`,
  specifically (per the inline comment) so that "appcenter makes network call just from
  AppCenter.start; we only want networking when sending reports."
- `src/vendors/AppCenterCrashes.swift:18-20` — wires `Crashes.delegate = self`, a
  `userConfirmationHandler`, then `AppCenter.start(withAppSecret:services:[Crashes.self])`.
  Only the `Crashes` service is registered.
- `src/vendors/AppCenterCrashes.swift:31-54` — `confirmationHandler` defers a modal
  `NSAlert` and only allows the network channel to flush
  (`AppCenter.networkRequestsAllowed = shouldSend`,
  `Crashes.notify(with: shouldSend ? .send : .dontSend)`) if the user agrees.
- `src/vendors/AppCenterCrashes.swift:56-77` — `checkIfShouldSend()` reads
  `Preferences.crashPolicy` (`.ask` shows the dialog; `.always` auto-sends; otherwise
  don't send). The user-facing copy is "AltTab crashed last time you used it…"
  (`:61-62`) and a "Remember my choice" checkbox.
- `src/vendors/AppCenterCrashes.swift:94-96` — on a crash upload, the SDK attaches a
  **debug profile** (`DebugProfile.make()`) as `debug-profile.md`. See §2.4 for what's
  in it.
- `src/vendors/AppCenterCrashes.swift:99` & `:103` — after each send succeeds/fails,
  `AppCenter.networkRequestsAllowed` is forced back to `false`, so the channel goes
  silent again between reports.

### 2.3 Instantiation and plist hooks

- `src/App.swift:4` `import AppCenterCrashes`; `src/App.swift:33`
  `private static var appCenterDelegate: AppCenterCrash?`;
  `src/App.swift:436` `App.appCenterDelegate = AppCenterCrash()` — created at the very
  top of `applicationDidFinishLaunching`.
- `Info.plist:36-37` — `NSPrincipalClass = AppCenterApplication` (the AppCenter
  exception-catching `NSApplication` subclass).
- `Info.plist:69-70` — `AppCenterApplicationForwarderEnabled = 0`.
- `Info.plist:73-74` — `AppCenterSecret = $(APPCENTER_SECRET)` (substituted from
  xcconfig at build time).

### 2.4 What leaves the device on a crash — `DebugProfile`

`src/secondary-windows/DebugProfile.swift` builds the attachment. Notable fields
(`DebugProfile.swift:15-34`): app name+version, macOS version, **License state label**
(`LicenseManager.shared.state.debugProfileLabel`), OS architecture
(`Sysctl.run("hw.machine")`), **hardware model** (`Sysctl.run("hw.model")`), and
hardware-utilization data. This same profile is also attached to feedback submissions
(§4). It does **not** appear to include the user's name/email or the machine fingerprint,
but it does include the license tier and hardware model — worth a privacy note.

### 2.5 Recommendation for a privacy-respecting free build

Two viable options, in order of how clean they are:

1. **Remove AppCenter entirely.** Delete `vendor/AppCenter/`, `src/vendors/AppCenterCrashes.swift`,
   the `App.swift` instantiation (`:4`, `:33`, `:436`), the `Info.plist` keys
   (`NSPrincipalClass` -> revert to plain `NSApplication`; drop
   `AppCenterApplicationForwarderEnabled`, `AppCenterSecret`), and the
   `Secrets.appCenterSecret` accessor. Remove the crash-policy UI/preference if nothing
   else uses it. This is the most defensible "free + private" posture and removes a
   ~Microsoft-hosted network dependency and the `com.lwouis` AppCenter app secret. Note
   `DebugProfile.make()` is also used by the feedback path, so keep `DebugProfile.swift`
   if feedback is retained; only the crash-attachment call site goes away.
2. **Keep AppCenter but neuter the default.** The current design is already opt-in
   (`networkRequestsAllowed=false` until consent), so a minimal change is to ship with
   `crashPolicy` defaulting to ask/never and point the secret at a self-owned AppCenter
   app. This keeps crash diagnostics but still ships a Microsoft SDK; less aligned with a
   "fully free, no strings" rebrand.

The grafted **upsell** uses of usage data (see §3) are independent of AppCenter and must
be removed regardless.

---

## 3. `UsageStats` — local-only behavioral counters (NOT telemetry, but paywall fuel)

`src/util/UsageStats.swift` records how often the switcher is triggered and which
"pro" features were used. **This is local-only**: it writes to a private `UserDefaults`
suite `"\(App.bundleIdentifier).usage"` (`UsageStats.swift:2`) and **is never sent over
the network** (no URLSession reference anywhere in the file; data is pruned after 365
days at `:59-69`). So it is not a telemetry concern per se.

However, it exists **to drive the paywall**: the recorded counts feed the Day1->Day35
trial-nag prompts and the upgrade UI:

- `src/pro/ProConversionCopy.swift:12,27,28` — reads `usedProFeatureNames()`,
  `triggerCount`, `usedProFeaturesSessionCount` to compose upsell copy.
- `src/pro/ui/UsageStatHeroView.swift:64-86` — renders trigger/pro-use counts in the
  upgrade hero.
- `src/pro/scheduling/Day15FullUpgradeWindow.swift:22`,
  `Day15ProactiveWindow.swift:21` — branch on `usedProFeaturesSessionCount`.
- `src/App.swift:315` `UsageStats.recordTrigger`, `:427` `UsageStats.prune`,
  `:67` `resetSession`.
- `src/preferences/settings-window/tabs/AboutTab.swift:148-152` — also shows week/month/
  year trigger counts in the About tab (a benign stat display).

Removal note: when the `src/pro/` tree is removed, `UsageStats` callers in `src/pro/*`
disappear. The neutral callers (`App.swift` recording, `AboutTab` display) can stay or be
removed; nothing about `UsageStats` requires the paywall. It does **not** make network
calls, so it is not a privacy blocker on its own.

---

## 4. Other network surfaces (outside AppCenter)

### 4.1 License backend — `src/pro/license/RemoteLicenseClient.swift` (PAYWALL)

- POSTs to `Endpoints.licenseApiBaseUrl` = `https://alt-tab.app/api/v1/license`
  (`src/api/Endpoints.swift:11`), endpoints `activate` / `validate` / `deactivate`
  (`RemoteLicenseClient.swift:104`, network at `:109` `URLSession.shared.dataTask`,
  `:127` `.resume()`).
- The activation body sends a **machine fingerprint** and the local trial-start timestamp
  (`RemoteLicenseClient.swift:16-25`). The fingerprint is the IOKit
  `IOPlatformUUID` with a keychain fallback (`src/pro/license/MachineFingerprint.swift:9-20`).
  This is a stable per-machine identifier transmitted to the backend — a privacy-relevant
  data flow that exists **only** to support the paywall.
- Removal note: this entire client and all of `src/pro/license/` goes away in a free
  build. It is the most clearly paywall-coupled network call.

### 4.2 License-tier cookie for Sparkle — `src/pro/license/LicenseCookie.swift` (PAYWALL)

- `syncLicenseCookie(state:)` writes a `license` cookie (value `pro` / `proExpired` /
  empty) on the `alt-tab.app` domain so "Sparkle's appcast request can be tailored per
  tier" (`LicenseCookie.swift:3-21`). Called from `src/App.swift:451` on every license
  state change.
- This means the **auto-update check itself transmits the user's license tier** to the
  server via cookie. In a free build with no tiers, this should be deleted; the appcast
  becomes a single feed for everyone.

### 4.3 Feedback form — `src/secondary-windows/FeedbackWindow.swift`

- POSTs to `Endpoints.feedbackUrl` = `https://alt-tab.app/api/v1/feedback`
  (`Endpoints.swift:12`; request built `FeedbackWindow.swift:444-456`, sent `:390`/`:412`).
- Body includes the user's title/body, a `kind`, and **the `DebugProfile`**
  (`FeedbackWindow.swift:449-454`). The UI explicitly warns "Your feedback will be
  submitted as a public GitHub issue" with "A debug profile (versions, settings,
  hardware) is attached" (`:380-381`).
- This is **first-party and consent-gated**, not analytics. It is not paywall code, but
  it is tied to the `alt-tab.app` backend and the upstream GitHub repo. A free rebrand
  must repoint or remove this (the backend that turns the POST into a GitHub issue is not
  in this repo and presumably belongs to lwouis). Note: a prior upstream commit
  (`da9a46bf "feat: remove the need to add email in feedback form"`) already minimized PII
  here.

### 4.4 Sparkle auto-update — `src/vendors/SparkleDelegate.swift`

- Feed URL = `Endpoints.appcastUrl` = `https://alt-tab.app/appcast.xml`
  (`SparkleDelegate.swift:26-28`, `Endpoints.swift:7`).
- `feedParameters` sends a small system profile on each check: app version, macOS
  version, CPU arch (`Sysctl.run("hw.machine")`), and preferred language
  (`SparkleDelegate.swift:30-38`). Combined with the license cookie (§4.2), update checks
  currently carry version + OS + arch + lang + license tier.
- `Info.plist:61-66` — `SUPublicEDKey` (the upstream lwouis signing key),
  `SUEnableAutomaticChecks=true`, weekly interval (604800s).
- Removal note: a fork **cannot** ship updates against `SUPublicEDKey` /
  `alt-tab.app/appcast.xml` unless it controls that domain and private signing key. A free
  republish must either point the appcast at its own host with its own EdDSA key, or strip
  auto-update. The license-tier cookie should be removed regardless.

---

## 5. Build-time identity/secrets wiring

- `src/api/Secrets.swift:6` — `appCenterSecret` from `Info.plist` key `AppCenterSecret`.
- `src/api/Endpoints.swift` — all URLs derive from `Domain` (`alt-tab.app`) and
  `ApiDomain` (`alt-tab.app/api`) plist keys (`Endpoints.swift:4-5`), themselves from
  `config/base.xcconfig:20-21` (`DOMAIN`, `API_DOMAIN`).
- `config/base.xcconfig:3-4` — `PRODUCT_NAME = AltTab`,
  `PRODUCT_BUNDLE_IDENTIFIER = com.lwouis.alt-tab-macos`.
- `Info.plist:73-78` — `AppCenterSecret`, `Domain`, `ApiDomain` substituted from xcconfig.
- `alt_tab_macos.entitlements` — app-sandbox **off**, library validation disabled. No
  app-group / keychain-access-group is declared here (per AGENTS.md the keychain items are
  tied to the code signature / bundle id, so the bundle id is load-bearing for stored
  license keys — relevant only if you keep licensing, which a free build would not).

---

## 6. Fork vs upstream — git characterization

### 6.1 Commands run and what they showed

```
git log --oneline -40            # last 40 commits: ALL authored by lwouis / semantic-release-bot
git log --oneline -- src/pro     # only 3 commits ever touch src/pro
git log --oneline --diff-filter=A -- src/pro | tail -5   # src/pro first appears in 9147a4a8
git log -40 --format='%an' | sort | uniq -c              # 34 lwouis, 6 semantic-release-bot
git rev-list --count HEAD        # 1850 commits total
git remote -v                    # origin = github.com:KofTwentyTwo/alt-tab-free.git
```

Findings:

- **The paywall was born in one commit, upstream.** `src/pro/` has only ever been touched
  by three commits, and it was **added** in `9147a4a8 "feat: introducing alt-tab pro!"`,
  authored by `lwouis <lwouis@gmail.com>` on **2026-04-05**, shipped as **v11.0.0**
  (`1f2b5a51 "chore(release): 11.0.0 [skip ci]"`). The commit immediately before the pro
  era (`317a485b`) is v10.12.0. Confirmed `src/pro/` did not exist before 9147a4a8
  (`git log 9147a4a8~1 -- src/pro` is empty).
- **This is not a diverged fork.** The author of every recent commit — including bug
  fixes after the pro launch (`f3fe535a`, `cddc89dd`, `e0b1778d`, etc.) — is `lwouis`.
  There are **zero commits by KofTwentyTwo / the current owner**. The "alt-tab-free" repo
  is a mirror of upstream `lwouis/alt-tab-macos` re-hosted under a new origin
  (`git@github.com:KofTwentyTwo/alt-tab-free.git`), with the codebase otherwise unchanged.
  The README still markets it as "AltTab Pro" and links `https://alt-tab.app/`
  (`README.md:1`).

### 6.2 What `9147a4a8` actually changed

It was a **1,869-file** commit — far more than just adding `src/pro/`. It simultaneously
introduced the paywall *and* performed a large repo-wide reorganization (many files were
moved into new folder structures: `macos/api-wrappers/`, `switcher/main-window/`,
`switcher/state/`, `kit/`, `preferences/settings-window/tabs/...`, etc.). So the v11.0.0
boundary is both "Pro launches" and "big refactor," which makes a literal
`git revert 9147a4a8` impractical.

**Files added under `src/pro/` in that commit (the paywall proper):**
- `src/pro/license/` — `Clock.swift`, `Keychain.swift`, `LicenseAPI.swift`,
  `LicenseCookie.swift`, `LicenseManager.swift`, `LicenseState.swift`,
  `MachineFingerprint.swift`, `RemoteLicenseClient.swift`.
- `src/pro/scheduling/` — `ProTransitionManager.swift`, `ProTransitionScheduler.swift`,
  `ProTransitionState.swift`, and the trial-nag windows/popovers
  `Day1WelcomeLetterWindow`, `Day4TourPopover`, `Day12HeadsUpPopover`,
  `Day15FullUpgradeWindow`, `Day15HardGatePopover`, `Day15ProactiveWindow`,
  `Day21ReminderPopover`, `Day35FinalWindow`.
- `src/pro/ui/` — `ProBadgeView`, `ProGradientButton`, `ProPromptHeader`,
  `ProPromptHost`, `ProPromptPopover`, `ProPromptWindow`, `UsageStatHeroView`.
- `src/pro/` root — `ProConversionCopy.swift`, `ProFeature.swift`, `ProFeatureCopy.swift`.

(Subsequent commit `60cca89b` added co-located `*Specs.md` / `*Tests.swift` under
`src/pro`, the only other src/pro churn.)

### 6.3 Upstream vs fork-added top-level areas

Because this repo *is* upstream-as-of-v11.x, the right framing is **upstream AltTab core
vs the v11.0.0 paywall graft**, not "fork-added" (there is no fork-added code):

- **Upstream AltTab core (keep):** `src/switcher/`, `src/events/`, `src/macos/`,
  `src/preferences/` (minus pro-gating hooks), `src/kit/`, `src/util/`,
  `src/experimentations/`, `src/secondary-windows/` (feedback/debug), `App.swift`,
  `main.swift`, `MainMenu.swift`, `Menubar.swift`, and the `vendor/Sparkle` +
  `vendor/ShortcutRecorder` deps. These predate and are independent of the paywall.
- **Paywall graft (remove):** the entire `src/pro/` tree, plus the call sites that hook it
  into the core — e.g. `App.swift:428-429` (`ProTransitionManager` wiring), `:448-459`
  (`LicenseManager` callbacks, `syncLicenseCookie`), `Menubar.swift:46/48/49` ("Get Pro",
  "My Account", "Support this project"), `App.swift:111-120`
  (`supportProject`/`upgradeToPro`/`openAccount` selectors), `UpgradeTab`, and the
  `src/pro/license/` network/keychain/fingerprint machinery (`src/api/Endpoints.swift`
  license/account/checkout URLs, `LicenseCookie`). These are detailed in the
  paywall-specific audit sections; this section flags them only as the fork/upstream
  boundary.
- **Telemetry/diagnostics (decide):** `vendor/AppCenter` + `src/vendors/AppCenterCrashes.swift`
  (crash reporting), feedback POST, Sparkle appcast — first-party, not paywall, but tied to
  `alt-tab.app` and the lwouis signing identity.

---

## 7. Branding / identity strings that tie the binary to the paywalled product

Everything below is still the **upstream lwouis identity** — none of it has been rebranded
for "alt-tab-free" yet. Each is a string a clean free build must change or remove.

| What | Value | Location |
|---|---|---|
| App name | `AltTab` | `config/base.xcconfig:3` (`PRODUCT_NAME`), surfaced via `App.name` `src/App.swift:13` |
| Bundle id | `com.lwouis.alt-tab-macos` | `config/base.xcconfig:4`; also hardcoded in `src/_test-support/Mocks.swift:133`; consumed by `UsageStats.swift:2` and the URL scheme `Info.plist:46-58` |
| Source-code / repo URL | `https://github.com/lwouis/alt-tab-macos` | `src/App.swift:16` (`App.repository`); shown as "Source code" link in `AboutTab.swift:19` |
| Website domain | `alt-tab.app` | `config/base.xcconfig:20` (`DOMAIN`), `Info.plist:75-76` |
| API domain | `alt-tab.app/api` | `config/base.xcconfig:21` (`API_DOMAIN`), `Info.plist:77-78` |
| Website link | `https://alt-tab.app` | `Endpoints.website` `src/api/Endpoints.swift:6`; "Website" link `AboutTab.swift:18` |
| Support/donate URL | `alt-tab.app/support` | `Endpoints.supportUrl` `Endpoints.swift:8`; opened by `App.supportProject()` `App.swift:111-112`; menubar "Support this project" `Menubar.swift:49` |
| Checkout/pricing URL | `alt-tab.app/pricing` | `Endpoints.checkoutUrl` `Endpoints.swift:9` (paywall) |
| Account URL | `alt-tab.app/my-account` | `Endpoints.accountUrl` `Endpoints.swift:10`; opened by `App.openAccount()`/`UpgradeTab.swift:273`; menubar "My Account" `Menubar.swift:48` |
| License API base | `https://alt-tab.app/api/v1/license` | `Endpoints.licenseApiBaseUrl` `Endpoints.swift:11` (paywall) |
| Feedback URL | `https://alt-tab.app/api/v1/feedback` | `Endpoints.feedbackUrl` `Endpoints.swift:12` |
| Appcast URL | `https://alt-tab.app/appcast.xml` | `Endpoints.appcastUrl` `Endpoints.swift:7`; `SparkleDelegate.swift:27` |
| Sparkle signing key | `SUPublicEDKey = 2e9SQOBoaKElchSa/4QDli/nvYkyuDNfynfzBF6vJK4=` | `Info.plist:62` (the upstream EdDSA key; cannot sign updates without lwouis's private key) |
| AppCenter app secret | `$(APPCENTER_SECRET)` -> lwouis's AppCenter app | `Info.plist:73-74`, `config/*.xcconfig`, `Secrets.swift:6` |
| Menubar upsell text | "Get Pro" | `Menubar.swift:46`, `:380` |
| Crash dialog copy | "AltTab crashed last time you used it…" | `AppCenterCrashes.swift:61-62` |
| Copyright | "GPL-3.0 licence" | `Info.plist:20-21` (license — keep, it's correct) |
| README marketing | "AltTab Pro — … — Get AltTab", links `https://alt-tab.app/` | `README.md:1` |

Code identifiers named `AltTab*` (e.g. `AltTabKey`, image asset names) and references to
`lwouis/alt-tab-macos` GitHub **issue numbers** inside code comments
(`src/macos/api-wrappers/MissionControl.swift:32`, `src/switcher/state/Applications.swift:109-110`,
`src/switcher/state/WindowThumbnails.swift:35`, etc.) are benign provenance/attribution and
can stay; they don't gate behavior. The `changelog.md` is entirely upstream-linked but is a
doc artifact, not shipped behavior.

**Keychain/identity caveat (from AGENTS.md):** the bundle id `com.lwouis.alt-tab-macos`
is coupled to Developer ID / TeamID and to keychain items used by the license code.
For a free build that *removes* licensing, the keychain coupling stops mattering (no
stored license keys to orphan), so rebranding the bundle id to a KofTwentyTwo identifier
is safe and recommended. If any licensing were retained, a keychain migration would be
required first.

---

## 8. Rebase-on-upstream vs clean-this-fork

Because the audit shows this repo is **upstream code re-hosted, with the paywall authored
upstream**, the owner has a real choice:

**Option A — Rebase the free build on a pre-Pro upstream tag.**
Upstream `lwouis/alt-tab-macos` is alive and GPL-3.0. v10.12.0 (`317a485b`) is the last
release **before** the Pro paywall (`9147a4a8` / v11.0.0). A free build could branch from
the pre-11.0.0 state and then cherry-pick only the *non-paywall* bug fixes that landed in
the 11.x line. Pros: no paywall code to extract, no `src/pro/` entanglement, no license
cookie/fingerprint surfaces, no need to reverse the 1,869-file Pro reorg. Cons: loses any
genuinely useful non-paywall improvements made *after* v11.0.0 unless individually
cherry-picked; the v11 refactor is intermixed with the paywall, so picking later fixes
that depend on the new folder layout is harder.

**Option B — Clean this snapshot (remove `src/pro/` + hooks in place).**
Keep the current v11.x codebase (with its newer fixes/refactor) and surgically remove the
paywall: delete `src/pro/`, the App.swift/Menubar/UpgradeTab hooks, the license/account/
checkout endpoints, the license cookie, and decide on AppCenter. Pros: keeps the latest
window-switching improvements. Cons: more invasive, must verify the build still links and
that nothing in the core silently depends on `LicenseManager`/`ProTransitionManager`
(the App.swift wiring at `:428-459` is the main coupling to untangle).

GPL-3.0 permits either path (the fork must stay GPL-3.0 and preserve `LICENCE.md` and the
`NSHumanReadableCopyright` notice). Given that the goal is "all features unlocked," and the
paywall gates **existing** AltTab features rather than adding new ones, **both options yield
the same feature set**; the decision is really "do we want the post-v11 fixes badly enough
to do the harder in-place removal (B), or do we prefer the clean slate of pre-paywall
upstream (A)?" A pragmatic hybrid is to start from this snapshot (B) for the newer fixes
but use upstream's v10.12.0 as a reference for what the core looked like before the graft.

Either way, the telemetry/branding cleanup in §2, §4, §5, and §7 is identical and must be
done on top of whichever base is chosen — most importantly: drop the license-tier cookie,
repoint or remove the appcast + Sparkle signing key, decide AppCenter's fate, and rebrand
the bundle id / name / URLs off the `lwouis` / `alt-tab.app` identity.
