#!/usr/bin/env python3
"""Transparent stdio audit for the hardcoded synthetic live-smoke only. Never records content."""
import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path

real = os.environ.pop("DEEPK_POC_AUDIT_REAL_CODEX")
output = os.environ.pop("DEEPK_POC_AUDIT_OUTPUT")
expected = os.environ.pop("DEEPK_POC_AUDIT_EXPECTED_TEXT")
summary = {"scope": "synthetic CLI JSON-RPC request; not provider HTTP or retention audit", "turnCount": 0, "checks": []}
summary_lock = threading.RLock()
pending_methods = {}
summary["rpcRequests"] = []
summary["rpcResponses"] = []
child = subprocess.Popen([real, *sys.argv[1:]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr)


def approved_source(value):
    # Text and OCR now travel in separate phases. Every submitted block must still be
    # byte-for-byte one of the fixed synthetic fixture's blocks, with no extra prose.
    expression = re.compile(r"<([ar])([0-9]+)>([\s\S]*?)</\1\2>")
    wanted = list(expression.finditer(expected))
    found = list(expression.finditer(value))
    if not wanted or not found or expression.sub("", expected).strip() or expression.sub("", value).strip():
        return False
    mapping = {(m[1], m[2]): m[0] for m in wanted}
    keys = [(m[1], m[2]) for m in found]
    if len(mapping) != len(wanted) or len(set(keys)) != len(keys):
        return False
    if any(mapping.get((m[1], m[2])) != m[0] for m in found):
        return False
    return keys == [(m[1], m[2]) for m in wanted if (m[1], m[2]) in set(keys)]


def write_summary():
    # The executable resolver also invokes this wrapper with --version. That short probe must
    # never overwrite an app-server audit with an empty report.
    if "app-server" not in sys.argv[1:]:
        return
    with summary_lock:
        os.makedirs(os.path.dirname(output), exist_ok=True)
        destination = Path(output)
        process_copy = destination.with_name(f"{destination.stem}.process-{os.getpid()}{destination.suffix}")
        for path in (destination, process_copy):
            temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(summary, handle, indent=2, sort_keys=True)
            os.replace(temporary, path)


def forward_input():
    try:
        for line in sys.stdin.buffer:
            message = json.loads(line)
            if "id" in message and isinstance(message.get("method"), str):
                with summary_lock:
                    pending_methods[str(message["id"])] = message["method"]
                    summary["rpcRequests"].append(message["method"])
                    write_summary()
            if message.get("method") == "thread/start":
                params = message.get("params", {})
                config = params.get("config", {})
                features = config.get("features", {})
                summary["threadProtection"] = {
                    "ephemeral": params.get("ephemeral") is True,
                    "approvalNever": params.get("approvalPolicy") == "never",
                    "shellDisabled": features.get("shell_tool") is False,
                    "viewImageDisabled": features.get("view_image") is False,
                    "appsDisabled": features.get("apps") is False,
                    "memoriesDisabled": features.get("memories") is False,
                }
                write_summary()
            if message.get("method") == "turn/start":
                items = message.get("params", {}).get("input", [])
                texts = [item.get("text", "") for item in items]
                sources = []
                for text in texts:
                    if "<source_text>\n" in text and "\n</source_text>" in text:
                        sources.append(text.split("<source_text>\n", 1)[1].rsplit("\n</source_text>", 1)[0])
                check = {
                    "onlyTextItems": bool(items) and all(set(item) == {"type", "text"} and item["type"] == "text" for item in items),
                    "sourceExactlyMatchesApprovedSyntheticRegions": len(sources) == 1 and approved_source(sources[0]),
                    "approvedRegionBatch": bool(expected) and len(re.findall(r"<[ar][0-9]+>", expected)) >= 1,
                    "noImageDataOrReferences": all("data:image/" not in text and "image_url" not in text and "file://" not in text for text in texts),
                    "noFixtureNameOrMetadata": all("역 안내판" not in text and "synthetic-original.png" not in text and "EXIF" not in text for text in texts),
                }
                summary["turnCount"] += 1
                summary["checks"].append(check)
                write_summary()
                if not all(check.values()):
                    child.terminate()
                    return
            child.stdin.write(line)
            child.stdin.flush()
    except (BrokenPipeError, ValueError):
        pass
    finally:
        try:
            child.stdin.close()
        except BrokenPipeError:
            pass


thread = threading.Thread(target=forward_input, daemon=True)
thread.start()
try:
    for line in child.stdout:
        try:
            message = json.loads(line)
            if "id" in message:
                with summary_lock:
                    method = pending_methods.pop(str(message["id"]), None)
                    if method:
                        summary["rpcResponses"].append(method)
                        write_summary()
        except (ValueError, TypeError):
            pass
        sys.stdout.buffer.write(line)
        sys.stdout.buffer.flush()
finally:
    if child.poll() is None:
        child.terminate()
    try:
        child.wait(timeout=2)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait()
    write_summary()
