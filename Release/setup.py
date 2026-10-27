#!/usr/bin/env python3
"""Restore release credentials at session runtime, never during a snapshot build."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SERVICE = "net.taehee.safience.release"
SPARKLE_VERSION = "2.10.0"
SECRET_NAMES = (
    "ASC_PRIVATE_KEY", "ASC_KEY_ID", "ASC_ISSUER_ID",
    "IOS_DISTRIBUTION_P12_B64", "IOS_DISTRIBUTION_P12_PASSWORD",
    "MAC_DEVELOPER_ID_P12_B64", "MAC_DEVELOPER_ID_P12_PASSWORD", "SPARKLE_PRIVATE_KEY",
)


def run(args, *, data=None, check=True):
    result = subprocess.run(list(map(str, args)), input=data, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} {args[1]} failed (exit {result.returncode}); output withheld to protect credentials")
    return result


def security_command(args):
    # Send passwords through stdin, not process arguments or plaintext files.
    if any("\n" in str(arg) or "\r" in str(arg) or "\0" in str(arg) for arg in args):
        raise ValueError("Keychain command arguments cannot contain line breaks or NUL")
    line = " ".join('"' + str(arg).replace('\\', '\\\\').replace('"', '\\"') + '"' for arg in args)
    result = run(["security", "-i"], data=(line + "\n").encode())
    if re.search(rb"(?:SecKeychain|SecItem|error:|Error:|Usage:)", result.stderr):
        raise RuntimeError("Keychain operation failed; output withheld to protect credentials")


def asc(*args):
    return json.loads(run(["asc", *args]).stdout)


def keychain_password(keychain):
    found = run(["security", "find-generic-password", "-s", SERVICE, "-a", str(keychain), "-w"], check=False)
    if found.returncode == 0:
        return found.stdout.decode().rstrip("\n")
    if keychain.exists():
        raise RuntimeError("Release Keychain exists but its unlock password is unavailable; refusing to replace it")
    password = secrets.token_hex(32)
    security_command(["create-keychain", "-p", password, keychain])
    security_command(["add-generic-password", "-s", SERVICE, "-a", keychain,
                      "-T", "/usr/bin/security", "-w", password])
    return password


def signing_identity(prefix, expected_name, team):
    script = '''require 'openssl'; require 'base64'; require 'json'
p = OpenSSL::PKCS12.new(Base64.decode64(ENV.fetch(ARGV[0] + '_P12_B64')), ENV.fetch(ARGV[0] + '_P12_PASSWORD'))
c = p.certificate
abort 'Certificate or private key invalid' unless p.key && c.check_private_key(p.key) && c.not_before <= Time.now && c.not_after > Time.now
puts JSON.generate({name: c.subject.to_a.assoc('CN')[1], team: c.subject.to_a.assoc('OU')[1],
  sha1: OpenSSL::Digest::SHA1.hexdigest(c.to_der).upcase, sha256: OpenSSL::Digest::SHA256.hexdigest(c.to_der)})'''
    identity = json.loads(run(["/usr/bin/ruby", "-e", script, prefix]).stdout)
    if not identity["name"].startswith(expected_name + ":") or identity["team"] != team:
        raise ValueError(f"{prefix} is not a {expected_name} identity for {team}")
    return identity


def sparkle_tools():
    folder = ROOT / "build" / f"sparkle-{SPARKLE_VERSION}"
    folder.mkdir(parents=True, exist_ok=True)
    release = json.loads(run(["gh", "api", f"repos/sparkle-project/Sparkle/releases/tags/{SPARKLE_VERSION}"]).stdout)
    name = f"Sparkle-{SPARKLE_VERSION}.tar.xz"
    asset = next(item for item in release["assets"] if item["name"] == name)
    archive = folder / name
    if not archive.exists():
        run(["gh", "release", "download", SPARKLE_VERSION, "--repo", "sparkle-project/Sparkle",
             "--pattern", name, "--dir", folder])
    if asset.get("digest") != "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest():
        raise ValueError("Sparkle archive does not match GitHub's digest")
    with tarfile.open(archive) as tar:
        tar.extractall(folder, filter="data")
    return folder / "bin"


def check_profile(profile, fingerprint, team, bundle, ios):
    if profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("Provisioning profile has expired")
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("Provisioning profile belongs to another team")
    if fingerprint not in [hashlib.sha256(cert).hexdigest() for cert in profile["DeveloperCertificates"]]:
        raise ValueError("Provisioning profile does not contain the supplied signing certificate")
    entitlements = profile["Entitlements"]
    identifier = entitlements.get("application-identifier", entitlements.get("com.apple.application-identifier"))
    required = {
        "com.apple.developer.icloud-container-identifiers": ["iCloud." + bundle],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-environment": "Production",
        "aps-environment" if ios else "com.apple.developer.aps-environment": "production",
    }
    if identifier != team + "." + bundle or entitlements.get("get-task-allow", False):
        raise ValueError("Profile is not for distribution of this bundle")
    if ios:
        required["com.apple.developer.web-browser"] = True
        required["com.apple.developer.ubiquity-kvstore-identifier"] = team + "." + bundle
    for key, value in required.items():
        actual = entitlements.get(key)
        if isinstance(value, list):
            if not isinstance(actual, list) or not set(value).issubset(actual):
                raise ValueError(f"Profile does not grant required entitlement: {key}")
            continue
        if isinstance(actual, list) and not isinstance(value, list):
            actual = value if value in actual else actual
        if actual != value:
            raise ValueError(f"Profile does not grant required entitlement: {key}")


def install_profile(profile_type, identity, team, bundle, create):
    bundles = asc("bundle-ids", "list", "--identifier", bundle, "--paginate")["data"]
    bundle_id = next(item["id"] for item in bundles if item["attributes"]["identifier"] == bundle)
    certificates = asc("certificates", "list", "--paginate")["data"]
    certificate_id = next(item["id"] for item in certificates if hashlib.sha256(
        base64.b64decode(item["attributes"]["certificateContent"])).hexdigest() == identity["sha256"])
    profiles = asc("profiles", "list", "--profile-type", profile_type, "--profile-state", "ACTIVE",
                   "--include", "bundleId,certificates", "--paginate")["data"]
    matches = [item for item in profiles if item["relationships"]["bundleId"]["data"]["id"] == bundle_id
               and any(cert["id"] == certificate_id for cert in item["relationships"]["certificates"]["data"])]
    if not matches:
        if not create:
            raise RuntimeError(f"No active {profile_type} profile matches this certificate; use --create-ios-profile for iOS only")
        print("Creating an iOS App Store profile with the existing certificate", flush=True)
        matches = [asc("profiles", "create", "--name", "eGlu App Store", "--profile-type", profile_type,
                       "--bundle", bundle_id, "--certificate", certificate_id)["data"]]
    item = max(matches, key=lambda p: p["attributes"]["expirationDate"])
    attributes = item["attributes"]
    content = base64.b64decode(attributes["profileContent"])
    decoded = run(["security", "cms", "-D"], data=content).stdout
    profile = plistlib.loads(decoded)
    check_profile(profile, identity["sha256"], team, bundle, profile_type == "IOS_APP_STORE")
    folder = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    folder.mkdir(parents=True, exist_ok=True)
    suffix = ".mobileprovision" if profile_type == "IOS_APP_STORE" else ".provisionprofile"
    (folder / (profile["UUID"] + suffix)).write_bytes(content)
    print(f"Installed {attributes['name']} ({profile_type}, expires {attributes['expirationDate'][:10]})", flush=True)
    return attributes["name"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", required=True)
    parser.add_argument("--create-ios-profile", action="store_true", help="Allow creation of a missing iOS App Store profile")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Release signing requires macOS")
    missing = [name for name in SECRET_NAMES if not os.environ.get(name)]
    if missing:
        parser.error("Bind these secure secrets to this command: " + ", ".join(missing))
    os.environ["ASC_BYPASS_KEYCHAIN"] = "1"
    bundle = next(line.split("=", 1)[1].strip() for line in (ROOT / "Config/Signing.xcconfig").read_text().splitlines()
                  if line.startswith("PRODUCT_BUNDLE_IDENTIFIER"))
    state = Path.home() / ".local/share/eglu-release"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    keychain = state / "signing.keychain-db"
    password = keychain_password(keychain)
    security_command(["unlock-keychain", "-p", password, keychain])
    run(["security", "set-keychain-settings", "-lut", "21600", keychain])
    search = shlex.split(run(["security", "list-keychains", "-d", "user"]).stdout.decode())
    if str(keychain) not in search:
        run(["security", "list-keychains", "-d", "user", "-s", *search, keychain])
    identities = []
    for prefix, kind in (("IOS_DISTRIBUTION", "Apple Distribution"), ("MAC_DEVELOPER_ID", "Developer ID Application")):
        identity = signing_identity(prefix, kind, args.team)
        identities.append(identity)
        known = run(["security", "find-identity", "-p", "codesigning", keychain]).stdout.decode()
        if identity["sha1"] not in known:
            with tempfile.TemporaryDirectory(prefix="eglu-signing-") as temp:
                archive = Path(temp) / "identity.p12"
                archive.write_bytes(base64.b64decode(os.environ[prefix + "_P12_B64"]))
                archive.chmod(0o600)
                security_command(["import", archive, "-k", keychain, "-f", "pkcs12", "-x", "-P",
                                  os.environ[prefix + "_P12_PASSWORD"], "-T", "/usr/bin/codesign"])
        print(f"Restored {kind} for {args.team}", flush=True)
    security_command(["set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain])
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        # PEM newlines are encoded for Keychain transport, never written to a file.
        value = base64.b64encode(os.environ[name].encode()).decode()
        security_command(["add-generic-password", "-U", "-s", SERVICE, "-a", name,
                          "-T", "/usr/bin/security", "-w", value, keychain])
    tools = sparkle_tools()
    expected = re.search(r"SPARKLE_PUBLIC_KEY: (\S+)", (ROOT / "project.yml").read_text())[1]
    existing = run([tools / "generate_keys", "--account", "safience", "-p"], check=False)
    if existing.returncode:
        previous = shlex.split(run(["security", "default-keychain", "-d", "user"]).stdout.decode())[0]
        try:
            run(["security", "default-keychain", "-d", "user", "-s", keychain])
            run([tools / "generate_keys", "--account", "safience", "-f", "/dev/stdin"], data=os.environ["SPARKLE_PRIVATE_KEY"].strip().encode())
        finally:
            run(["security", "default-keychain", "-d", "user", "-s", previous])
    public = run([tools / "generate_keys", "--account", "safience", "-p"]).stdout.decode().strip()
    if public != expected:
        raise ValueError("Stored Sparkle key does not match the configured public key; refusing to replace it")
    print("Sparkle public key matches project.yml", flush=True)
    run(["xcrun", "notarytool", "store-credentials", "safience", "--key", "/dev/stdin", "--key-id",
         os.environ["ASC_KEY_ID"], "--issuer", os.environ["ASC_ISSUER_ID"], "--keychain", keychain],
        data=os.environ["ASC_PRIVATE_KEY"].encode())
    print("Notarization credentials validated and stored in the release Keychain", flush=True)
    ios = install_profile("IOS_APP_STORE", identities[0], args.team, bundle, args.create_ios_profile)
    mac = install_profile("MAC_APP_DIRECT", identities[1], args.team, bundle, False)
    config = Path.home() / ".config/eglu-release"
    config.mkdir(parents=True, exist_ok=True, mode=0o700)
    exports = {"DEVELOPMENT_TEAM": args.team, "ICLOUD": "1", "PROFILE": mac, "IOS_PROFILE": ios,
               "NOTARY_PROFILE": "safience", "NOTARY_KEYCHAIN": str(keychain), "ASC_BYPASS_KEYCHAIN": "1"}
    lines = ["# Generated non-secret settings. Do not source with shell tracing enabled.",
             'case $- in *x*) echo "Disable shell tracing before loading credentials" >&2; return 1;; esac']
    lines += [f"export {name}={shlex.quote(value)}" for name, value in exports.items()]
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        lines.append(f"export {name}=\"$(security find-generic-password -s {SERVICE} -a {name} -w \"$NOTARY_KEYCHAIN\" | /usr/bin/base64 -D)\"")
    environment = config / "environment.sh"
    environment.write_text("\n".join(lines) + "\n")
    environment.chmod(0o600)
    print(f"Ready. Load release settings: source {environment}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, StopIteration) as error:
        sys.exit(str(error) or "A matching signing resource was not found")
