#!/bin/bash
# Builds InkBar.app into ./build.
#
# Signing: uses SIGN_IDENTITY if set, otherwise the first "Developer ID Application"
# certificate in your keychain, otherwise an ad-hoc signature. While anything is hidden,
# macOS 27 only draws status items of notarized apps, InkBar's own ensō included.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
    SIGN_IDENTITY=${SIGN_IDENTITY:--}
fi

# Notarization needs a secure timestamp; RELEASE=1 asks Apple's timestamp server for one.
TIMESTAMP=--timestamp=none
[[ "${RELEASE:-}" == 1 ]] && TIMESTAMP=--timestamp

swift build -c release --product InkBar

APP=build/InkBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp .build/release/InkBar "$APP/Contents/MacOS/InkBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
.build/release/InkBar --render-icon "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime "$TIMESTAMP" --entitlements Resources/InkBar.entitlements --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP (signed with: $SIGN_IDENTITY)"
