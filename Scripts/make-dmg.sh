#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Luca Gibelli
# SPDX-License-Identifier: GPL-2.0-only
#
# make-dmg.sh — package the notarized app into a distributable DMG.
#
# Run after Scripts/notarize.sh. The DMG is signed and notarized in its own
# right: Gatekeeper assesses the container as well as the app inside it, so a
# bare DMG around a notarized app still warns on first open.
#
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
cd "$PROJECT_ROOT"

APP="out/$APP_NAME.app"
[ -d "$APP" ] || die "build first: ./Scripts/notarize.sh"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/$APP_NAME-$VERSION.dmg"
STAGE="build/dmg"
IDENTITY="$(signing_identity)"

say "Staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"     # the familiar drag-to-install layout

say "Creating $DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

# LaunchServices indexes any app bundle it sees. Drop the staged copy's
# registration while it still exists, so no record points at a deleted path.
ls_unregister "$STAGE/$APP_NAME.app"
rm -rf "$STAGE"

if [ "$IDENTITY" != "-" ]; then
    say "Signing the DMG"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"

    # A signed DMG is a release DMG, and a release is notarized.
    require_notary_credentials
    say "Notarizing the DMG"
    notary_submit "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
else
    printf "\n\033[1;33mNOTE:\033[0m ad hoc build — the DMG is unsigned and will warn on other Macs.\n"
fi

# Verify the artifact the way a recipient receives it, rather than trusting the
# build log: mount the image and assess the app inside it.
say "Verifying the image as a recipient receives it"
MNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MNT"
# spctl rejects an ad hoc app; report that and go on, so the image is still
# detached below.
spctl -a -vvv -t execute "$MNT/$APP_NAME.app" 2>&1 | head -3 | sed 's/^/  /' || true
if xcrun stapler validate "$MNT/$APP_NAME.app" >/dev/null 2>&1; then
    echo "  stapled ticket valid — opens offline, no Gatekeeper warning"
else
    echo "  WARNING: no stapled ticket; users without network will see a warning"
fi
# Mounting registered the app inside the image. Drop that registration before
# unmounting, while the path still exists.
ls_unregister "$MNT/$APP_NAME.app"
hdiutil detach "$MNT" -quiet
rmdir "$MNT" 2>/dev/null || true

say "Done"
ls -lh "$DMG"
