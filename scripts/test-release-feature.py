#!/usr/bin/env python3
"""Accountless regression for the real shipping feature boundary."""
from pathlib import Path
import importlib.util
import plistlib
import shutil
import tempfile

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("release_check", root / "scripts/check-release-feature.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
with tempfile.TemporaryDirectory(prefix="deepk-release-feature-") as work:
    app = Path(work) / "deepK.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources/docs").mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable":"deepK","NSScreenCaptureUsageDescription":"synthetic permission fixture"}))
    binary = app / "Contents/MacOS/deepK"
    binary.write_bytes(b"NativeImageInput SelectionTextLayout")
    for name in ["LICENSE", "docs/licensing.md", "THIRD-PARTY-NOTICES.txt"]:
        shutil.copy2(root / name, app / "Contents/Resources" / name)
    assert not checker.check(app, root)
    binary.write_bytes(b"old app without image input")
    assert "production image feature missing" in checker.check(app, root)
    binary.write_bytes(b"NativeImageInput SelectionTextLayout --resilience-live")
    assert "synthetic evidence code included in distribution" in checker.check(app, root)
    binary.write_bytes(b"NativeImageInput SelectionTextLayout")
    (app / "Contents/Resources/LICENSE").unlink()
    assert any("recipient notice" in item for item in checker.check(app, root))
print("PASS: shipping guard detects missing feature, test entrypoint leakage and notice delivery")
