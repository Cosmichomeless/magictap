#!/bin/bash
# Builds MagicTap.app and packs it into build/MagicTap-<version>.dmg
# (app + a shortcut to /Applications, ready to drag and drop).
#
#   scripts/make-dmg.sh
#
# The app is ad-hoc signed and not notarized (see README, "Install").
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/MagicTap-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R build/MagicTap.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "MagicTap $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
