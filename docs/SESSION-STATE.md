# SESSION-STATE — CommandTabFree (de-paywalled AltTab fork)

_Handoff written 2026-06-15. Branch: `depaywall-free` (NOT merged to master)._

## What this is
`KofTwentyTwo/alt-tab-free` is a fork of **AltTab** (`lwouis/alt-tab-macos`, GPL-3.0). Upstream author lwouis added a Pro paywall in v11.0.0 (commit `9147a4a8`); this fork **neutralizes the paywall so all features are free** and is rebranded **CommandTabFree**. Goal: ship free + keep merging upstream forever (thin, merge-stable patch — see `docs/PLAN-maintained-fork.md`).

## ✅ DONE (all on branch `depaywall-free`, HEAD `98a023aa`)
- **De-paywall** (commit `f3d76859`): 3 inert edits — `LicenseManager.computeState()` → `guard false else { return .pro }` (single state producer opens every gate); `LicenseCookie.syncLicenseCookie` + `AppCenterCrash.init` wrapped `if false`; `App.handleCustomUrl` early-returns (kills activate-fingerprint POST). `src/pro/` left physically present but inert.
- **Anti-relock tests** (`4506c539`, `1a914c88`): `testDepaywall*` guards in `LicenseManagerTests.swift`; 16 legacy paywall tests `XCTSkip`-marked. **Test scheme GREEN.**
- **Identity** (`4d82a684`): `PRODUCT_NAME=CommandTabFree`, `PRODUCT_BUNDLE_IDENTIFIER=com.koftwentytwo.commandtabfree` (FROZEN) in `config/local.xcconfig`.
- **Local-build version fix** (`e2429096`): `CURRENT_PROJECT_VERSION=0.0.0` in `local.xcconfig` (else `App.version` (App.swift:14) nil-crashes on local builds).
- **Brand sweep + About** (`f5f9034d`): 11 user-facing "AltTab"→"CommandTabFree"; About box credits upstream — _"A free fork of AltTab by Louis Pontoise — GPL-3.0"_ (`AboutTab.swift:18`), Source-code link → fork repo (`App.repository`, App.swift:16). PRESERVED: migration key `PreferencesMigrations.swift:363` "Screen showing AltTab", LICENCE/NOTICE/contributors, src/pro strings.
- **Placeholder icon** (`98a023aa`): `resources/icons/app/app.icns` = dark slate + ⌘⇥ glyph (generated; **real artwork still TODO**). Xcode scheme product name fixed → `CommandTabFree.app`.
- **Local build runs**: ad-hoc-signed `CommandTabFree.app`, de-paywalled, launches. CI/identity scaffolding (`upstream_sync.yml`, `guard.yml`, adapted `ci_cd.yml`, `update_appcast.sh`) committed earlier (`3dde8a91`).

### Build / run locally
- Ad-hoc (no cert): `xcodebuild -project alt-tab-macos.xcodeproj -scheme Debug -configuration Debug -derivedDataPath DerivedData CODE_SIGN_IDENTITY="-"` → `DerivedData/Build/Products/Debug/CommandTabFree.app`
- Stable signature (recommended, fixes the TCC loop): `scripts/codesign/setup_local.sh` (needs keychain/admin approval — user runs it), then `ai/build.sh`; afterwards `rm -f codesign.{conf,key,crt,p12}`.
- **TCC permission loop** (ad-hoc rebuilds leave stale grants): `tccutil reset ScreenCapture com.koftwentytwo.commandtabfree && tccutil reset Accessibility com.koftwentytwo.commandtabfree`. The durable fix is the stable cert above.

## ⏳ NEXT (publish checklist — see `docs/EXECUTION-STATUS.md` §3)
Owner-gated, **Apple Developer ID is the long pole** (user struggling): KofTwentyTwo must enroll as an **Organization** under a *separate* Apple ID (their primary is MMLT's Account Holder; account `744245396565` = `kingsrook_root_admin` profile) + D-U-N-S + $99. Then:
- Sparkle EdDSA keypair (I generate, owner stores private key as CI secret)
- GitHub secrets in a `production` environment; `gh label create sync conflict chokepoint-refresh`; external cron for `upstream_sync.yml`
- `DOMAIN`/appcast host → **kof22.com is ready** (see DNS below); replace `fork.invalid` in `local.xcconfig`
- **Real icon artwork** (replace placeholder)
- Push `depaywall-free` + open PR (runs `guard.yml`, no secrets) → merge → signed/notarized release

## DNS/mail (DONE this session — infra, not the fork repo)
Plan at `/Users/james.maes/Git.Local/kof22/DNS-MAIL-PLAN.md` (outside repo). Both `kof22.com` and `koftwentytwo.com` migrated to benchfinity-style vanity NS (`ns1/ns2.<domain>` glued to `.146`) on the **Synology DNS Server**; `realm.direct` retired for these two. `koftwentytwo.com`: web→`50.122.5.146` (=kof22), MX→`mail.kof22.com` (per-domain mail; each IP runs Postfix/Dovecot), added as MailPlus additional domain on `.146`. Outbound relays via **SocketLabs** (`include:email-od.com`, DKIM CNAME→`dkim._domainkey.email-od.com`). Registrar = AWS acct `744245396565` (`AWS_PROFILE=kingsrook_root_admin`; `--profile` flag breaks the wrapper — use the env var). Inbound mail test was never confirmed (couldn't send from this VPN-blocked machine).

## Key docs
`docs/AUDIT.md` (master audit) · `docs/GRAPHS.md` (mermaid) · `docs/PLAN-maintained-fork.md` (the strategy — thin patch + merge tracking + CI) · `docs/PLAN-republish-free.md` (one-shot excision, superseded) · `docs/EXECUTION-STATUS.md` (publish checklist) · `docs/audit/01–09-*.md` (deep dives).

## Gotchas
- Don't merge to master / don't `git revert 9147a4a8` (mixes paywall with a 1869-file reorg).
- `aws`: use `AWS_PROFILE=kingsrook_root_admin aws …` (the `--profile` flag fails on the local wrapper); SSO token expires (`aws sso login`).
- Bundle id is FROZEN (keychain/UserDefaults suite derives from it).
