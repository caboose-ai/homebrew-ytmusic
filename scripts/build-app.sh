#!/bin/bash
# Builds YTMusic.app into <outdir> using only the Command Line Tools (no full Xcode).
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: scripts/build-app.sh <outdir>" >&2
  exit 2
fi

mkdir -p "$1"
OUTDIR="$(cd "$1" && pwd)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --disable-sandbox: SwiftPM's own sandbox fails inside Homebrew's sandbox.
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"

APP="$OUTDIR/YTMusic.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/YTMusic" "$APP/Contents/MacOS/YTMusic"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. Locally built binaries carry no quarantine flag, so Gatekeeper never checks them.
codesign --force --sign - "$APP"

echo "Built $APP (version $VERSION)"
