#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Luca Gibelli
# SPDX-License-Identifier: GPL-2.0-only
#
# make-appcast.sh — turn a built disk image into the appcast Sparkle reads.
#
# Every item in the appcast carries the Ed25519 signature of its archive, made
# with the private key. That signature is the whole security model: an attacker
# who takes over the web server can serve a different feed, but Sparkle will
# refuse anything in it that does not verify against the public key baked into
# the app, and will refuse any app not signed by our team on top of that.
#
# The private key is read from the login keychain, under the account in
# SPARKLE_KEY_ACCOUNT (menumeters), or from $SPARKLE_PRIVATE_KEY_FILE when
# there is no keychain to read.
#
# Usage:
#   ./Scripts/make-appcast.sh [path/to/MenuMeters-X.Y.Z.dmg]
#
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
cd "$PROJECT_ROOT"

REPO_URL="https://github.com/lgibelli/MenuMeters"
SITE_URL="https://www.salamacchine.it/apps/menumeters/"

SPARKLE="$(fetch_sparkle)"

DMG="${1:-}"
if [ -z "$DMG" ]; then
  DMG="build/$APP_NAME-$(plist_value CFBundleShortVersionString).dmg"
fi
[ -f "$DMG" ] || die "no disk image at $DMG — run ./Scripts/make-dmg.sh first"

VERSION="$(basename "$DMG" .dmg)"
VERSION="${VERSION#"$APP_NAME"-}"

STAGE="build/appcast"

say "Staging $DMG as $APP_NAME-$VERSION.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$DMG" "$STAGE/$APP_NAME-$VERSION.dmg"

# The update alert shows release notes, and there is exactly one place where
# they are written: Docs/RELEASE-NOTES.md. Take this version's section from it.
NOTES="$STAGE/$APP_NAME-$VERSION.md"
awk -v want="# $APP_NAME $VERSION" '
  $0 == want { inside = 1; next }
  inside && /^# / { exit }
  inside { print }
' Docs/RELEASE-NOTES.md > "$NOTES"
if [ ! -s "$NOTES" ]; then
  rm -f "$NOTES"
  echo "   (no section for $VERSION in Docs/RELEASE-NOTES.md; shipping without notes)"
fi

KEY_ARGS=(--account "$SPARKLE_KEY_ACCOUNT")
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
  KEY_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
else
  # generate_appcast only warns about a key that does not match the app's,
  # and writes an unsigned item that every copy would refuse.
  PUBLIC_KEY=$("$SPARKLE/bin/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p 2>/dev/null || true)
  [ "$PUBLIC_KEY" = "$(plist_value SUPublicEDKey)" ] || die "the key in keychain account '$SPARKLE_KEY_ACCOUNT' is not the app's SUPublicEDKey.
       keychain: ${PUBLIC_KEY:-none}
       app:      $(plist_value SUPublicEDKey)"
fi

say "Generating and signing the appcast"
"$SPARKLE/bin/generate_appcast" \
  "${KEY_ARGS[@]}" \
  --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" \
  --link "$SITE_URL" \
  --embed-release-notes \
  --maximum-deltas 0 \
  -o "$STAGE/appcast.xml" \
  "$STAGE"

# Check what was written: the item must be signed, and must describe the
# version its download URL and release notes were chosen for.
grep -q 'sparkle:edSignature=' "$STAGE/appcast.xml" \
  || die "the appcast item is not signed; check the update key"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$STAGE/appcast.xml" \
  || die "the app in $DMG is not version $VERSION"

say "Appcast written to $STAGE/appcast.xml"
echo "   Publish it at ${SITE_URL}appcast.xml"
echo "   (copy it into www/public/apps/menumeters/ in the site repository and deploy)"
