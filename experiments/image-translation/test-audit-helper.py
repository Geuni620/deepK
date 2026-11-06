#!/usr/bin/env python3
"""No network or credentials: verify synthetic audit preservation and rejection."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

wrapper = Path(__file__).with_name("audit-codex.py")
expected = "<r1>Tickets</r1><r0>Please check the platform before boarding.</r0>"
with tempfile.TemporaryDirectory(prefix="deepk-audit-unit-") as temporary:
    root = Path(temporary)
    fake = root / "fake-codex"
    fake.write_text(f"#!{sys.executable}\n" + '''import json,sys
if '--version' in sys.argv:
    print('codex-cli 0.160.1');sys.exit(0)
for line in sys.stdin:
    message=json.loads(line)
    if 'id' in message:
        print(json.dumps({'id':message['id'],'result':{}}),flush=True)
''')
    fake.chmod(0o755)
    output = root / "audit.json"
    environment = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "DEEPK_POC_AUDIT_REAL_CODEX": str(fake),
                   "DEEPK_POC_AUDIT_OUTPUT": str(output), "DEEPK_POC_AUDIT_EXPECTED_TEXT": expected}
    def messages(source):
        return "\n".join(json.dumps(message) for message in [
            {"id": 1, "method": "thread/start", "params": {"ephemeral": True, "approvalPolicy": "never", "config": {
                "features": {"shell_tool": False, "view_image": False, "apps": False, "memories": False}}}},
            {"id": 2, "method": "turn/start", "params": {"input": [{"type": "text", "text": f"<source_text>\n{source}\n</source_text>"}]}}
        ]) + "\n"
    for _ in range(2):
        subprocess.run([sys.executable, str(wrapper), "app-server", "--stdio"], input=messages(expected), text=True,
                       env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10)
        report = json.loads(output.read_text())
        assert report["turnCount"] == 1 and all(report["checks"][0].values())
        assert all(report["threadProtection"].values())
    copies = list(root.glob("audit.process-*.json"))
    assert len(copies) == 2 and all(json.loads(p.read_text())["turnCount"] == 1 for p in copies)
    for subset in ["<r1>Tickets</r1>", "<r0>Please check the platform before boarding.</r0>"]:
        subprocess.run([sys.executable, str(wrapper), "app-server", "--stdio"], input=messages(subset), text=True,
                       env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10)
        assert all(json.loads(output.read_text())["checks"][0].values())
    before = output.read_bytes()
    subprocess.run([sys.executable, str(wrapper), "--version"], input="", text=True, env=environment,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10)
    assert output.read_bytes() == before
    rejected = subprocess.run([sys.executable, str(wrapper), "app-server", "--stdio"], input=messages("synthetic mismatch"),
                              text=True, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10)
    assert not json.loads(output.read_text())["checks"][0]["sourceExactlyMatchesApprovedSyntheticRegions"]
    assert not any(json.loads(line).get("id") == 2 for line in rejected.stdout.splitlines())
print("PASS: audit snapshots survive version probes and process replacement; mismatched input is never forwarded")
