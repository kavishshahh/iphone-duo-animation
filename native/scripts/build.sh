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
# XCTest ships inside Xcode.app, not the Command Line Tools. Run the geometry tests when
# we can, skip them (with a note) when we can't, and never let that block the app build.
if [ "${STILL_SKIP_TESTS:-0}" = "1" ]; then
  echo "Skipping tests (STILL_SKIP_TESTS=1)."
elif xcrun --find xctest >/dev/null 2>&1; then
  echo "Running geometry and gesture tests..."
  swift test
else
  echo "Skipping tests: XCTest needs full Xcode, and only the Command Line Tools are installed."
  echo "The app builds fine without it. CI runs the tests on every push."
fi
echo "Building Still..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$(pwd)/build/Still.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Still" "$APP/Contents/MacOS/Still"
cp "Sources/Still/Resources/Info.plist" "$APP/Contents/Info.plist"
ditto "$BIN_DIR/Still_Still.bundle" "$APP/Contents/Resources/Still_Still.bundle"
# Ad-hoc signing (`--sign -`) makes the designated requirement a bare cdhash, so EVERY rebuild is
# a different app to macOS and the Screen Recording grant is silently dropped — the app then
# re-prompts while System Settings still shows a stale, enabled row for it. Signing with a real
# development certificate binds the requirement to bundle ID + certificate instead, which survives
# rebuilds, so the permission is granted once. Falls back to ad-hoc when no certificate exists.
# The identity must be the SAME on every rebuild. TCC binds Screen Recording to the designated
# requirement, which names the signing certificate: sign with a different one and macOS sees a
# different app and silently drops the permission. Picking "the first identity the keychain lists"
# is not stable — the order changes, and a machine with several Apple Development certificates
# will quietly alternate between them, breaking the grant on a rebuild that changed nothing.
#
# So the choice is made once and remembered. Delete native/.signing-identity to choose again.
IDENTITY_FILE="$(pwd)/.signing-identity"
if [ -n "${STILL_SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$STILL_SIGN_IDENTITY"
elif [ -f "$IDENTITY_FILE" ]; then
  SIGN_IDENTITY="$(cat "$IDENTITY_FILE")"
else
  # Store the certificate's SHA-1, not its name: several Apple Development certificates can share
  # one display name, and codesign refuses an ambiguous name outright. `sort` on the hash keeps a
  # first run reproducible instead of dependent on keychain ordering.
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E 'Apple Development|Developer ID Application' \
    | awk '{print $2}' | sort | head -1)"
  [ -n "$SIGN_IDENTITY" ] && printf '%s' "$SIGN_IDENTITY" > "$IDENTITY_FILE"
fi
if [ -n "$SIGN_IDENTITY" ]; then
  echo "Signing as: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime "$APP"
else
  echo "No development certificate found; signing ad hoc."
  echo "macOS will forget the Screen Recording permission on every rebuild."
  codesign --force --deep --sign - "$APP"
fi
echo ""
echo "Built: $APP"
echo "This is a locally signed prototype, not a notarized public release."
echo "Open it with: open \"$APP\""
