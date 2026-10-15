#!/bin/bash
# Build MPDBar.app and mpdbar-probe from source.
#   scripts/bundle.sh                  build into build/ (host architecture)
#   scripts/bundle.sh --install        also copy the app to ~/Applications and launch it
#   UNIVERSAL=1 scripts/bundle.sh      universal binaries (arm64 + x86_64), as releases do
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
# macOS ships bash 3.2, where an empty array under `set -u` is an error: expand it guarded.
swiftb() { swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} "$@"; }

swiftb --product MPDBar
swiftb --product mpdbar-probe
BIN="$(swiftb --show-bin-path)"

APP="build/MPDBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/MPDBar" "$APP/Contents/MacOS/MPDBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/mpdbar-probe" build/mpdbar-probe
codesign --force -s - "$APP" >/dev/null
codesign --force -s - build/mpdbar-probe >/dev/null
echo "Built $APP and build/mpdbar-probe ($(lipo -archs "$APP/Contents/MacOS/MPDBar"))"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MPDBar 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/MPDBar.app"
  cp -R "$APP" "$HOME/Applications/MPDBar.app"
  open "$HOME/Applications/MPDBar.app"
  echo "Installed to ~/Applications/MPDBar.app"
fi
