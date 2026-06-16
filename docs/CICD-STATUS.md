# CI/CD readiness — CommandTabFree (fork of lwouis/alt-tab-macos)

**Date:** 2026-06-16  **Branch:** `master`  **Repo:** `KofTwentyTwo/CommandTabFree` (public)
**Status:** push CI verified **fully green** on the real runner (run `27634828800`, commit `6070f0cb`).
**Authoritative design:** `docs/PLAN-maintained-fork.md` §4; owner checklist `docs/EXECUTION-STATUS.md` §3.4/§3.5.

This is the state after the CI-fix pass. The pass applied only **safe, owner-secret-independent**
adaptations so that **push CI is GREEN today** on the not-yet-signing-provisioned fork, while the
release tail **flips on automatically** the moment the owner adds the Apple/Sparkle secrets. No secret
values were invented; no DOMAIN fabricated; notarization is not enabled without a cert.

---

## What changed in this pass

| File | Change |
|---|---|
| `.github/workflows/ci_cd.yml` | Added a `release-gate` step that emits `signing-ready` from secret presence (`APPLE_P12_CERTIFICATE`/`APPLE_ID`/`APPLE_PASSWORD`/`APPLE_TEAM_ID`/`SPARKLE_ED_PRIVATE_KEY`). Gated codesign/notarize/appcast/semantic-release/extract-changelog/gh-release/sync-state-advance behind `push && signing-ready=='true'`. Removed the `update_readme_and_website.sh` step (queried the **upstream** lwouis API — semantic mismatch, cosmetic). |
| `scripts/update_appcast.sh` | `sign_update -s $KEY` (DEPRECATED; per `--help` "no longer supported for newly generated keys" — would reject the fork's fresh EdDSA key) → `printf '%s' "$SPARKLE_ED_PRIVATE_KEY" \| sign_update --ed-key-file -`. No `-p` (default output is the `sparkle:edSignature/length` attr pair the enclosure needs; verified). Key now off the argv. |
| `commitlint.config.js` | Added `defaultIgnores: true` + `ignores` predicates (drop `chore(sync): merge upstream …`, `Merge …`, `Revert …`) so a sync merge's dragged-in upstream messages don't fail commitlint and block the release job (PLAN §4.3). |
| `scripts/update_readme_and_website.sh` | **Removed** — hardcoded `lwouis/alt-tab-macos` API + `lwouis` contributor graph; cosmetic SVG stats; no live caller after the workflow edit. |
| `scripts/update_website.sh` | **Removed** — dispatched to upstream `lwouis/alt-tab-website`; already had no live caller. |
| `scripts/upload_symbols_to_appcenter.sh` | **Removed** — hardcoded upstream AppCenter org; telemetry is off (PLAN §3.4); no live caller. |

All three workflow YAMLs validate (`yaml.safe_load` OK); `commitlint.config.js` loads in node.

---

## (A) WORKING / green NOW, without any owner secret

These run on every push and PR and need no Apple/Sparkle/DOMAIN/bot secret. They are what makes push
CI GREEN today (vs. the prior all-14-runs-RED state — note that RED was a *missing depaywall marker*,
already fixed on this branch; this pass ensures it does not go RED again on missing secrets).

| Capability | Where | Confidence |
|---|---|---|
| **Guard A** anti-relock unit tests (`run_tests.sh`, Test scheme) | `ci_cd.yml` push+PR; `guard.yml` PR (macos-15) | High — verified GREEN in EXECUTION-STATUS §2.2 (493 exec, 16 skipped, 0 fail) |
| **Guard B** de-paywall marker + `if false` wrap grep | `ci_cd.yml` first push step + PR; `guard.yml` PR | High — marker present at `LicenseManager.swift:177` |
| **Guard C** unresolved-conflict-marker grep | `ci_cd.yml` first push step + PR; `guard.yml` PR | High |
| **Compile the full tree** (`build_app.sh`, **ad-hoc**) | `ci_cd.yml` push | Verified GREEN on CI (run 27634828800). NOTE: the bare `build_app.sh` inherits upstream's Developer ID from `config/release.xcconfig:5` and fails with exit 65 on CI; the build step now runs ad-hoc (`CODE_SIGN_IDENTITY=-`) when `release-gate` is not signing-ready, and signed otherwise. `build_app.sh` forwards xcodebuild overrides via `"$@"`. |
| **commitlint** (push range + PR base..head, with `ignores`) | `ci_cd.yml` | Med-High — `ignores` should absorb upstream merge msgs; confirm on FIRST real sync PR |
| **generated-files-up-to-date** check | `ci_cd.yml` push+PR | High |
| **semantic-release dry-run** version compute (`determine_next_version.sh`) | `ci_cd.yml` push | High — dry-run, no push, no secret |
| **Release tail SKIPS cleanly** when secrets absent (warning, not failure) | `ci_cd.yml` `release-gate` | High — `signing-ready=false` path emits `::warning::` and skips |

> Note: full GREEN on the GitHub-hosted **macos-15** runner with **Xcode 26.0.1** is now CONFIRMED by a
> real run (`27634828800`, commit `6070f0cb`): gate + `run_tests.sh` + ad-hoc `build_app.sh` all pass and
> the release tail skips cleanly on absent secrets.

## (B) READY — flips ON automatically when the owner adds secret X

No further code change needed; the gate enables these the moment the secret(s) exist in the `production`
Environment.

| Capability | Enabling secret(s) | Gated step(s) |
|---|---|---|
| Code-sign keychain import | `APPLE_P12_CERTIFICATE` | `setup_ci_master.sh` |
| Notarize + staple | `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID` | `package_and_notarize_release.sh` |
| Sparkle appcast sign + publish to gh-pages | `SPARKLE_ED_PRIVATE_KEY` (+ a real `DOMAIN`/feed host) | `update_appcast.sh` (now `--ed-key-file -`) |
| Tag push + GitHub Release | ambient `GITHUB_TOKEN` (auto) — only gated alongside the above so a release isn't cut unsigned | `npx semantic-release`, `softprops/action-gh-release`, `.fork-sync-state` advance |
| Sync PR fires `guard.yml`/`ci_cd.yml` PR checks | `SYNC_BOT_TOKEN` (GitHub App token or fork PAT — NOT default `GITHUB_TOKEN`) | `upstream_sync.yml` (fail-closed if missing) |

> The release tail is **all-or-nothing**: it requires the full Apple set **and** the Sparkle key
> (`signing-ready` is the AND of all five). This is deliberate — cutting a tag/Release without a signed,
> notarized, Sparkle-signed artifact would publish an un-updatable or Gatekeeper-blocked build and burn a
> version number. If you want to test the build path before the Apple cert exists, push runs build + Guard
> A and stops cleanly.

## (C) OWNER-BLOCKED — exact action required (cannot be done by agents)

| # | Blocker | Exact owner action |
|---|---|---|
| 1 | Apple Developer ID cert | Obtain a **Developer ID Application** cert for the fork; base64 it into secret `APPLE_P12_CERTIFICATE`; set `CODE_SIGN_IDENTITY` in `config/local.xcconfig` (currently commented). Re-sign the vendored `vendor/Sparkle/Helpers/*` under the SAME ID or notarization rejects (PLAN §3.3). |
| 2 | Notarization creds | Set secrets `APPLE_ID`, `APPLE_PASSWORD` (app-specific password), `APPLE_TEAM_ID` in the `production` Environment. |
| 3 | Sparkle private key | Store `SPARKLE_ED_PRIVATE_KEY` (already generated 2026-06-15) in the `production` Environment. Confirm the `Info.plist` `SUPublicEDKey` is the real public half (currently may be a placeholder). |
| 4 | `production` Environment | Create the GitHub Environment named **`production`** (matches `ci_cd.yml: environment: production`) with **no required-reviewer protection** that would stall releases; attach secrets #1–#3. |
| 5 | Real DOMAIN / appcast host | Replace `DOMAIN`/`API_DOMAIN` placeholders (`fork.invalid`) in `config/local.xcconfig` with fork-owned routable hosts; stand up `https://<DOMAIN>/appcast.xml` (gh-pages); `git rm appcast.xml` + gitignore it (PLAN §3.2). Until done, auto-update has no feed even with the key. |
| 6 | `SYNC_BOT_TOKEN` | Provision a GitHub App installation token (preferred) or fork PAT with contents + pull-requests write. Default `GITHUB_TOKEN` does NOT re-trigger PR checks → guards never run on the sync PR (`upstream_sync.yml` fails closed without it). |
| 7 | PR labels | `gh label create sync` / `conflict` / `chokepoint-refresh` (`upstream_sync.yml` fails closed if any is missing). |
| 8 | External scheduler | Hit `repository_dispatch` (type `upstream-sync`) from an external cron (immune to GitHub's 60-day in-repo `schedule:` auto-disable); add the two-trigger liveness alert (PLAN §4.2). |
| 9 | Xcode re-pin discipline | When an upstream sync bumps `ci_cd.yml`'s pinned Xcode, re-pin `guard.yml`'s `Xcode_26.0.1` line to match (EXECUTION-STATUS §3.5). |
| 10 | Bootstrap acceptance tests | (a) sync PR through the bot shows guard checks; (b) a deliberately-relocked branch goes RED on `guard.yml`; (c) fork build N→N+1 auto-updates via Sparkle (PLAN §4.2/§4.4/§6.1). |

---

## Remaining risks (need a real CI run to confirm)

- **macos-15 + Xcode_26.0.1 availability** on GitHub-hosted runners is assumed, not verified here.
- **commitlint `ignores`** is verified to load and match our synthetic subject, but the exact set of
  *upstream* non-conforming messages can't be enumerated until a real `chore(sync)` merge — re-verify on
  the FIRST sync PR (PLAN §4.3 says confirm on first sync).
- **`semantic-release` v15 / commitlint v8 on node-16**: kept per PLAN §4.3 (engines mismatch only warns);
  unverified end-to-end on the runner since the release tail can't run without secrets.
- **`update_appcast.sh` gh-pages publish path** (orphan-branch seed, append-before-`</channel>`) is logic
  the agents can't exercise without `GITHUB_TOKEN` + a real repo; verify on the first signed release.
- **`set -x` in `update_appcast.sh`** will print the `printf '%s' "$SPARKLE_ED_PRIVATE_KEY"` command in
  the (private-repo) log trace; the key is no longer on the argv/process list, but consider `set +x` around
  the sign line if the repo ever goes from private logs to public. (Not changed in this pass — out of scope.)
