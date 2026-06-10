#!/usr/bin/env bash

# alt-tab-free: fork-owned rewrite of upstream's update_appcast.sh (PLAN §3.3/§4.0/§4.3).
#
# Upstream appended the signed Sparkle <item> into the IN-TREE, committed appcast.xml. That is wrong
# for the fork three ways: (1) every upstream + fork release edits it -> guaranteed merge conflicts;
# (2) the fork would serve entries signed with lwouis's key its own SUPublicEDKey can't verify; and
# (3) SAFETY-CRITICAL — upstream's enclosure URL points at lwouis's releases, so Sparkle auto-update
# would pull the UPSTREAM PAYWALLED binary as the "update". This rewrite:
#   - points the enclosure at THIS FORK's releases (the single most safety-critical edit, PLAN §4.0);
#   - points releaseNotesLink at the fork's release tag (was https://alt-tab.app/changelog-bare);
#   - emits the feed OUT OF TREE (gh-pages branch) instead of editing the in-tree appcast.xml; and
#   - injects a GPL §6(d) corresponding-source pointer into the appcast <description> so users who
#     receive object code ONLY via auto-update still get a source pointer (PLAN §5(1)).
#
# This file is in the §6.2 "keep ours" recurring-conflict set.

set -exu

# GITHUB_REPOSITORY is "owner/repo" of THIS fork in GitHub Actions; deriving the URLs from it keeps
# this script fork-agnostic (no hardcoded owner). OWNER-OVERRIDABLE-BEFORE-PUBLISH: if you run this
# outside Actions, export GITHUB_REPOSITORY=<owner>/<repo> first.
fork_repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY (owner/repo of the fork) must be set}"
# OWNER-OVERRIDABLE-BEFORE-PUBLISH: the host that serves the Sparkle feed (Endpoints.appcastUrl is
# "https://$DOMAIN/appcast.xml" via the DOMAIN cascade). The feed is published to the gh-pages branch
# of this repo by default; point $DOMAIN at that gh-pages site (or CNAME it). See PLAN §3.3.
feed_branch="${APPCAST_FEED_BRANCH:-gh-pages}"
feed_path="${APPCAST_FEED_PATH:-appcast.xml}"

version="$(cat "$VERSION_FILE")"
date="$(date +'%a, %d %b %Y %H:%M:%S %z')"
minimumSystemVersion="$(awk -F ' = ' '/MACOSX_DEPLOYMENT_TARGET/ { print $2; }' < config/base.xcconfig)"
zipName="$APP_NAME-$version.zip"
edSignatureAndLength=$(vendor/Sparkle/bin/sign_update -s $SPARKLE_ED_PRIVATE_KEY "$XCODE_BUILD_PATH/$zipName")

# GPL §6(d) corresponding-source pointer for object code conveyed via Sparkle auto-update.
correspondingSource="https://github.com/$fork_repo/archive/refs/tags/v$version.tar.gz"

# alt-tab-free [depaywall]: enclosure -> THIS FORK's release asset (NOT lwouis's); releaseNotesLink
# -> the fork's release tag; <description> carries the GPL §6(d) source pointer.
echo "
    <item>
      <title>Version $version</title>
      <pubDate>$date</pubDate>
      <description>Corresponding source (GPL-3.0): $correspondingSource</description>
      <sparkle:minimumSystemVersion>$minimumSystemVersion</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$fork_repo/releases/tag/v$version</sparkle:releaseNotesLink>
      <enclosure
        url=\"https://github.com/$fork_repo/releases/download/v$version/$zipName\"
        sparkle:version=\"$version\"
        sparkle:shortVersionString=\"$version\"
        $edSignatureAndLength
        type=\"application/octet-stream\"/>
    </item>
" > ITEM.txt

# alt-tab-free [depaywall]: publish OUT OF TREE — fetch the gh-pages copy of the feed, append the new
# <item>, and push it back. The in-tree appcast.xml is an empty skeleton kept only until the owner
# removes it from the tree (see ownerActionsNeeded / PLAN §3.3). Never edit the in-tree feed here.
work_dir="$(mktemp -d)"
git clone --depth 1 --branch "$feed_branch" \
  "https://x-access-token:${GITHUB_TOKEN}@github.com/$fork_repo.git" "$work_dir/feed" 2>/dev/null || {
  # gh-pages does not exist yet: seed an empty Sparkle feed skeleton.
  git clone --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/$fork_repo.git" "$work_dir/feed"
  git -C "$work_dir/feed" checkout --orphan "$feed_branch"
  git -C "$work_dir/feed" rm -rf . >/dev/null 2>&1 || true
  cat > "$work_dir/feed/$feed_path" <<'SKELETON'
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>alt-tab-free</title>
    <language>en</language>
  </channel>
</rss>
SKELETON
}

# Append the new <item> just before </channel> (the channel close, not </language>, so the skeleton
# need not carry a <language> line for the append to work).
awk -v item_file="$PWD/ITEM.txt" '
  /<\/channel>/ && !done { while ((getline line < item_file) > 0) print line; done=1 }
  { print }
' "$work_dir/feed/$feed_path" > "$work_dir/feed/$feed_path.new"
mv "$work_dir/feed/$feed_path.new" "$work_dir/feed/$feed_path"

git -C "$work_dir/feed" config user.name  "github-actions[bot]"
git -C "$work_dir/feed" config user.email "github-actions[bot]@users.noreply.github.com"
git -C "$work_dir/feed" add "$feed_path"
git -C "$work_dir/feed" commit -m "chore(appcast): publish $APP_NAME v$version"
git -C "$work_dir/feed" push origin "$feed_branch"
