#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/build/Progress Notifier.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/ProgressNotifier" "$APP/Contents/MacOS/ProgressNotifier"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
