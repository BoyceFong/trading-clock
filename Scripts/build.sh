#!/bin/bash
# Build TradingClock.app from the Swift package.
#
# Usage:
#   Scripts/build.sh                 # build dist/TradingClock.app (release)
#   Scripts/build.sh --debug         # debug build
#   Scripts/build.sh --open          # build + launch the .app
#   Scripts/build.sh --install       # build + install to /Applications (fallback ~/Applications) + launch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# xcode-select points at Command Line Tools; Liquid Glass needs the Xcode 26 SDK.
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

CONFIG="release"
OPEN=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --debug)  CONFIG="debug" ;;
    --open)   OPEN=1 ;;
    --install) INSTALL=1 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

cd "$ROOT_DIR"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/TradingClock.app"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/TradingClock" "$APP_DIR/Contents/MacOS/TradingClock"
cp "$ROOT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"

# SPM resource bundle (Localizable.strings lproj folders).
for bundle in "$BIN_PATH"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

echo "==> Ad-hoc codesign"
codesign --force --sign - "$APP_DIR"

if [ "$INSTALL" = "1" ]; then
  pkill -x TradingClock 2>/dev/null || true
  TARGET="/Applications"
  if [ ! -w "$TARGET" ]; then TARGET="$HOME/Applications"; fi
  echo "==> Installing to $TARGET"
  rm -rf "$TARGET/TradingClock.app"
  cp -R "$APP_DIR" "$TARGET/TradingClock.app"
  xattr -cr "$TARGET/TradingClock.app"
  open "$TARGET/TradingClock.app"
elif [ "$OPEN" = "1" ]; then
  open "$APP_DIR"
fi

echo "==> Done: $APP_DIR"
