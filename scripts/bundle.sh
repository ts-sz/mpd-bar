#!/bin/bash
# Build MPDBar.app from source.
#   scripts/bundle.sh             build into build/MPDBar.app
#   scripts/bundle.sh --install   also copy to ~/Applications and launch it
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MPDBar
swift build -c release --product mpdbar-probe
BIN="$(swift build -c release --show-bin-path)"

APP="build/MPDBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/MPDBar" "$APP/Contents/MacOS/MPDBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MPDBar 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/MPDBar.app"
  cp -R "$APP" "$HOME/Applications/MPDBar.app"
  open "$HOME/Applications/MPDBar.app"
  echo "Installed to ~/Applications/MPDBar.app"
fi
