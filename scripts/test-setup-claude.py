"""Exercise the real setup script with fake npm/defaults; no network or host settings writes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parent / "setup-claude.sh"
with tempfile.TemporaryDirectory(prefix="deepk-setup-test-") as temporary:
    root = Path(temporary)
    script = root / "scripts/setup-claude.sh"
    script.parent.mkdir()
    shutil.copyfile(source, script)
    shims = root / "shims"
    shims.mkdir()
    calls = root / "calls.jsonl"

    def shim(name, content):
        path = shims / name
        path.write_text(content)
        path.chmod(0o755)

    shim("uname", "#!/bin/sh\necho arm64\n")
    shim("npm", """#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
prefix = pathlib.Path(args[args.index('--prefix') + 1])
cli = prefix / 'node_modules/@anthropic-ai/claude-code-darwin-arm64/claude'
cli.parent.mkdir(parents=True, exist_ok=True)
cli.write_text('#!/bin/sh\\necho fixture-version\\n')
cli.chmod(0o755)
with open(os.environ['DEEPK_SETUP_TEST_CALLS'], 'a') as output:
    output.write(json.dumps(['npm', str(prefix)]) + '\\n')
""")
    shim("defaults", """#!/usr/bin/env python3
import json, os, sys
with open(os.environ['DEEPK_SETUP_TEST_CALLS'], 'a') as output:
    output.write(json.dumps(['defaults', *sys.argv[1:]]) + '\\n')
""")
    environment = dict(os.environ, PATH=f"{shims}:{os.environ['PATH']}",
                       DEEPK_SETUP_TEST_CALLS=str(calls))
    legacy = root / ".build/claude-runtime/node_modules/legacy-marker"
    legacy.parent.mkdir(parents=True)
    legacy.write_text("existing installed CLI")

    for domain, arguments in [("com.deepk.app.dev", []), ("com.deepk.app", ["--installed"])]:
        subprocess.run(["/bin/bash", str(script), *arguments], env=environment,
                       check=True, capture_output=True, text=True)
        recorded = [json.loads(line) for line in calls.read_text().splitlines()]
        prefix = root / ".build/claude-runtime" / domain
        expected_cli = prefix / "node_modules/@anthropic-ai/claude-code-darwin-arm64/claude"
        assert recorded[-2] == ["npm", str(prefix)], recorded
        assert recorded[-1] == ["defaults", "write", domain, "claudeExecutablePath", "-string", str(expected_cli)], recorded
        assert legacy.read_text() == "existing installed CLI"

    before = calls.read_bytes()
    rejected = subprocess.run(["/bin/bash", str(script), "--unknown"], env=environment,
                              capture_output=True, text=True)
    assert rejected.returncode == 2
    assert calls.read_bytes() == before, "invalid mode must not install or change defaults"
    print("Claude setup isolation passed: separate install paths and defaults domains; legacy runtime preserved")
