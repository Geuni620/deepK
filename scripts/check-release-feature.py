#!/usr/bin/env python3
"""Verify the feature and recipient notices in the app that will actually ship."""
from pathlib import Path
import plistlib
import sys


def check(app, project):
    problems = []
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        binary = (app / "Contents/MacOS" / info["CFBundleExecutable"]).read_bytes()
    except (OSError, KeyError, plistlib.InvalidFileException):
        return ["app metadata or executable missing"]
    for symbol in (b"NativeImageInput", b"SelectionTextLayout"):
        if symbol not in binary:
            problems.append("production image feature missing")
    for marker in (b"POCSyntheticDemo", b"POCFixtures", b"--record-synthetic-demo", b"--resilience-live", b"DEEPK_POC_AUDIT_EXPECTED_TEXT"):
        if marker in binary:
            problems.append("synthetic evidence code included in distribution")
    if not info.get("NSScreenCaptureUsageDescription"):
        problems.append("explicit screen capture usage description missing")
    if (app / "Contents/Resources/MIGAN_512.mlmodelc").exists():
        for name in ["LICENSE-MWOYEO", "LICENSE-MI-GAN-WEIGHTS", "IMAGE-MODEL-NOTICES.md"]:
            if not (app / "Contents/Resources" / name).is_file():
                problems.append("local restoration model notice missing: " + name)
    for source, destination in [
        ("LICENSE", "LICENSE"), ("docs/licensing.md", "docs/licensing.md"),
        ("THIRD-PARTY-NOTICES.txt", "THIRD-PARTY-NOTICES.txt"),
    ]:
        target = app / "Contents/Resources" / destination
        if not target.is_file() or target.read_bytes() != (project / source).read_bytes():
            problems.append("recipient notice missing or stale: " + destination)
    return sorted(set(problems))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: check-release-feature.py APP")
    issues = check(Path(sys.argv[1]), Path(__file__).resolve().parent.parent)
    for issue in issues:
        print("Release check: " + issue, file=sys.stderr)
    if not issues:
        print("PASS: production image feature, test-code exclusion and recipient notices")
    raise SystemExit(bool(issues))
