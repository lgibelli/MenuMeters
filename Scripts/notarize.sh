#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Luca Gibelli
# SPDX-License-Identifier: GPL-2.0-only
#
# notarize.sh — build, sign, notarize, staple and verify MenuMeters for
# Developer ID distribution.
#
# Prereqs (one-time):
#   1. Developer ID Application certificate in the login keychain.
#   2. TEAM_ID set, plus either NOTARY_PROFILE (a notarytool keychain profile)
#      or APPLE_API_KEY_PATH / APPLE_API_KEY_ID / APPLE_API_ISSUER for CI.
#      See release.env.example.
#
# Usage:
#   ./Scripts/notarize.sh
#
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
cd "$PROJECT_ROOT"

require_team_id
require_notary_credentials

IDENTITY="$(signing_identity)"
[ "$IDENTITY" != "-" ] || die "No Developer ID Application identity for team $TEAM_ID.
       Notarization requires a real certificate; ad hoc will not do."

APP="out/$APP_NAME.app"
VERSION=$(plist_value CFBundleShortVersionString)
ZIP="build/$APP_NAME-$VERSION.zip"
mkdir -p build

say "1/5  Build and sign"
./build-clt.sh

# Notarization is rejected outright without the hardened runtime flag.
require_hardened_runtime "$APP"

say "2/5  Zip for submission"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

say "3/5  Submit to Apple (typically 1-5 minutes)"
notary_submit "$ZIP"

say "4/5  Staple the ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

say "5/5  Gatekeeper assessment (what a user's Mac will actually do)"
spctl -a -vvv -t execute "$APP" 2>&1 | head -4

# Re-zip so the archive carries the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

printf "\n\033[1;32mDONE\033[0m\n"
echo "   Stapled app: $APP"
echo "   Zip:         $ZIP"
echo "   Next:        ./Scripts/make-dmg.sh"
