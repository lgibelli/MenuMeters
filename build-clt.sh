#!/bin/bash
#
# Copyright (c) 2026 The MenuMeters contributors (see the Git history)
# SPDX-License-Identifier: GPL-2.0-only
#
# Changes:
# 2026-10     gonejack: written.
# 2026-10-30  Luca Gibelli: Sparkle, hardened runtime, Developer ID signing,
#             parallel architecture builds, --dev.
#
# Build MenuMeters with the Command Line Tools only (no Xcode installation).
#
#   ./build-clt.sh          release build: universal, optimized
#   ./build-clt.sh --dev    development build: this Mac's architecture only,
#                           unoptimized, with debug info, signed ad hoc
#
# Either way it produces a complete, signed application bundle:
#
#   out/MenuMeters.app
#
# The bundle contains the Swift executable (arm64 + x86_64, or only the native
# architecture for --dev), the Sparkle update framework, the localized string
# tables, the disk icon sets, the About text and the license notices. Run it
# with `open out/MenuMeters.app`.
#
# A release build is signed with the Developer ID Application identity for
# TEAM_ID when one is available (see release.env.example), and ad hoc
# otherwise; a --dev build is always signed ad hoc. Either way it
# gets the hardened runtime. The first build downloads Sparkle once into
# build/vendor and checks it against a pinned SHA-256.
#
set -euo pipefail
source "$(dirname "$0")/Scripts/build-common.sh"
cd "$PROJECT_ROOT"

DEV=0
case "${1:-}" in
    "") ;;
    --dev) DEV=1 ;;
    *) die "usage: $0 [--dev]" ;;
esac

SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=out
APP="$OUT/MenuMeters.app"
OBJ="$OUT/obj"
RES="$APP/Contents/Resources"
DEPLOYMENT_TARGET=26.0
CORES=$(sysctl -n hw.ncpu)
if [ "$DEV" = 1 ]; then
    IDENTITY="-"
    ARCHS=("$(uname -m)")
else
    IDENTITY="$(signing_identity)"
    ARCHS=(arm64 x86_64)
fi
SPARKLE="$(fetch_sparkle)"

rm -rf "$OUT"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$RES"

SOURCES=(Sources/MenuMeters/*.swift)
COMMON_FLAGS=(
    -sdk "$SDK"
    -module-name MenuMeters
    -swift-version 5
    -F "$SPARKLE" -framework Sparkle
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks
)
if [ "$DEV" = 1 ]; then
    # Without whole-module optimization the driver compiles the files as
    # separate jobs, CORES at a time.
    COMMON_FLAGS+=(-Onone -g -j "$CORES")
else
    # The two architectures compile at the same time, and each splits its code
    # generation across threads, as Xcode does for whole-module builds.
    COMMON_FLAGS+=(-O -whole-module-optimization -num-threads $(( (CORES + 1) / 2 )))
fi

PIDS=()
THIN=()
for arch in "${ARCHS[@]}"; do
    say "Compiling $arch"
    xcrun swiftc "${COMMON_FLAGS[@]}" \
        -target "$arch-apple-macos$DEPLOYMENT_TARGET" \
        -o "$OBJ/MenuMeters-$arch" \
        "${SOURCES[@]}" &
    PIDS+=("$!")
    THIN+=("$OBJ/MenuMeters-$arch")
done
FAILED=0
for pid in "${PIDS[@]}"; do
    wait "$pid" || FAILED=1
done
[ "$FAILED" = 0 ] || die "compilation failed"

lipo -create "${THIN[@]}" -output "$APP/Contents/MacOS/MenuMeters"
chmod +x "$APP/Contents/MacOS/MenuMeters"
if [ "$DEV" = 1 ]; then
    # Keep the debug symbols beside the app, where lldb looks for them.
    DSYM="$OUT/MenuMeters.app.dSYM"
    mv "$OBJ/MenuMeters-${ARCHS[0]}.dSYM" "$DSYM"
    mv "$DSYM/Contents/Resources/DWARF/MenuMeters-${ARCHS[0]}" \
        "$DSYM/Contents/Resources/DWARF/MenuMeters"
fi
rm -rf "$OBJ"

# Info.plist is already a concrete, Xcode-variable-free plist.
cp MenuMeters-Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ditto, not cp -R: Sparkle.framework is a versioned bundle whose symlinks
# have to survive the copy, or the loader will not find it.
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Application resources.
cp Resources/MenuMeters.icns "$RES/"
cp Resources/Welcome.rtf "$RES/"
cp Resources/com.ragingmenace.MenuMeters.plist "$RES/"
cp Resources/releases.html "$RES/"
cp LICENSE "$RES/"
cp Docs/Acknowledgements.md "$RES/"
# The Xcode project ships the same committed copy of Sparkle's notice.
cmp -s "$SPARKLE/LICENSE" Resources/Sparkle-LICENSE.txt \
    || die "Resources/Sparkle-LICENSE.txt differs from Sparkle $SPARKLE_VERSION's LICENSE"
cp Resources/Sparkle-LICENSE.txt "$RES/"
cp Resources/DiskIcons/*.tiff "$RES/"
cp -R Resources/*.lproj "$RES/"

ENTITLEMENTS=()
if [ "$IDENTITY" = "-" ]; then
    # Library validation is part of the hardened runtime and refuses to load a
    # framework signed by anybody else. With a Developer ID signature that is
    # exactly what we want; with an ad hoc one there is no team to compare, so
    # Sparkle would never load. Ad hoc builds drop it, as the Xcode project does.
    ENTITLEMENTS=(--entitlements Resources/MenuMeters-adhoc.entitlements)
fi

say "Signing as: $IDENTITY"
sign_sparkle_framework "$APP/Contents/Frameworks/Sparkle.framework" "$IDENTITY"
# The hardened runtime keeps other processes from injecting code into
# MenuMeters, which may hold the Accessibility permission.
codesign --force --options runtime --timestamp \
    ${ENTITLEMENTS[@]+"${ENTITLEMENTS[@]}"} \
    --sign "$IDENTITY" "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
require_hardened_runtime "$APP"

say "BUILD OK"
file "$APP/Contents/MacOS/MenuMeters"
echo "Output: $APP"
