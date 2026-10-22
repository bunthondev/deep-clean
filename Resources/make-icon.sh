#!/bin/zsh
# Generates Resources/AppIcon.icns from make-icon.swift using sips + iconutil (no Xcode needed).
set -e
cd "$(dirname "$0")"
TMP=$(mktemp -d)
swift make-icon.swift "$TMP/icon_1024.png"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$TMP/icon_1024.png" --out "$SET/icon_${sz}x${sz}.png" >/dev/null
  dbl=$((sz*2))
  sips -z $dbl $dbl "$TMP/icon_1024.png" --out "$SET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o AppIcon.icns
cp "$TMP/icon_1024.png" icon-preview.png
rm -rf "$TMP"
echo "wrote Resources/AppIcon.icns"
