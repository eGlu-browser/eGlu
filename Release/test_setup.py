import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_setup", Path(__file__).with_name("setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            "TeamIdentifier": ["TEAM"],
            "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=1),
            "DeveloperCertificates": [b"certificate"],
            "Entitlements": {
                "application-identifier": "TEAM.test.app",
                "com.apple.developer.icloud-container-identifiers": ["iCloud.test.app"],
                "com.apple.developer.icloud-services": ["CloudKit", "CloudDocuments"],
                "com.apple.developer.icloud-container-environment": ["Development", "Production"],
                "aps-environment": "production",
                "com.apple.developer.web-browser": True,
                "com.apple.developer.ubiquity-kvstore-identifier": "TEAM.test.app",
            },
        }

    def check(self, profile=None, ios=True):
        setup.check_profile(profile or self.profile, hashlib.sha256(b"certificate").hexdigest(), "TEAM", "test.app", ios)

    def test_ios_distribution_profile(self):
        self.check()

    def test_mac_profile(self):
        entitlements = self.profile["Entitlements"]
        entitlements["com.apple.application-identifier"] = entitlements.pop("application-identifier")
        entitlements["com.apple.developer.aps-environment"] = entitlements.pop("aps-environment")
        self.check(ios=False)

    def test_invalid_identity_and_entitlements(self):
        for key, value in (("TeamIdentifier", ["OTHER"]), ("DeveloperCertificates", [b"other"]),
                           ("ExpirationDate", datetime.now(timezone.utc) - timedelta(days=1))):
            with self.subTest(key=key):
                profile = copy.deepcopy(self.profile)
                profile[key] = value
                with self.assertRaises(ValueError):
                    self.check(profile)
        for key, value in (("aps-environment", "development"), ("get-task-allow", True),
                           ("com.apple.developer.web-browser", False),
                           ("com.apple.developer.icloud-container-identifiers", ["iCloud.other"]),
                           ("application-identifier", "TEAM.other")):
            with self.subTest(key=key):
                profile = copy.deepcopy(self.profile)
                profile["Entitlements"][key] = value
                with self.assertRaises(ValueError):
                    self.check(profile)

    def test_passwords_are_not_process_arguments(self):
        with patch.object(setup, "run") as run:
            run.return_value.stderr = b""
            setup.security_command(["unlock-keychain", "-p", 'sensitive"password', "test.keychain"])
            self.assertEqual(run.call_args.args[0], ["security", "-i"])
            self.assertNotIn("sensitive", str(run.call_args.args))

    def test_keychain_command_injection_is_rejected(self):
        with self.assertRaises(ValueError):
            setup.security_command(["unlock-keychain", "-p", "password\ndelete-keychain other"])


if __name__ == "__main__":
    unittest.main()
