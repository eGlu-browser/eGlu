#!/bin/zsh
# Safience for Mac as a disk image to download: signed with Developer ID,
# with the hardened runtime, notarised by Apple and stapled, so it opens on
# any Mac without Gatekeeper's warning. (The App Store build is the other
# way to the Mac app; this one is for outside it.)
#
#   Release/mac.sh             build, sign and pack: build/mac/Safience-<version>.dmg
#   Release/mac.sh notarize    the same, then the app and the disk image notarised and stapled
#
# Needs:
#   - the "Developer ID Application" certificate, with its private key, in the
#     keychain; the team is read from it (or DEVELOPMENT_TEAM)
#   - to notarise: Safience's notary sign-in, in a file named for the app and
#     kept out of the repository, as Harper's is (SAFIENCE_NOTARY_ENV, by
#     default ~/.appstoreconnect/safience-notary.env), which sets
#     ASC_KEY_PATH to an App Store Connect API key's .p8, ASC_KEY_ID and
#     ASC_ISSUER_ID; or a notarytool keychain profile (NOTARY_PROFILE, made
#     once with `xcrun notarytool store-credentials safience`). Notarising
#     sends the app to Apple, who look it over and keep a ticket.
#   - ICLOUD=1 for a build with iCloud sync, signed with its production
#     entitlements (Config/SafienceMacRelease.entitlements) and the team's
#     Developer ID provisioning profile, which Release/profile.py makes in the
#     team's account and installs, once (PROFILE names another). A Developer
#     ID profile names no devices: nothing else in the account changes.
#     Without ICLOUD the build has everything but sync, which Settings ›
#     iCloud then says it isn't signed for.
#
# The disk image's window is laid out by Release/dmg.py through dmgbuild,
# installed into build/ the first time (Python 3), as the Mac's Search lays
# out its own (its Installer/dmg.py); without it, a plain disk image.
set -euo pipefail
cd "$(dirname "$0")/.."

STEP="${1:-pack}"
OUT="build/mac"
NAME="Safience"

# The notary service's sign-in, from the app's own file, unless already set.
NOTARY_ENV="${SAFIENCE_NOTARY_ENV:-$HOME/.appstoreconnect/safience-notary.env}"
if [[ -z "${ASC_KEY_PATH:-}${NOTARY_PROFILE:-}" && -f "$NOTARY_ENV" ]]; then
  source "$NOTARY_ENV"
fi

# The Developer ID identity, and its team: "Developer ID Application: Name (TEAM)".
IDENTITY_LINE="$(security find-identity -v -p codesigning | grep '"Developer ID Application:' | head -1 || true)"
if [[ -z "$IDENTITY_LINE" ]]; then
  echo "No Developer ID Application certificate in the keychain: Xcode › Settings › Accounts › Manage Certificates." >&2
  exit 1
fi
IDENTITY="$(echo "$IDENTITY_LINE" | awk '{print $2}')"
TEAM="${DEVELOPMENT_TEAM:-$(echo "$IDENTITY_LINE" | sed -E 's/.*\(([A-Z0-9]+)\)".*/\1/')}"

# How notarytool signs in: a keychain profile, or the API key.
NOTARY=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  NOTARY=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
fi
if [[ "$STEP" == "notarize" && ${#NOTARY} -eq 0 ]]; then
  echo "To notarise: $NOTARY_ENV with ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, or NOTARY_PROFILE." >&2
  exit 1
fi

# Signed by hand with Developer ID; with iCloud, with the provisioning
# profile iCloud's entitlements need too.
SIGNING=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application" "DEVELOPMENT_TEAM=$TEAM")
PROFILES=""
if [[ -n "${ICLOUD:-}" ]]; then
  ENTITLEMENTS="Config/SafienceMacRelease.entitlements"
  PROFILE="${PROFILE:-Safience Developer ID}"
  SIGNING+=("PROVISIONING_PROFILE_SPECIFIER=$PROFILE")
  BUNDLE="$(grep -E '^PRODUCT_BUNDLE_IDENTIFIER' Config/Signing.xcconfig | sed -E 's/.*= *//')"
  PROFILES="<key>provisioningProfiles</key><dict><key>$BUNDLE</key><string>$PROFILE</string></dict>"
else
  ENTITLEMENTS="Config/SafienceMacLocal.entitlements"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "Archiving $NAME (Release, signed with Developer ID, $([[ -n "${ICLOUD:-}" ]] && echo "with iCloud" || echo "without iCloud"))…"
xcodebuild archive -quiet \
  -project Safience.xcodeproj -scheme "Safience Mac" -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$OUT/$NAME.xcarchive" \
  "MAC_ENTITLEMENTS=$ENTITLEMENTS" ENABLE_HARDENED_RUNTIME=YES "${SIGNING[@]}"

# Exported for Developer ID: signed again with a secure timestamp, which notarisation asks for.
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  $PROFILES
</dict>
</plist>
PLIST
echo "Exporting for Developer ID…"
xcodebuild -exportArchive -quiet -archivePath "$OUT/$NAME.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"
APP="$OUT/export/$NAME.app"
codesign --verify --deep --strict "$APP"
SIGNATURE="$(codesign --display --verbose=4 "$APP" 2>&1)"
[[ "$SIGNATURE" == *"(runtime)"* && "$SIGNATURE" == *"Timestamp="* ]] \
  || { echo "The app isn't signed with the hardened runtime and a timestamp, which notarisation asks for." >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$OUT/$NAME-$VERSION.dmg"

# Sent to Apple and waited for; the ticket stapled to `file` on acceptance,
# and Apple's log printed on anything else.
notarize() {
  local file="$1" result id status
  echo "Notarising $(basename "$file")…"
  result="$(xcrun notarytool submit "$file" "${NOTARY[@]}" --wait --output-format json)"
  id="$(echo "$result" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("id", ""))')"
  status="$(echo "$result" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("status", ""))')"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarisation: $status" >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${NOTARY[@]}" >&2
    exit 1
  fi
}

# The app first, so that it opens without asking even taken out of the disk
# image and opened with no network to check it by.
if [[ "$STEP" == "notarize" ]]; then
  ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"
  notarize "$OUT/$NAME.zip"
  xcrun stapler staple "$APP"
  rm "$OUT/$NAME.zip"
fi

echo "Packing $(basename "$DMG")…"
DMGBUILD="build/dmgbuild/bin/dmgbuild"
if [[ ! -x "$DMGBUILD" ]]; then
  { python3 -m venv build/dmgbuild && build/dmgbuild/bin/pip install --quiet "dmgbuild==1.6.7"; } >/dev/null 2>&1 || true
fi
if [[ -x "$DMGBUILD" ]]; then
  "$DMGBUILD" -s Release/dmg.py -D "app=$APP" "$NAME" "$DMG" >/dev/null
else
  echo "note: no dmgbuild, a plain disk image without its window laid out" >&2
  STAGE="$OUT/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
  rm -rf "$STAGE"
fi
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ "$STEP" == "notarize" ]]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  # What a Mac that downloads it decides: the disk image, and the app in it.
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  spctl --assess --type execute --verbose "$APP"
fi

echo "Done: $DMG ($VERSION, build $BUILD)$([[ "$STEP" == "notarize" ]] && echo ", notarised and stapled")"
