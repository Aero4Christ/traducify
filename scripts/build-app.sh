#!/bin/bash
# Build Traducify.app from the SwiftPM package. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Traducify"
APP="dist/Traducify.app"

WHISPER_FRAMEWORK=".build/artifacts/traducify/whisper/whisper.xcframework/macos-arm64_x86_64/whisper.framework"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Traducify"
cp Bundle/Info.plist "$APP/Contents/Info.plist"
cp -R "$WHISPER_FRAMEWORK" "$APP/Contents/Frameworks/"
if [ -f Bundle/AppIcon.icns ]; then
  cp Bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# Silero VAD model (small; bundled so VAD works offline with no download)
if [ -f Bundle/ggml-silero-v5.1.2.bin ]; then
  cp Bundle/ggml-silero-v5.1.2.bin "$APP/Contents/Resources/ggml-silero-v5.1.2.bin"
fi

# the binary references @rpath/whisper.framework; point rpath at the bundle
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Traducify" 2>/dev/null || true

# Sign with a stable self-signed identity so TCC grants (Screen & System Audio
# Recording) persist across rebuilds: ad-hoc gives a new cdhash every build, which
# is what forces a re-grant each time. Falls back to ad-hoc where the identity is
# not installed (other machines, CI). Create it once with scripts/make-signing-cert.sh.
SIGN_ID="${SIGN_ID:-Traducify Self-Signed}"
security find-certificate -c "$SIGN_ID" >/dev/null 2>&1 || SIGN_ID="-"
# Clear extended attributes right before EACH codesign: in an iCloud-synced
# folder the File Provider re-adds com.apple.FinderInfo, which trips codesign's
# "detritus not allowed" check if cleared only once up front.
xattr -cr "$APP/Contents/Frameworks/whisper.framework"
codesign --force --sign "$SIGN_ID" "$APP/Contents/Frameworks/whisper.framework"
xattr -cr "$APP"
codesign --force --sign "$SIGN_ID" "$APP"

echo "Built $APP (signed: $SIGN_ID)"
