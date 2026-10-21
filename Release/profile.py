#!/usr/bin/env python3
# The team's Developer ID provisioning profile for Safience, which a Mac build
# with iCloud sync is signed with (Release/mac.sh, ICLOUD=1): made in the
# team's account through the App Store Connect API when there is none yet,
# then downloaded and installed where Xcode looks for profiles.
#
#   Release/profile.py
#
# It signs in as Release/mac.sh does: with the App Store Connect API key that
# Safience's notary file names (SAFIENCE_NOTARY_ENV, by default
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
NAME = os.environ.get("PROFILE", "Safience Developer ID")


def sign_in():
    """The API key's path, id and issuer: from the environment, or Safience's notary file."""
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
    # Xcode 16 and later read profiles from here.
    folder = os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, profile["attributes"]["uuid"] + ".provisionprofile")
    with open(path, "wb") as file:
        file.write(content)
    # What the profile grants, read from its signed plist, for a look before signing with it.
    decoded = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True, check=True).stdout
    entitlements = plistlib.loads(decoded)["Entitlements"]
    print(f"Installed “{NAME}” ({profile['attributes']['uuid']}), until {profile['attributes']['expirationDate'][:10]}:")
    for key in sorted(entitlements):
        print(f"  {key}: {entitlements[key]}")


if __name__ == "__main__":
    main()
