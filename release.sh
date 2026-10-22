#!/bin/zsh
# Builds DeepClean.app and zips it for a GitHub release.
#   ./release.sh                 -> dist/DeepClean-<version>.zip
#   SIGN_IDENTITY="..." ./release.sh
#   ./release.sh --bump-cask     -> after `gh release create`, updates the Homebrew tap to this version
#
# Full flow: bump versions in Resources/Info.plist, ./release.sh, commit, git tag -a vX.Y.Z, push with tags,
#   gh release create vX.Y.Z dist/DeepClean-X.Y.Z.zip dist/DeepClean-X.Y.Z.zip.sig --title "DeepClean X.Y.Z" --notes-file RELEASE_NOTES.md
#   ./release.sh --bump-cask
#
# Every zip is signed with the Ed25519 key at $DEEPCLEAN_UPDATE_KEY (default ~/.config/deepclean/update-signing.pem).
# The app's in-place updater refuses a zip whose .sig does not verify against the public key in Updater.swift.
# Never commit the private key. To rotate: openssl genpkey -algorithm ed25519 -out <pem>, then paste
#   openssl pkey -in <pem> -pubout -outform DER | tail -c 32 | base64   into Installer.updatePublicKey.
set -e
cd "$(dirname "$0")"

if [[ "$1" == "--bump-cask" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
  URL="https://github.com/bunthondev/deep-clean/releases/download/v$VERSION/DeepClean-$VERSION.zip"
  echo "Fetching $URL"
  SHA=$(curl -fsSL "$URL" | shasum -a 256 | cut -d' ' -f1)
  TAP=$(brew --repository bunthondev/tap 2>/dev/null || true)
  [[ -d "$TAP" ]] || { echo "Tap not installed. Run: brew tap bunthondev/tap"; exit 1; }
  CASK="$TAP/Casks/deepclean.rb"
  sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
  (cd "$TAP" && git add Casks/deepclean.rb && git commit -qm "deepclean $VERSION" && git push -q origin HEAD)
  echo "Cask updated to $VERSION ($SHA)"
  brew audit --cask --online bunthondev/tap/deepclean && echo "Audit passed"
  exit 0
fi

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' DeepClean.app/Contents/Info.plist)
mkdir -p dist
ZIP="dist/DeepClean-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent DeepClean.app "$ZIP"
echo "Wrote $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

KEY="${DEEPCLEAN_UPDATE_KEY:-$HOME/.config/deepclean/update-signing.pem}"
[[ -f "$KEY" ]] || { echo "Update signing key not found at $KEY (see comments at top of this script)"; exit 1; }
openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$ZIP" -out "$ZIP.sig"
PUB=$(openssl pkey -in "$KEY" -pubout -outform DER | tail -c 32 | base64)
grep -q "\"$PUB\"" Sources/DeepClean/Updater.swift || { echo "Public key in Updater.swift does not match $KEY"; exit 1; }
echo "Signed: $ZIP.sig"
