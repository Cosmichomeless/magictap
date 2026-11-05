#!/bin/bash
# Builds MagicTap.app (release) into ./build and ad-hoc signs it.
#
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  also copy to ~/Applications
#
# Optional: SIGN_IDENTITY="My Cert" scripts/build-app.sh
# A stable signing identity keeps the Accessibility permission across rebuilds;
# with the default ad-hoc signature macOS asks for it again after every build.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/MagicTap.app"
IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MagicTap" "$APP/Contents/MacOS/MagicTap"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: ${IDENTITY/#-/ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/MagicTap.app"
    cp -R "$APP" "$HOME/Applications/MagicTap.app"
    echo "Installed to ~/Applications/MagicTap.app"
fi
