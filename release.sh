#!/bin/zsh
# Builds DeepClean.app and zips it for a GitHub release.
#   ./release.sh                 -> dist/DeepClean-<version>.zip
#   SIGN_IDENTITY="..." ./release.sh
# Then: gh release create v<version> dist/DeepClean-<version>.zip --title "DeepClean <version>" --notes-file RELEASE_NOTES.md
set -e
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' DeepClean.app/Contents/Info.plist)
mkdir -p dist
ZIP="dist/DeepClean-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent DeepClean.app "$ZIP"
echo "Wrote $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
