#!/usr/bin/env python3
# The team's Developer ID provisioning profile for eGlu, which a Mac build
# with iCloud sync is signed with (Release/mac.sh, ICLOUD=1): made in the
# team's account through the App Store Connect API when there is none yet,
# then downloaded and installed where Xcode looks for profiles.
#
#   Release/profile.py
#   PASSKEYS=1 Release/profile.py
#
# PASSKEYS=1 makes a profile of its own, "Safience Developer ID Passkeys",
# for a build with Apple's passkey entitlement for browsers (Release/mac.sh,
# PASSKEYS=1). Apple grants that entitlement on request, and the capability
# is then turned on for the app's identifier on developer.apple.com, by hand:
# a profile carries what the identifier has when the profile is made. One
# made without it is no use, as an app signed with the entitlement and that
# profile won't open, so it is deleted again at once and nothing is
# installed. The profile ICLOUD=1 builds use is left as it is.
#
# It signs in as Release/mac.sh does: with the App Store Connect API key that
# eGlu's notary file names (SAFIENCE_NOTARY_ENV, by default
# ~/.appstoreconnect/safience-notary.env), unless ASC_KEY_PATH, ASC_KEY_ID
# and ASC_ISSUER_ID are set already.
#
# A Developer ID profile names the app's identifier and the Developer ID
# certificate, and no devices: making one changes nothing else in the
# account. The identifier must have iCloud and push turned on, as the
# iPhone and iPad app's has. Needs PyJWT (pip install pyjwt cryptography).
import base64, json, os, plistlib, subprocess, sys, time, urllib.error, urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
PASSKEYS = bool(os.environ.get("PASSKEYS"))
PASSKEY_KEY = "com.apple.developer.web-browser.public-key-credential"
NAME = os.environ.get("PROFILE", "Safience Developer ID Passkeys" if PASSKEYS else "Safience Developer ID")


def sign_in():
    """The API key's path, id and issuer: from the environment, or eGlu's notary file."""
    names = ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID")
    found = {name: os.environ.get(name) for name in names}
    path = os.environ.get("SAFIENCE_NOTARY_ENV", os.path.expanduser("~/.appstoreconnect/safience-notary.env"))
    if not all(found.values()) and os.path.exists(path):
        for line in open(path):
            key, _, value = line.strip().partition("=")
            if key in names and not found[key]:
                found[key] = os.path.expanduser(os.path.expandvars(value.strip().strip('"')))
    if not all(found.values()):
        sys.exit(f"Set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, in {path} or the environment.")
    return found["ASC_KEY_PATH"], found["ASC_KEY_ID"], found["ASC_ISSUER_ID"]


KEY, KID, ISS = sign_in()
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def call(method, path, body=None):
    now = int(time.time())
    token = jwt.encode({"iss": ISS, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                       open(KEY).read(), algorithm="ES256", headers={"kid": KID, "typ": "JWT"})
    request = urllib.request.Request(API + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None)
    request.add_header("Authorization", "Bearer " + token)
    if body is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            text = response.read()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        sys.exit(f"{method} {path}: {error.code} {error.read()[:800].decode(errors='replace')}")


def bundle_identifier():
    for line in open(os.path.join(HERE, "Config", "Signing.xcconfig")):
        if line.startswith("PRODUCT_BUNDLE_IDENTIFIER"):
            return line.split("=", 1)[1].strip()
    sys.exit("No PRODUCT_BUNDLE_IDENTIFIER in Config/Signing.xcconfig")


def main():
    identifier = bundle_identifier()
    bundles = call("GET", f"/v1/bundleIds?filter[identifier]={identifier}")["data"]
    bundle = next((b for b in bundles if b["attributes"]["identifier"] == identifier), None)
    if bundle is None or bundle["attributes"]["platform"] not in ("UNIVERSAL", "MAC_OS"):
        sys.exit(f"{identifier} isn't registered for the Mac in the team's account.")

    profiles = call("GET", f"/v1/profiles?filter[name]={urllib.request.quote(NAME)}&filter[profileType]=MAC_APP_DIRECT")["data"]
    profile = next((p for p in profiles if p["attributes"]["profileState"] == "ACTIVE"), None)
    made = profile is None
    if profile is None:
        certificates = call("GET", "/v1/certificates?filter[certificateType]=DEVELOPER_ID_APPLICATION")["data"]
        if not certificates:
            sys.exit("No Developer ID Application certificate in the team's account.")
        print(f"Making the Developer ID profile “{NAME}” for {identifier}…")
        profile = call("POST", "/v1/profiles", {"data": {
            "type": "profiles",
            "attributes": {"name": NAME, "profileType": "MAC_APP_DIRECT"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": c["id"]} for c in certificates]},
            },
        }})["data"]

    content = base64.b64decode(profile["attributes"]["profileContent"])
    # What the profile grants, read from its signed plist, for a look before signing with it.
    decoded = subprocess.run(["security", "cms", "-D"], input=content, capture_output=True, check=True).stdout
    entitlements = plistlib.loads(decoded)["Entitlements"]
    if PASSKEYS and entitlements.get(PASSKEY_KEY) is not True:
        if made:
            call("DELETE", f"/v1/profiles/{profile['id']}")
            sys.exit(f"The identifier {identifier} doesn't have the passkey capability yet, so the profile made "
                     f"would not grant {PASSKEY_KEY}; it was deleted again. Once Apple has granted it, turn it on "
                     f"for {identifier} on developer.apple.com (Identifiers) and run this again.")
        sys.exit(f"“{NAME}” doesn't grant {PASSKEY_KEY}: it was made before the capability was on. Delete it on "
                 f"developer.apple.com (Profiles) and run this again.")
    # Xcode 16 and later read profiles from here.
    folder = os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, profile["attributes"]["uuid"] + ".provisionprofile")
    with open(path, "wb") as file:
        file.write(content)
    print(f"Installed “{NAME}” ({profile['attributes']['uuid']}), until {profile['attributes']['expirationDate'][:10]}:")
    for key in sorted(entitlements):
        print(f"  {key}: {entitlements[key]}")


if __name__ == "__main__":
    main()
