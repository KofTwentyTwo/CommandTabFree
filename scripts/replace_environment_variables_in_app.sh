#!/usr/bin/env bash

set -exu

# alt-tab-free [identity]: see docs/PLAN-maintained-fork.md §3.1 CI caveat.
#
# Upstream did `cat > config/local.xcconfig` (a TRUNCATING overwrite) writing BOTH
# CURRENT_PROJECT_VERSION and APPCENTER_SECRET, which would clobber the fork's COMMITTED
# identity block (PRODUCT_NAME / bundle id / DOMAIN / signing) on every CI run.
#
# Fork fix:
#   - APPEND only (>>), never truncate — preserve the committed identity block.
#   - Write ONLY CURRENT_PROJECT_VERSION. It is NOT in the committed block, so a single
#     appended line is collision-free (xcconfig is last-wins).
#   - DROP the APPCENTER_SECRET line entirely: telemetry is off (Edit 3, §2) and the
#     committed block already sets APPCENTER_SECRET= — re-appending it would create a
#     duplicate key.
#
# Xcode substitutes $(CURRENT_PROJECT_VERSION) into Info.plist at build time.
cat >> config/local.xcconfig <<EOF
CURRENT_PROJECT_VERSION = $(cat "$VERSION_FILE")
EOF
