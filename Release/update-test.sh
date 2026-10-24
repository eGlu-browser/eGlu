#!/bin/zsh
# A test of eGlu for Mac updating itself, from the shell (Mac/Sources/Updates.swift):
# an older and a newer eGlu Mac Direct, built under a bundle identifier of
# their own (so nothing of the real app's data is touched), the newer packed as
# a disk image, signed with Sparkle's key and announced in an appcast served on
# this Mac; the older opened with -updateTest, which checks at once and installs
# what it finds without asking. It passes when the copy that was opened is the
# newer build, still signed with the same Developer ID.
#
#   Release/update-test.sh
#
# Needs the Developer ID Application certificate and Sparkle's key (account
# "safience"), as Release/mac.sh release does. Nothing is notarised, published
# or sent anywhere; the test app and everything it kept are removed after.
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_ID="net.taehee.safience.updatetest"
# A port nothing else here is using, chosen now: the builds name it in their feed's address.
PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
WORK="build/update-test"
# Kept between runs, so a second run builds only what changed.
BUILDS="build/update-test-builds"
SPARKLE="build/sparkle-2.10.0"
IDENTITY_LINE="$(security find-identity -v -p codesigning | grep '"Developer ID Application:' | head -1)"
TEAM="$(echo "$IDENTITY_LINE" | sed -E 's/.*\(([A-Z0-9]+)\)".*/\1/')"
[[ -x "$SPARKLE/bin/sign_update" ]] || { echo "Sparkle's tools aren't in $SPARKLE: Release/mac.sh release fetches them." >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/feed"

build() {
  local version="$1" number="$2"
  echo "Building $version ($number)…"
  xcodebuild build -quiet -project eGlu.xcodeproj -scheme "eGlu Mac Direct" -configuration Debug \
    -destination "generic/platform=macOS" -derivedDataPath "$BUILDS/dd-$number" -packageAuthorizationProvider netrc \
    PRODUCT_BUNDLE_IDENTIFIER="$TEST_ID" MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$number" \
    SPARKLE_FEED_URL="http://127.0.0.1:$PORT/appcast.xml" \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application" DEVELOPMENT_TEAM="$TEAM" \
    MAC_ENTITLEMENTS=Config/eGluMacDirect.entitlements >"$WORK/build-$number.log" 2>&1 \
    || { grep -E 'error' "$WORK/build-$number.log" | head -20 >&2; echo "Building $version failed: $WORK/build-$number.log" >&2; exit 1; }
  echo "$BUILDS/dd-$number/Build/Products/Debug/eGlu.app"
}

OLD="$(build 1.0.2 31 | tail -1)"
NEW="$(build 1.0.3 32 | tail -1)"

# The newer as people would get it: a disk image, signed for Sparkle.
DMG="$WORK/feed/eGlu-1.0.3.dmg"
mkdir -p "$WORK/stage"
cp -R "$NEW" "$WORK/stage/"
hdiutil create -volname eGlu -srcfolder "$WORK/stage" -ov -format UDZO -quiet "$DMG"
SIGNED="$("$SPARKLE/bin/sign_update" --account safience "$DMG")"
SIGNATURE="$(echo "$SIGNED" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')"
python3 Release/appcast.py --out "$WORK/feed/appcast.xml" --version 1.0.3 --build 32 \
  --url "http://127.0.0.1:$PORT/eGlu-1.0.3.dmg" --length "$(stat -f %z "$DMG")" --signature "$SIGNATURE"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/feed" >"$WORK/server.log" 2>&1 &
SERVER=$!
APP="$WORK/installed/eGlu.app"
cleanup() {
  kill "$SERVER" 2>/dev/null || true
  pkill -f "$WORK/installed/eGlu.app" 2>/dev/null || true
  rm -rf "$HOME/Library/Containers/$TEST_ID"
  defaults delete "$TEST_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The feed answers before the app asks it.
for _ in {1..20}; do
  curl -fsS "http://127.0.0.1:$PORT/appcast.xml" -o /dev/null 2>/dev/null && break
  sleep 0.5
done
curl -fsS "http://127.0.0.1:$PORT/appcast.xml" -o /dev/null || { echo "The feed on port $PORT doesn't answer:" >&2; cat "$WORK/server.log" >&2; exit 1; }

mkdir -p "$WORK/installed"
cp -R "$OLD" "$APP"
echo "Opening 1.0.2 (31) to update itself…"
open -n -g "$APP" --args -updateTest YES

# Up to two minutes for it to find, fetch, check and install the update.
for _ in {1..60}; do
  sleep 2
  NOW="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$NOW" == "32" ]] && break
done
echo "Requests the feed served:"
grep -E '"GET ' "$WORK/server.log" | sed -E 's/.*"(GET [^"]+)".*/  \1/' || true
if [[ "$NOW" != "32" ]]; then
  echo "FAILED: the copy is still build $NOW." >&2
  log show --last 3m --style compact --predicate 'process CONTAINS "eGlu" OR process CONTAINS "Autoupdate" OR process CONTAINS "Installer"' 2>/dev/null \
    | grep -iE 'sparkle|update|install' | tail -20 >&2 || true
  exit 1
fi
codesign --verify --deep --strict "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E 'Authority=Developer ID Application|TeamIdentifier'
echo "PASSED: the copy opened as 1.0.2 (31) is now $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist") (32), signed as before."
