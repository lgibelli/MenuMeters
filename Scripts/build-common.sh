#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Luca Gibelli
# SPDX-License-Identifier: GPL-2.0-only
#
# build-common.sh — shared configuration and helpers for the MenuMeters build
# and release scripts. Source this file, don't run it.
#
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MenuMeters"
BUNDLE_ID="it.salamacchine.menumeters"
INFO_PLIST="$PROJECT_ROOT/MenuMeters-Info.plist"

# Account-specific values live in a local, gitignored release.env so the repo
# carries no account identifiers. Copy release.env.example and fill it in.
[ -f "$PROJECT_ROOT/release.env" ] && source "$PROJECT_ROOT/release.env"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# The keychain account holding the Ed25519 key that signs updates. MenuMeters
# has its own, so a key leaked for another app cannot sign updates for this one.
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-menumeters}"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Drop a LaunchServices registration for a path that is about to disappear.
# Staging directories and mounted disk images both create these, and a record
# pointing at a deleted path confuses LaunchServices about the installed copy.
# Call this while the path still EXISTS: lsregister cannot reliably drop a
# record for something already deleted or unmounted.
ls_unregister() {
  local p="$1"
  [ -x "$LSREGISTER" ] || return 0
  "$LSREGISTER" -u "$p" 2>/dev/null || true
  # LaunchServices stores the physical path. /tmp and /var are symlinks to
  # /private/tmp and /private/var, so the logical form alone does not match.
  local phys
  phys="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")"
  # Guard every lsregister call with `|| true`: it exits non-zero when there
  # is nothing to unregister, which would abort a script running under set -e.
  if [ -n "$phys" ] && [ "$phys" != "$p" ]; then
    "$LSREGISTER" -u "$phys" 2>/dev/null || true
  fi
  return 0
}

say() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
die() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

require_team_id() {
  [ -n "$TEAM_ID" ] || die "TEAM_ID is not set.
       Export it, or copy release.env.example to release.env and fill it in."
}

# True when App Store Connect API key credentials are available. Preferred in CI,
# where a login keychain is awkward to provision.
have_api_key() {
  [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] \
    && [ -n "${APPLE_API_ISSUER:-}" ]
}

require_notary_credentials() {
  have_api_key && return 0
  [ -n "$NOTARY_PROFILE" ] || die "No notarization credentials.
       Either set APPLE_API_KEY_PATH / APPLE_API_KEY_ID / APPLE_API_ISSUER,
       or set NOTARY_PROFILE in release.env."
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
      --output-format json >/dev/null 2>&1 || \
    die "notarytool keychain profile '$NOTARY_PROFILE' is missing or invalid.
       Create one with:
         xcrun notarytool store-credentials '$NOTARY_PROFILE' \\
           --apple-id 'you@example.com' --team-id '$TEAM_ID' \\
           --password '<app-specific-password>'"
}

# notary_submit <path-to-zip-or-dmg>
notary_submit() {
  if have_api_key; then
    xcrun notarytool submit "$1" \
      --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER" --wait --timeout 20m
  else
    xcrun notarytool submit "$1" \
      --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m
  fi
}

# Resolves the Developer ID Application identity for TEAM_ID, falling back to
# adhoc ("-") for local development builds and CI.
signing_identity() {
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then echo "$CODESIGN_IDENTITY"; return; fi
  if [ -n "$TEAM_ID" ]; then
    local found
    found=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep "Developer ID Application: .*($TEAM_ID)" \
            | head -1 | sed 's/.*"\(.*\)"/\1/')
    if [ -n "$found" ]; then echo "$found"; return; fi
  fi
  echo "-"
}

# require_hardened_runtime <app>
#
# Capture first rather than piping into `grep -q`: under `set -o pipefail`,
# grep -q exits on the first match, codesign takes SIGPIPE, and the pipeline
# reports failure exactly when the check succeeds.
require_hardened_runtime() {
  local flags
  flags=$(codesign -d --verbose=2 "$1" 2>&1 | grep -o 'flags=0x[0-9a-f]*([^)]*)' || true)
  case "$flags" in
    *runtime*) echo "   hardened runtime: $flags" ;;
    *) die "hardened runtime missing on $1 (got '${flags:-none}')" ;;
  esac
}

# ---- Sparkle: the update framework ----------------------------------------
#
# MenuMeters ships outside the App Store, so it updates itself, and Sparkle is
# the framework other non-App-Store Mac apps use for that. The framework is not
# committed: it is fetched from the official release and pinned by SHA-256.
# The pin matches the digest GitHub publishes for the release asset.
#
# The framework inside the tarball ships adhoc signed, so the pin is what makes
# the download reproducible. Every piece is re-signed with our own identity,
# since a framework signed by another team cannot be loaded under the hardened
# runtime.
SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SPARKLE_VENDOR="$PROJECT_ROOT/build/vendor/sparkle-$SPARKLE_VERSION"

# fetch_sparkle - download, verify and unpack the distribution. Prints the
# directory holding Sparkle.framework, bin/ and LICENSE.
fetch_sparkle() {
  if [ ! -d "$SPARKLE_VENDOR/Sparkle.framework" ]; then
    local tarball="$PROJECT_ROOT/build/vendor/Sparkle-$SPARKLE_VERSION.tar.xz"
    mkdir -p "$SPARKLE_VENDOR"
    if [ ! -f "$tarball" ]; then
      curl -sSL --fail -o "$tarball" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        || die "could not download Sparkle $SPARKLE_VERSION"
    fi
    local got
    got=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
    [ "$got" = "$SPARKLE_SHA256" ] || die "Sparkle $SPARKLE_VERSION tarball has the wrong hash.
       expected $SPARKLE_SHA256
       got      $got"
    # Only what we ship or run. The distribution also carries a test app,
    # which LaunchServices would register as an application.
    tar -xf "$tarball" -C "$SPARKLE_VENDOR" \
        ./Sparkle.framework ./bin ./LICENSE \
        || die "could not unpack $tarball"
  fi
  echo "$SPARKLE_VENDOR"
}

# sign_sparkle_framework <framework-path> <identity>
#
# Inside out: Sparkle's own executables and services first, then the framework
# that contains them. Their entitlements are preserved as shipped, and every
# piece gets the hardened runtime, which notarization requires of nested code
# too.
sign_sparkle_framework() {
  local fw="$1" identity="$2" item
  for item in "$fw/Versions/B/Autoupdate" \
              "$fw/Versions/B/Updater.app" \
              "$fw"/Versions/B/XPCServices/*.xpc; do
    [ -e "$item" ] || continue
    codesign --force --options runtime --timestamp \
             --preserve-metadata=entitlements \
             --sign "$identity" "$item" >/dev/null
  done
  codesign --force --options runtime --timestamp --sign "$identity" "$fw" >/dev/null
}
