# TODO — CommandTabFree

_Updated 2026-06-16. The **publishing pipeline + auto-update are LIVE** — **v100.2.0** released (signed, notarized, Gatekeeper-accepted, auto-updating). The only substantial remaining work is upstream-sync automation. Full detail: `docs/CICD-STATUS.md`, `docs/EXECUTION-STATUS.md` §3._

## ✅ Done this session (2026-06-16)
- [x] **Signed + notarized releases** — Developer ID `James Maes (2X834TJ5MA)`; cert + creds in `production` secrets; `CODE_SIGN_IDENTITY`/Manual/`TEAM_ID` in `config/local.xcconfig`; vendored Sparkle helpers re-signed. Full tail proven (runs `27643432063` v100.1.0, `27647918163` v100.2.0).
- [x] **Auto-update** — `DOMAIN = koftwentytwo.github.io/CommandTabFree`, `SUEnableAutomaticChecks = true`, in-tree `appcast.xml` removed + gitignored. GitHub Pages serves the gh-pages feed; v100.2.0 ships auto-updating.
- [x] **Homebrew cask** — bumped to v100.2.0 + quarantine-strip postflight dropped (`KofTwentyTwo/homebrew-tap`).
- [x] **Release-gate decouple** — sign/notarize/release apparatus gated on a `will-release` signal (empty `VERSION.txt` ⇒ no release); non-release pushes build+test without cutting a release or needing `[skip ci]`.
- [x] genstrings gate fixed (`d1e1b296`); ad-hoc-until-cert build (`6070f0cb`); `.fork-sync-state` reset to `v11.3.0` + release tail no longer clobbers it; 3 sync labels created.

## Remaining — Upstream-sync automation (owner-gated)
- [ ] **`SYNC_BOT_TOKEN`** — GitHub App installation token (or fork PAT with contents + pull-requests write). Default `GITHUB_TOKEN` does NOT re-trigger PR checks, so guards never run on the sync PR.
- [ ] **External cron** — hit `repository_dispatch` (type `upstream-sync`) from an external scheduler (immune to GitHub's 60-day in-repo `schedule:` auto-disable).
- [ ] **Re-wire the `.fork-sync-state` cursor advance** into the upstream-sync merge flow so it records the synced **UPSTREAM** tag (not the fork release tag) — `upstream_sync.yml` (PLAN §4.2).

## Optional
- [ ] kof22.com custom domain for the appcast (one DNS CNAME → `koftwentytwo.github.io`; GitHub redirects the github.io URL, so existing builds keep updating).

## Bootstrap acceptance tests (after upstream-sync is wired)
- [ ] Sync PR through the bot shows guard checks running.
- [ ] A deliberately-relocked branch goes RED on `guard.yml`.
- [x] Fork build N→N+1 auto-updates via Sparkle — infra live (feed served + v100.2.0 auto-update-enabled); end-to-end N→N+1 confirmed on the next release.
