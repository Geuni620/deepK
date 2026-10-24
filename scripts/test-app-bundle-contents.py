#!/usr/bin/env python3
"""Accountless regression checks for the final app packaging boundary."""

import pathlib
import subprocess
import sys
import tempfile
import unittest


CHECKER = pathlib.Path(__file__).with_name("check-app-bundle.py")


class BundleContentsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="deepk-bundle-check-")
        self.root = pathlib.Path(self.directory.name)
        self.app = self.root / "DeepK.app"
        self.resources = self.app / "Contents" / "Resources"
        self.resources.mkdir(parents=True)

    def tearDown(self):
        self.directory.cleanup()

    def check(self):
        return subprocess.run([sys.executable, str(CHECKER), str(self.app)], capture_output=True, text=True)

    def test_regular_assets_and_internal_symlinks_are_allowed(self):
        (self.resources / "note.txt").write_text("synthetic public resource")
        (self.resources / "alias.txt").symlink_to("note.txt")
        (self.resources / "public.pem").write_text("synthetic public certificate fixture")
        self.assertEqual(self.check().returncode, 0)

    def test_local_configuration_and_signing_files_stop_packaging(self):
        for name in (".env", ".env.production", ".dev.vars", "auth.json", "signing.p12", "identity.key"):
            with self.subTest(name=name):
                candidate = self.resources / name
                candidate.write_text("SYNTHETIC_ONLY")
                result = self.check()
                self.assertEqual(result.returncode, 1)
                self.assertIn(name, result.stderr)
                self.assertNotIn("SYNTHETIC_ONLY", result.stderr)
                candidate.unlink()

    def test_private_key_header_is_rejected_even_with_another_filename(self):
        header = b"-----BEGIN " + b"PRIVATE KEY-----\n"
        (self.resources / "note.txt").write_bytes(header + b"SYNTHETIC_ONLY\n")
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("note.txt", result.stderr)
        self.assertNotIn("SYNTHETIC_ONLY", result.stderr)

    def test_external_symlink_stops_packaging(self):
        outside = self.root / "outside.txt"
        outside.write_text("SYNTHETIC_OUTSIDE")
        (self.resources / "outside-link").symlink_to(outside)
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("outside-link", result.stderr)
        self.assertNotIn("SYNTHETIC_OUTSIDE", result.stderr)


if __name__ == "__main__":
    unittest.main()
