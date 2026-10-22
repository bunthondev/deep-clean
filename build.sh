#!/bin/zsh
# Builds DeepClean.app next to this script.
#   ./build.sh            build
#   ./build.sh --run      build and open
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build.sh
#   SIGN_IDENTITY="DeepClean Dev" ./build.sh      # a self-signed cert from Keychain Access works too
# Without SIGN_IDENTITY the app is ad-hoc signed, which changes every build, so macOS forgets
# Full Disk Access grants between rebuilds. Any stable certificate fixes that.
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -vE '^\s*$' | tail -5
APP=DeepClean.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DeepClean "$APP/Contents/MacOS/DeepClean"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
  echo "Signed with: $SIGN_IDENTITY"
else
  codesign --force --sign - "$APP" 2>/dev/null || true
  echo "Ad-hoc signed (set SIGN_IDENTITY for a stable signature)"
fi
echo "Built $PWD/$APP ($(du -sh "$APP" | cut -f1))"
[[ "$1" == "--run" ]] && open "$APP"
exit 0
