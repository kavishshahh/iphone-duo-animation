#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Still must be built on a Mac with macOS 14+ and Xcode Command Line Tools."
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Install Xcode Command Line Tools first: xcode-select --install"
  exit 1
fi
echo "Running geometry and gesture tests..."
swift test
echo "Building Still..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$(pwd)/build/Still.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Still" "$APP/Contents/MacOS/Still"
cp "Sources/Still/Resources/Info.plist" "$APP/Contents/Info.plist"
ditto "$BIN_DIR/Still_Still.bundle" "$APP/Contents/Resources/Still_Still.bundle"
codesign --force --deep --sign - "$APP"
echo ""
echo "Built: $APP"
echo "This is a locally signed prototype, not a notarized public release."
echo "Open it with: open \"$APP\""
