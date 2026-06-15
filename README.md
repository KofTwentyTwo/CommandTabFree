# CommandTabFree

**CommandTabFree is a fork of [AltTab](https://github.com/lwouis/alt-tab-macos)
(github.com/lwouis/alt-tab-macos), © Louis Pontoise, licensed GPL-3.0.**

This fork neutralizes the AltTab Pro paywall — **all features are free.** It is
**not affiliated with, sponsored by, or endorsed by** the original author. "AltTab"
is used here only to credit the upstream project (nominative fair use); CommandTabFree
is a separate, independently-distributed build.

CommandTabFree is itself released under the **GNU General Public License v3.0** — the same
license as upstream. See [`LICENCE.md`](LICENCE.md) for the full text and
[`NOTICE.md`](NOTICE.md) for the GPL §5(a) statement of changes made in this fork.

## Install

```sh
brew install --cask koftwentytwo/tap/commandtabfree
```

CommandTabFree is **not yet signed or notarized**, so the cask removes the download
quarantine to avoid a Gatekeeper prompt. You can also download the **`.dmg`** (or `.zip`)
from the [Releases](https://github.com/KofTwentyTwo/CommandTabFree/releases) page and drag
CommandTabFree to Applications — since it's unsigned, right-click the app and choose **Open**
on first launch. On first launch, grant **Accessibility** and **Screen Recording** in System
Settings. Universal binary (Apple Silicon + Intel), macOS 10.13+.

## Based on AltTab by Louis Pontoise

This software is built on AltTab (`lwouis/alt-tab-macos`) by Louis Pontoise and its
contributors. All of upstream's copyright, attribution, contributor credits
([`docs/contributors.md`](docs/contributors.md)), and third-party acknowledgments
([`docs/acknowledgments.md`](docs/acknowledgments.md)) are retained unchanged. The
only functional change this fork makes is removing the Pro paywall so every feature
is available for free; see [`NOTICE.md`](NOTICE.md) for the precise change list.

## Corresponding source (GPL-3.0 §6)

The complete corresponding source for every released binary is this repository at the
matching release tag:

```
https://github.com/KofTwentyTwo/CommandTabFree
```

For a given release `vX.Y.Z`, the source is the repository tree at that tag, including
the committed build configuration. Only signing/notarization secrets (the Developer ID
certificate, the Sparkle EdDSA private key, and Apple notarization credentials) are
deliberately not conveyed; GPL-3.0 does not require these to be distributed.

---

<!--
  Below: upstream credit. CommandTabFree is a fork of AltTab by Louis Pontoise.
  This links to the original project for attribution, not as a download CTA for this fork.
-->

<div align="center">

CommandTabFree is a free, GPL-3.0 fork of <a href="https://github.com/lwouis/alt-tab-macos">AltTab</a> by Louis Pontoise.

</div>
