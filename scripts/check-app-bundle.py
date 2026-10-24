#!/usr/bin/env python3
"""Reject local credential material before an app is uploaded or packaged."""

import pathlib
import re
import sys


PRIVATE_KEY = re.compile(br"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----")
CREDENTIAL_NAMES = {"auth.json", "credentials.json", ".credentials.json", ".npmrc", ".netrc", "id_rsa", "id_ed25519"}
PRIVATE_EXTENSIONS = {".p12", ".pfx", ".key", ".mobileprovision"}


def violations(app):
    problems = []
    for candidate in sorted(app.rglob("*")):
        relative = candidate.relative_to(app).as_posix()
        name = candidate.name.lower()
        if name in CREDENTIAL_NAMES or name in {".env", ".dev.vars"} or name.startswith((".env.", ".dev.vars.")) or candidate.suffix.lower() in PRIVATE_EXTENSIONS:
            problems.append(f"{relative}: local credential filename")
            continue
        try:
            if candidate.is_symlink():
                resolved = candidate.resolve(strict=True)
                if not resolved.is_relative_to(app):
                    problems.append(f"{relative}: symlink outside app bundle")
                    continue
            if candidate.is_file():
                with candidate.open("rb") as handle:
                    if PRIVATE_KEY.search(handle.read(4096)):
                        problems.append(f"{relative}: private key material")
        except (OSError, RuntimeError):
            problems.append(f"{relative}: unreadable bundle entry")
    return problems


def main():
    if len(sys.argv) != 2:
        print("usage: check-app-bundle.py DeepK.app", file=sys.stderr)
        return 2
    try:
        app = pathlib.Path(sys.argv[1]).resolve(strict=True)
        if not app.is_dir():
            raise NotADirectoryError
    except OSError:
        print("App bundle directory was not found.", file=sys.stderr)
        return 2
    problems = violations(app)
    if problems:
        print("App packaging stopped: remove local credentials or external symlinks:", file=sys.stderr)
        for problem in problems:
            print(f"- {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
