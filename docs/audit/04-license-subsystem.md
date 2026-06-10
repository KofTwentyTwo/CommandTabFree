# Audit 04 — License / Activation Subsystem

> Scope: `src/pro/license/` — `LicenseManager.swift`, `LicenseState.swift`, `LicenseAPI.swift`, `RemoteLicenseClient.swift`, `LicenseCookie.swift`, `Keychain.swift`, `MachineFingerprint.swift`, `Clock.swift` (plus `LicenseManagerSpecs.md` & `LicenseManagerTests.swift`). Cross-references `src/api/Endpoints.swift`, `Info.plist`, `config/base.xcconfig`, and the app-side consumers.
>
> This is the **single source of truth** for whether the user has Pro. Every Pro gate and upsell prompt in the app reads from `LicenseManager.shared`. Removing the paywall cleanly = making this subsystem report "always Pro/free-unlocked" (or stubbing it out) without breaking the public surface the rest of the app links against.

---

## 1. The `LicenseState` model

Defined in `src/pro/license/LicenseState.swift:1-21`. It is a flat 4-case `enum LicenseState: Equatable` — **there is no separate "lifetime" enum case**:

```swift
enum LicenseState: Equatable {
    case trial(daysRemaining: Int)   // active trial, day count baked in
    case pro                          // valid paid license (any variant)
    case proExpired                   // version-limited Pro past its version cutoff
    case trialExpired                 // trial over, OR a defensively-invalidated license
}
```

Members:
- `isProAvailable: Bool` (`LicenseState.swift:7-12`) — `true` for `.trial` and `.pro`; `false` for `.proExpired` and `.trialExpired`. This is the "can the user use Pro features right now" gate.
- `debugProfileLabel: String` (`LicenseState.swift:14-20`) — `"Trial"`, `"Pro"`, or `"Free"` (both expired cases map to `"Free"`). Used only by `src/secondary-windows/DebugProfile.swift:17`.

### "Lifetime" vs "Pro" vs "version-limited" — these are *variants*, not states

The free/trial/pro/lifetime distinction the audit brief asks about is split across two mechanisms:

1. **State** (`.trial` / `.pro` / `.proExpired` / `.trialExpired`) — the runtime entitlement.
2. **Variant slug** (a string from the backend, persisted in Keychain account `variantId`) — sub-classifies a `.pro` license:
   - **Lifetime**: `LicenseManager.lifetimeVariants: Set<String> = ["pro_lifetime"]` (`LicenseManager.swift:25`). A lifetime variant has *no version cutoff, ever*.
   - **Version-limited Pro**: `LicenseManager.versionLimitedVariants: [String: String] = [:]` (`LicenseManager.swift:28`) — maps a variant slug to a max supported version string (e.g. `"variant_slug": "X.Y.Z"`). **Currently empty**, so in this build every `.pro` variant behaves as unlimited and `.proExpired` is unreachable in practice (confirmed by `testVersionLimitedPastCutoffIsProExpired` in the specs, `LicenseManagerSpecs.md:55-56`).
   - **Regular Pro**: any variant slug that is neither lifetime nor version-limited.

`isLifetimeVariant` (see §6) reads the persisted `variantId` and tests membership in `lifetimeVariants`. There is **no** `.lifetime` enum case — lifetime is just `.pro` + a particular variant slug.

### State transitions (from `LicenseManagerSpecs.md:18-23`)

```
.trial(daysRemaining)  →  .pro            (user activates a key)
.trial(daysRemaining)  →  .trialExpired   (14 days elapse)
.pro                   →  .trialExpired   (revalidation fails / license invalidated)
.pro                   →  .proExpired     (version-limited variant past its cutoff — dead code while the dict is empty)
```

---

## 2. The activation flow — `activate(_ licenseKey:)`

`LicenseManager.activate(_:completion:)` — `LicenseManager.swift:104-140`.

1. Calls `api.activate(licenseKey)` (network).
2. On `.success(response: ActivateResult)`, hops to the **main queue** and builds an all-or-nothing batch of Keychain writes:
   - `licenseKey` → account `"licenseKey"` (`keychainKeyAccount`).
   - `response.instanceId` → account `"instanceId"` (`keychainInstanceAccount`).
   - `response.variantId` (if non-nil) → account `"variantId"` (`keychainVariantAccount`).
3. **Rollback invariant** (`LicenseManager.swift:117-126`): each write is attempted in order; if any returns a status other than `errSecSuccess`, *every previously-attempted account is removed* and the call fails with `LicenseAPIError.keychainWriteFailed(account:status:)`. Validation timestamps and email are **not** written in this path, so the user can never end up half-activated. The spec (`LicenseManagerSpecs.md:29`) calls this "the most important invariant in the file."
4. On a fully successful write batch:
   - `defaults["lastValidation"] = clock.now.timeIntervalSince1970` (`LicenseManager.swift:127`).
   - `defaults["lastValidationResult"] = true` (`:128`).
   - If `response.customerEmail` is non-nil/non-empty → `defaults[customerEmailKey] = email` (`:129-131`).
   - Calls `onBeforeProUnlock()` (`:132`) **before** flipping state.
   - Sets `state = .pro` (`:133`), which triggers `didSet → onStateChanged?(state)`.
   - `completion(.success(()))`.
5. On `.failure(error)` from the API, state is untouched and the error is forwarded (`:135-137`).

The completion runs on the main thread in all branches (the whole result handler is wrapped in `DispatchQueue.main.async`).

App-side activation entrypoints:
- **URL scheme** `alt-tab://activate?license_key=...` → `App.handleCustomUrl` → `LicenseManager.shared.activate(...)` (`src/App.swift:473-485`).
- **Settings → Upgrade tab** manual key entry (`src/preferences/settings-window/tabs/UpgradeTab.swift:325`).

### Sibling network operations

- `deactivate(completion:)` — `LicenseManager.swift:142-166`. Requires both `licenseKey` and `instanceId` in Keychain (else `LicenseAPIError.invalidKey`); calls `api.deactivate`, and on success **removes all three Keychain accounts**, clears `lastValidation`, `lastValidationResult`, and `customerEmail` from defaults, then recomputes via `computeTrialState()` (→ `.trial(n)` if still inside the 14-day window, else `.trialExpired`). Consumed by `UpgradeTab.swift:405`.
- `deactivateInstance(licenseKey:instanceId:completion:)` — `LicenseManager.swift:170-174`. Remote-deactivates *another machine's* seat without touching any local state. Used to reclaim a seat after a `seatLimitExceeded` error (`UpgradeTab.swift:389`).
- `revalidateWithServer()` — `LicenseManager.swift:209-232` (see §4).

---

## 3. Remote server validation — the actual API

### Base URL resolution

`Endpoints` (`src/api/Endpoints.swift:3-13`) reads two Info.plist keys, themselves fed from `config/base.xcconfig`:

| Constant | Source | Resolved value (this build) |
|---|---|---|
| `Endpoints.domain` | Info.plist `Domain` ← xcconfig `DOMAIN` | `alt-tab.app` (`config/base.xcconfig:20`) |
| `Endpoints.apiDomain` | Info.plist `ApiDomain` ← xcconfig `API_DOMAIN` | `alt-tab.app/api` (`config/base.xcconfig:21`) |
| `Endpoints.website` | `"https://\(domain)"` | `https://alt-tab.app` |
| `Endpoints.licenseApiBaseUrl` | `"https://\(apiDomain)/v1/license"` | **`https://alt-tab.app/api/v1/license`** |

`Info.plist:75-78` declares `Domain → $(DOMAIN)` and `ApiDomain → $(API_DOMAIN)`. (Note `feedbackUrl` at `Endpoints.swift:12` is `https://alt-tab.app/api/v1/feedback` — a separate, non-license endpoint owned by the feedback window.)

`LicenseManager.shared` injects `RemoteLicenseClient(baseUrl: Endpoints.licenseApiBaseUrl, keychain: keychain)` (`LicenseManager.swift:12`).

### Endpoints, methods, request/response shapes

`RemoteLicenseClient` (`src/pro/license/RemoteLicenseClient.swift`) is a `struct` conforming to the `LicenseAPI` protocol. All three calls are **POST**, `Content-Type: application/json`, `Accept: application/json`, body via `JSONSerialization`, executed on `URLSession.shared` (`RemoteLicenseClient.swift:103-128`). The file header comment (`:1-5`) describes it as "our own licensing backend at `alt-tab.app/v1/license/*`", provider-agnostic; the `LicenseManagerSpecs.md:13` calls the backend "LemonSqueezy-backed."

**POST `{baseUrl}/activate`** (`RemoteLicenseClient.swift:15-60`)
Request body:
```json
{
  "license_key": "<key>",
  "fingerprint": "<MachineFingerprint.get>",
  "trial_started_at": <int epoch seconds>   // only if LicenseManager.shared.trialStartDate != nil
}
```
`trial_started_at` (`:23-25`) lets the backend report trial→paid conversion latency (backend takes MIN across machines; omitted after deactivation clears the local trial start).
Response DTO `ActivateResponse` (`:132-139`): `{ activated: Bool, instance_id: String?, variant_id: String?, customer_email: String?, error: String?, instances: [InstanceDTO]? }`.
Mapping (`:28-58`):
- `activated == true` but missing `instance_id` → `invalidResponse(debugInfo: "missing instance_id")`.
- `activated == true` → `ActivateResult(instanceId, variantId, customerEmail)`.
- `activated == false` + `error == "invalid_key"` → `LicenseAPIError.invalidKey`.
- `error == "seat_limit_exceeded"` → `LicenseAPIError.seatLimitExceeded(instances:)` (maps `instances` DTOs).
- any other non-nil `error` → `activationRejected(reason)`; nil error → `activationRejected("unknown")`.

**POST `{baseUrl}/validate`** (`RemoteLicenseClient.swift:62-78`)
Request body: `{ "license_key": "<key>", "instance_id": "<id>" }`.
Response DTO `ValidateResponse` (`:141-144`): `{ valid: Bool, variant_id: String? }` → `ValidateResult(valid, variantId)`.

**POST `{baseUrl}/deactivate`** (`RemoteLicenseClient.swift:80-101`)
Request body: `{ "license_key": "<key>", "instance_id": "<id>" }`.
Response DTO `DeactivateResponse` (`:146-149`): `{ deactivated: Bool, error: String? }`. `deactivated == false` → `LicenseAPIError.deactivationRejected`.

`InstanceDTO` (`:151-159`): `{ id: String, machineName: String?, lastSeenAt: Int }` → maps to the public `ActiveInstance` struct.

### `LicenseAPI` protocol & error model

`src/pro/license/LicenseAPI.swift`:
- `protocol LicenseAPI` (`:4-8`) — the three async methods. This is the seam tests mock (`MockLicenseAPI`, `LicenseManagerTests.swift:504-527`).
- Result structs: `ActivateResult` (`:10-14`), `ValidateResult` (`:16-19`), `ActiveInstance` (`:21-25`).
- `enum LicenseAPIError: LocalizedError` (`:27-58`) — `invalidKey`, `activationRejected(String)`, `seatLimitExceeded(instances:)`, `deactivationRejected`, `noData`, `invalidResponse(debugInfo:)`, `apiError(String)`, `keychainWriteFailed(account:status:)`. Provides localized `errorDescription` and an internal `debugInfo`.

### Decode-failure handling

`post<T>` (`RemoteLicenseClient.swift:103-128`): network error → forwarded; nil data → `noData`; decode failure logs `statusCode`+body and, if the raw JSON has a string `error` field, surfaces `apiError(message)`, else `invalidResponse(debugInfo:)`. **Note:** no HTTP status-code gating — a 4xx/5xx with a decodable body is treated as a normal response.

---

## 4. Async revalidation (background re-check)

- `scheduleAsyncRevalidationIfNeeded()` (`LicenseManager.swift:202-207`): on `initialize()`, computes `elapsed = now - defaults["lastValidation"]`; only calls `revalidateWithServer()` if `elapsed >= revalidationInterval`.
- `revalidationInterval = 30 * 24 * 60 * 60` (30 days) — `LicenseManager.swift:18` (private static).
- `revalidateWithServer()` (`:209-232`): requires `licenseKey` + `instanceId` in Keychain (else returns). On `api.validate` success: refreshes `lastValidation` timestamp, stores `response.valid` into `lastValidationResult`, persists a returned `variantId` to Keychain, and sets `state = computeState()` if valid or `.trialExpired` if invalid. Network failure is swallowed (`:227-228`) — state and timestamp preserved, retried next launch. Also called directly from the QA menu "Revalidate" button (`src/debug/QAMenu.swift:221`).

---

## 5. State computation, machine fingerprint, persistence

### `computeState()` / `computeTrialState()`

- `computeState()` (`LicenseManager.swift:176-190`): if a `licenseKey` exists in Keychain — read `lastValidationResult`; if missing/false → **defensively** `.trialExpired` (`:179`); if a `variantId` exists and is in `versionLimitedVariants` and `currentAppVersion()` numerically exceeds the cutoff → `.proExpired` (`:180-186`); otherwise `.pro`. If no license key → `computeTrialState()`.
- `computeTrialState()` (`:192-200`): persists `trialStartDate` on first ever call (never reset on relaunch); `daysSince = floor((now - start)/86400)`; if `>= trialDuration` → `.trialExpired`, else `.trial(daysRemaining: trialDuration - daysSince)`.
- `trialDuration = 14` (`:17`), 0-indexed: day 0 → `.trial(14)`, day 13 → `.trial(1)`, day 14 → `.trialExpired` (`LicenseManagerSpecs.md:27`).
- `currentAppVersion: () -> String` (`:42-44`) defaults to `CFBundleShortVersionString`; overridable for tests.

### Machine fingerprint

`MachineFingerprint.get(keychain:)` (`src/pro/license/MachineFingerprint.swift:9-20`): primary source is the IOKit `IOPlatformUUID` of `IOPlatformExpertDevice` (`:11-14`). Fallback: a previously-stored value at Keychain account `"machineFingerprint"` (`:5,:16`); if neither exists, generates a random `UUID().uuidString`, persists it to that Keychain account, and returns it. Only consumer is the `activate` request body (`RemoteLicenseClient.swift:18`). `validate`/`deactivate` use the stored `instanceId` instead.

### Persistence map (Keychain + UserDefaults + cookie)

**Keychain** — `SystemKeychain` (`src/pro/license/Keychain.swift:10-89`), generic-password items (`kSecClassGenericPassword`), accessibility `kSecAttrAccessibleWhenUnlocked` on write (`Keychain.swift:45`). `setValue` deletes-then-adds (`:39-48`). All items share one service:
- **Service:** `LicenseManager.keychainService = "\(App.bundleIdentifier).license"` (`LicenseManager.swift:4`) → resolves to **`com.lwouis.alt-tab-macos.license`** (`App.bundleIdentifier` = `Bundle.main.bundleIdentifier!`, `src/App.swift:11`; bundle id `com.lwouis.alt-tab-macos`, `config/base.xcconfig:4`).
- Accounts under that service:
  | Account constant | Account string | Written by |
  |---|---|---|
  | `keychainKeyAccount` | `"licenseKey"` | activate (`LicenseManager.swift:19`) |
  | `keychainInstanceAccount` | `"instanceId"` | activate (`:20`) |
  | `keychainVariantAccount` | `"variantId"` | activate / revalidate (`:21`) |
  | (MachineFingerprint) | `"machineFingerprint"` | fingerprint fallback (`MachineFingerprint.swift:5`) |
- `removeAll()` (`Keychain.swift:74-88`, DEBUG only) wipes everything under the service — used by the QA "Mock fresh install" action.

> **Code-signature coupling (from AGENTS.md):** Keychain access is tied to the app's Developer ID / TeamID / bundle id. If the free build changes the bundle id or signing identity, these items become inaccessible — but for a free build that no longer reads them, that is harmless.

**UserDefaults** — suite `LicenseManager.defaultsSuiteName = "\(App.bundleIdentifier).license"` (`LicenseManager.swift:5`) → `com.lwouis.alt-tab-macos.license`. Non-secret bookkeeping keys:
| Key | Type | Set by | Read by |
|---|---|---|---|
| `"trialStartDate"` | Double (epoch) | `computeTrialState` first launch (`:194`) | `trialStartDate`, `daysSinceTrialStart`, trial math |
| `"lastValidation"` | Double (epoch) | activate / revalidate (`:127`,`:217`) | `scheduleAsyncRevalidationIfNeeded` |
| `"lastValidationResult"` | Bool | activate / revalidate (`:128`,`:218`) | `computeState` defensive check |
| `customerEmailKey` = `"customerEmail"` | String | activate (`:130`) | `customerEmail` getter |

**HTTP cookie** — `syncLicenseCookie(state:)` (`src/pro/license/LicenseCookie.swift:5-22`) sets a `license` cookie on `.alt-tab.app` (host from `Endpoints.website`), value `"pro"` / `"proExpired"` / `""`, `secure`, `distantFuture` expiry, in `HTTPCookieStorage.shared`. Purpose: Sparkle's appcast request can be tailored per tier. Called from the `onStateChanged` hook (`src/App.swift:451`).

---

## 6. PUBLIC SURFACE — what the rest of the app depends on

`LicenseManager.shared` (`LicenseManager.swift:7-15`) is the singleton; the wider app touches **only** the members below. Each entry lists definition site + every external call site, since this is what a free-build rewrite must keep compiling.

### `state: LicenseState` — `private(set)` stored, `didSet → onStateChanged?(state)` (`LicenseManager.swift:51-53`)
The core read. External readers:
- `src/App.swift:206` — `if case .pro = ... { return false }` (gates some behavior).
- `src/Menubar.swift:86` — menubar Pro/trial display.
- `src/preferences/settings-window/SettingsWindow.swift:162,196,206` — account UI.
- `src/preferences/settings-window/tabs/UpgradeTab.swift:220` — upgrade tab rendering.
- `src/pro/scheduling/ProTransitionManager.swift:172,299` — trial-nag scheduling.
- `src/secondary-windows/DebugProfile.swift:17` — `.debugProfileLabel`.

### `isProLocked: Bool` — computed (`LicenseManager.swift:67-72`)
`true` for `.proExpired`/`.trialExpired`, `false` for `.pro`/`.trial`. **The most widely consumed gate.** Drives degradation of Pro prefs and ghosting of Pro UI:
- `src/pro/ProFeature.swift:65` (`var isLocked`).
- `src/events/PreferencesEvents.swift:62`.
- `src/preferences/PreferenceDefinition.swift:34`.
- `src/preferences/settings-window/LabelAndControl.swift:86`.
- `src/preferences/settings-window/tabs/appearance/AppearanceTab.swift:589,667`.
- `src/preferences/settings-window/tabs/controls/ControlsTab.swift:589`.
- `src/preferences/settings-window/tabs/controls/ShortcutEditor.swift:599,705`.
- `src/pro/scheduling/ProTransitionManager.swift:179`.

### `isProAvailable: Bool` — computed, delegates to `state.isProAvailable` (`LicenseManager.swift:62`)
- `src/pro/ProFeature.swift:63,75`.

### `customerEmail: String?` — computed from `defaults[customerEmailKey]` (`LicenseManager.swift:55`)
- `src/preferences/settings-window/SettingsWindow.swift:167,196,207`.
- `src/preferences/settings-window/tabs/UpgradeTab.swift:227`.

### `isLifetimeVariant: Bool` — computed from Keychain `variantId` ∈ `lifetimeVariants` (`LicenseManager.swift:57-60`)
- `src/preferences/settings-window/SettingsWindow.swift:164`.
- `src/preferences/settings-window/tabs/UpgradeTab.swift:228`.

### `onStateChanged: ((LicenseState) -> Void)?` (`LicenseManager.swift:38`)
Fired from `state.didSet` on initialize and on every transition. Wired once in `src/App.swift:449-459` to: refresh menubar license items, sync the Sparkle cookie, notify `ProTransitionManager`, refresh `UpgradeTab`/upgrade button, reset preference-dependent components, and post `proLockStateDidChangeNotification`.

### `onBeforeProUnlock: () -> Void` (`LicenseManager.swift:49`, default no-op)
Fired **before** `state` flips to `.pro` (in `activate` `:132` and `mockProUser` `:276`) so observers can snapshot pre-Pro selections. Wired in `src/App.swift:448` to `ProTransitionManager.shared.onProUnlocked()`.

### `initialize()` (`LicenseManager.swift:91-94`)
Sets `state = computeState()` then schedules async revalidation. Called once at startup: `src/App.swift:460`.

### `refreshState()` (`LicenseManager.swift:99-102`)
Recomputes `state` and reassigns only if changed (so the baked-in trial day count tracks the clock). Called before UI surfaces read the day count:
- `src/Menubar.swift:396`.
- `src/preferences/settings-window/SettingsWindow.swift:1246`.

### `activate(_:completion:)` (`LicenseManager.swift:104-140`) — see §2
- `src/App.swift:481`, `src/preferences/settings-window/tabs/UpgradeTab.swift:325`.

### Other public members consumed externally
- `deactivate(completion:)` — `UpgradeTab.swift:405`.
- `deactivateInstance(licenseKey:instanceId:completion:)` — `UpgradeTab.swift:389`.
- `revalidateWithServer()` — `QAMenu.swift:221` (DEBUG).
- `daysSinceTrialStart: Int` (`:79-82`) — `ProTransitionManager.swift:300`.
- `trialStartDate: Date?` (`:74-77`) — read internally by `RemoteLicenseClient.activate` (`:23`).
- `LicenseManager.trialDuration` (static, `=14`) — referenced for trial messaging.
- DEBUG-only QA helpers `mockTrialUser`/`mockTrialExpired`/`mockTrialDay`/`mockProUser` (`:234-279`) — `src/debug/QAMenu.swift:151,239` etc.

---

## 7. Tests & specs (skim)

- `LicenseManagerSpecs.md` — prose spec; the load-bearing rules are in §"Behavior & edge cases" (`:25-34`): 14-day 0-indexed trial, no grace period, all-or-nothing Keychain writes with rollback, defensive expiry, 30-day throttled revalidation, synchronous compute on initialize, callback ordering.
- `LicenseManagerTests.swift` — 1:1 with the spec's scenario list. Tests inject `MockClock` (`:475`), `MockKeychain` (`:482`), `MockLicenseAPI` (`:504-527`) and an isolated `UserDefaults(suiteName:)` per test (`:13-23`). They never set `onStateChanged`/`onBeforeProUnlock` side effects unless asserting on them. `mockProUser`-related test is `#if DEBUG`-guarded.

---

## 8. Removal notes for a fully-free build

**Goal:** every feature unlocked, no trial nag, no network, no Keychain license reads — without breaking the ~30 external call sites in §6.

Recommended strategy (lowest blast radius): **keep the `LicenseManager.shared` public surface, gut the internals.**
- Make `state` permanently `.pro` (or add an always-`true` short-circuit). Then `isProLocked` is always `false` and `isProAvailable` always `true` automatically — most consumers (§6) need no edits.
- Stub `activate`/`deactivate`/`deactivateInstance`/`revalidateWithServer` to no-op-success (or delete and remove the 2 activate call sites + Upgrade tab management). The `LicenseAPI`/`RemoteLicenseClient`/`MachineFingerprint`/`LicenseCookie`/`Keychain` files can then be deleted entirely, since nothing else references them.
- `customerEmail` → return nil; `isLifetimeVariant` → return false (or true). Their consumers are all in `SettingsWindow`/`UpgradeTab` account UI, which is being removed with the paywall anyway.
- `onStateChanged`/`onBeforeProUnlock`/`initialize()`/`refreshState()` can become no-ops but should remain as symbols until the `App.swift` wiring (`:448-460`), `Menubar`, and `SettingsWindow` callers are also cleaned up — otherwise the build breaks.

**What is safe to delete outright** (no external readers beyond the license subsystem itself + the paywall UI being removed): `Clock.swift`, `MachineFingerprint.swift`, `LicenseCookie.swift` (also drop the `onStateChanged` call to `syncLicenseCookie` in `App.swift:451`), `RemoteLicenseClient.swift`, `Keychain.swift`, `LicenseAPI.swift`, `LicenseManagerTests.swift`, `LicenseManagerSpecs.md`.

**Coupled removals to coordinate (outside this audit's scope but flagged):**
- `src/api/Endpoints.swift:11` `licenseApiBaseUrl` becomes dead; `Info.plist`/`config/base.xcconfig` `ApiDomain` only feeds license + feedback URLs (feedback at `Endpoints.swift:12` is independent — keep `apiDomain` if feedback stays).
- The Sparkle appcast tier cookie (`LicenseCookie.swift`) means the free build's updater no longer differentiates tiers — verify the appcast still serves the free build without the `license` cookie.
- `App.swift:473-485` URL-scheme `activate` handler and the whole `UpgradeTab` should be removed with the paywall UI.

**Risks:**
- The `private(set) var state` `didSet` fires `onStateChanged` — if you hardcode `state = .pro` at init time, ensure the `onStateChanged` hook (and `ProTransitionManager`) tolerate being invoked, or unset the hook in the free build.
- Existing installs have stale Keychain items under `com.lwouis.alt-tab-macos.license` and UserDefaults under the same suite; a free build can ignore them, but leaving them is cosmetically untidy.
- Bundle id is still `com.lwouis.alt-tab-macos` (upstream's). Republishing under a new identity will change the Keychain service name anyway (moot once license reads are gone), but is a signing/identity decision per AGENTS.md.
