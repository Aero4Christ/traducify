#!/bin/bash
# Package dist/Traducify.app into a drag-to-Applications dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0-beta}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -d dist/Traducify.app ] || ./scripts/build-app.sh

cp -R dist/Traducify.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "dist/Traducify-$VERSION.dmg"
hdiutil create -volname "Traducify" -srcfolder "$STAGE" -ov -format UDZO \
  "dist/Traducify-$VERSION.dmg"

echo "Built dist/Traducify-$VERSION.dmg"
