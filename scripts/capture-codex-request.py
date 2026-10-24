#!/usr/bin/env python3
"""deepK가 보내는 Codex 요청 본문을 로컬에서 캡처한다. 구독 사용량을 쓰지 않는다.

capture-codex-request.sh가 다음 하위 명령을 차례로 부른다.
- `proxy`: CodexTranslationClient의 실행 파일 자리에 들어가 실제 `codex app-server`를 띄운다.
  JSONL은 그대로 전달하고 `thread/start` config에 로컬 모델 제공자만 더한다. 그래서 turn의 Responses 요청은
  이 스크립트의 가짜 서버(127.0.0.1)로만 간다. 로컬 제공자로 확인되지 않은 스레드의 `turn/start`는 막는다.
  configWarning 같은 알림은 응답이 아니라 별도 알림이므로 따로 모은다. Codex의 HTTPS 연결은 기록용 CONNECT
  중계를 거치게 해, 모델 요청 외에 Codex가 스스로 접속한 호스트(계정·모델 목록·사용 한도 조회)를 남긴다.
- `snapshot`: `~/.codex`(또는 CODEX_HOME)의 파일 목록과 크기·수정 시각만 기록한다. 내용은 읽지 않는다.
- `report`: 캡처한 요청을 계획 4·5절 기준(크기, 개인 메모리 줄, 스킬 안내, goal 도구, configWarning, 계층)으로
  검사해 전체 보고서를 파일로 쓰고, 짧은 JSON을 표준 출력에 낸다. 메모리 요약은 일치한 줄 수만 센다.

proxy 모드의 캡처 디렉터리는 환경변수 DEEPK_CAPTURE_DIR, 실제 Codex 경로는 DEEPK_CAPTURE_REAL_CODEX로 받는다.
"""

import http.server
import json
import os
import select
import socket
import socketserver
import subprocess
import sys
import threading

PROVIDER_ID = "deepk_capture"
BODY_LIMIT = 10 * 1024
GOAL_TOOLS = ("create_goal", "get_goal", "update_goal")
# 계획 4절은 request_user_input 도구를 제거로 정했다. `tools.experimental_request_user_input.enabled=false`는 앞의 것만 끈다.
# 비동기 변형은 모델 카탈로그의 experimental_supported_tools로만 켜져(core/src/tools/spec_plan.rs@rust-v0.160.0)
# 스레드 config로 끌 수 없다. 남아 있으면 실패로 보고하고 사용자 결정이 필요하다고 적는다.
USER_INPUT_TOOLS = ("request_user_input", "request_user_input_async", "send_user_message_async")


def codex_home():
    return os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")


def capture_dir():
    path = os.environ["DEEPK_CAPTURE_DIR"]
    os.makedirs(path, exist_ok=True)
    return path


def next_path(directory, prefix, suffix, lock=threading.Lock()):
    with lock:
        index = 1
        while os.path.exists(os.path.join(directory, f"{prefix}-{index}{suffix}")):
            index += 1
        path = os.path.join(directory, f"{prefix}-{index}{suffix}")
        open(path, "w").close()
        return path


def append_line(path, text, lock=threading.Lock()):
    with lock, open(path, "a", encoding="utf-8") as handle:
        handle.write(text + "\n")


def sse(event):
    return f"event: {event['type']}\ndata: {json.dumps(event, ensure_ascii=False)}\n\n".encode()


class FakeResponses(http.server.BaseHTTPRequestHandler):
    """Responses API 스트림의 최소 형태만 돌려준다. 인증 헤더는 기록하지 않는다."""

    def log_message(self, *_):
        pass

    def do_GET(self):
        append_line(os.path.join(capture_dir(), "paths.log"), f"GET {self.path}")
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        directory = capture_dir()
        append_line(os.path.join(directory, "paths.log"), f"POST {self.path}")
        if not self.path.endswith("/responses"):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        with open(next_path(directory, "req", ".json"), "wb") as handle:
            handle.write(body)
        response_id = "resp_deepk_capture"
        item = {"type": "message", "role": "assistant", "id": "msg_deepk_capture",
                "content": [{"type": "output_text", "text": "캡처"}]}
        usage = {"input_tokens": 0, "input_tokens_details": None, "output_tokens": 0,
                 "output_tokens_details": None, "total_tokens": 0}
        payload = b"".join([
            sse({"type": "response.created", "response": {"id": response_id}}),
            sse({"type": "response.output_item.added", "item": item}),
            sse({"type": "response.output_text.delta", "item_id": item["id"], "delta": "캡처"}),
            sse({"type": "response.output_item.done", "item": item}),
            sse({"type": "response.completed", "response": {"id": response_id, "usage": usage}}),
        ])
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class ConnectLogger(socketserver.StreamRequestHandler):
    """HTTPS_PROXY로 받은 CONNECT의 호스트만 기록하고 그대로 잇는다. TLS 내용은 보지 않는다."""

    def handle(self):
        request_line = self.rfile.readline(65536).decode("latin-1").strip()
        while self.rfile.readline(65536) not in (b"\r\n", b"\n", b""):
            pass
        parts = request_line.split()
        log = os.path.join(capture_dir(), "outbound.log")
        if len(parts) < 2 or parts[0].upper() != "CONNECT":
            # 평문 HTTP 프록시 요청은 중계하지 않는다(호스트만 남기고 거절).
            append_line(log, f"refused {request_line[:200]}")
            self.wfile.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        host, _, port = parts[1].rpartition(":")
        append_line(log, f"CONNECT {parts[1]}")
        try:
            upstream = socket.create_connection((host, int(port or 443)), timeout=15)
        except OSError:
            self.wfile.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        self.wfile.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        self.wfile.flush()
        sockets = [self.connection, upstream]
        try:
            while True:
                readable, _, _ = select.select(sockets, [], [], 120)
                if not readable:
                    return
                for source in readable:
                    data = source.recv(65536)
                    if not data:
                        return
                    (upstream if source is self.connection else self.connection).sendall(data)
        except OSError:
            return
        finally:
            upstream.close()


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True


def proxy(arguments):
    directory = capture_dir()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeResponses)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    tunnel = ThreadingTCPServer(("127.0.0.1", 0), ConnectLogger)
    threading.Thread(target=tunnel.serve_forever, daemon=True).start()
    base_url = f"http://127.0.0.1:{server.server_address[1]}/v1"
    proxy_url = f"http://127.0.0.1:{tunnel.server_address[1]}"
    environment = dict(os.environ)
    environment.pop("DEEPK_CAPTURE_DIR", None)
    for key in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"):
        environment[key] = proxy_url
    environment["NO_PROXY"] = environment["no_proxy"] = "127.0.0.1,localhost"
    codex = subprocess.Popen([os.environ["DEEPK_CAPTURE_REAL_CODEX"], *arguments],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=environment)
    output_lock = threading.Lock()
    state_lock = threading.Lock()
    pending_threads = set()
    local_threads = set()

    def write_output(line):
        with output_lock:
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()

    def forward_input():
        for line in sys.stdin.buffer:
            message = json.loads(line)
            method = message.get("method")
            params = message.get("params") or {}
            if method == "turn/start":
                with state_lock:
                    allowed = params.get("threadId") in local_threads
                if not allowed:
                    # 로컬 제공자로 확인되지 않은 스레드의 turn은 실제 모델로 갈 수 있으므로 보내지 않는다.
                    append_line(os.path.join(directory, "blocked.log"), str(params.get("threadId")))
                    write_output((json.dumps({"id": message.get("id"), "error": {
                        "code": -32099, "message": "capture proxy blocked a turn outside the local provider"}})
                        + "\n").encode())
                    continue
                with open(next_path(directory, "turn-start", ".json"), "w", encoding="utf-8") as handle:
                    json.dump({key: value for key, value in params.items() if key != "input"}, handle, indent=2)
            if method == "thread/start":
                with state_lock:
                    pending_threads.add(message.get("id"))
                params = message.setdefault("params", {})
                config = params.setdefault("config", {})
                with open(next_path(directory, "thread-start", ".json"), "w", encoding="utf-8") as handle:
                    json.dump(params, handle, ensure_ascii=False, indent=2)
                # 기본 openai 제공자는 덮어쓸 수 없으므로(model-provider-info) 로컬 제공자를 더하고
                # 이 스레드에서만 선택한다. deepK가 보낸 나머지 config는 그대로 둔다.
                config["model_provider"] = PROVIDER_ID
                config["model_providers"] = {PROVIDER_ID: {
                    "name": "deepK capture", "base_url": base_url, "wire_api": "responses",
                    "request_max_retries": 0, "stream_max_retries": 0, "supports_websockets": False,
                }}
                line = (json.dumps(message, ensure_ascii=False) + "\n").encode()
            codex.stdin.write(line)
            codex.stdin.flush()
        codex.stdin.close()

    threading.Thread(target=forward_input, daemon=True).start()
    notifications = os.path.join(directory, "notifications.jsonl")
    for line in codex.stdout:
        try:
            message = json.loads(line)
        except ValueError:
            message = {}
        if "method" in message and "id" not in message:
            append_line(notifications, json.dumps({"method": message["method"], "params": message.get("params")},
                                                  ensure_ascii=False))
        elif "method" not in message:
            with state_lock:
                is_thread_start = message.get("id") in pending_threads
                pending_threads.discard(message.get("id"))
            result = message.get("result") or {}
            if is_thread_start and result.get("modelProvider") == PROVIDER_ID:
                with state_lock:
                    local_threads.add((result.get("thread") or {}).get("id"))
            elif is_thread_start:
                with open(os.path.join(directory, "provider-mismatch.json"), "w", encoding="utf-8") as handle:
                    json.dump(message, handle, ensure_ascii=False)
        write_output(line)
    return codex.wait()


def snapshot(output):
    """파일 경로·크기·수정 시각만 모은다. 대화 기록이나 메모리 내용은 읽지 않는다."""
    root = codex_home()
    entries = {}
    for directory, _, files in os.walk(root):
        for name in files:
            path = os.path.join(directory, name)
            try:
                info = os.lstat(path)
            except OSError:
                continue
            entries[os.path.relpath(path, root)] = [info.st_size, info.st_mtime_ns]
    with open(output, "w", encoding="utf-8") as handle:
        json.dump({"root": root, "entries": entries}, handle)
    return 0


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)


def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def numbered(directory, prefix):
    names = [name for name in os.listdir(directory) if name.startswith(prefix + "-") and name.endswith(".json")]
    return sorted(names, key=lambda name: int(name[len(prefix) + 1:-5]))


def memory_lines():
    path = os.path.join(codex_home(), "memories", "memory_summary.md")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [line.strip() for line in handle if len(line.strip()) >= 40]


def analyze_case(directory, memory):
    requests = []
    for name in numbered(directory, "req"):
        with open(os.path.join(directory, name), "rb") as handle:
            raw = handle.read()
        body = json.loads(raw)
        text = "\n".join(strings(body))
        # code mode에서는 도구가 input의 additional_tools 항목 안 namespace로 들어간다.
        declared = list(body.get("tools", []))
        for entry in body.get("input", []):
            if isinstance(entry, dict) and entry.get("type") == "additional_tools":
                declared.extend(entry.get("tools", []))
        tools, tool_names = [], set()
        for tool in declared:
            if not isinstance(tool, dict):
                continue
            nested = [child.get("name") for child in tool.get("tools", []) if isinstance(child, dict)]
            tool_names.update(name for name in [tool.get("name"), *nested] if name)
            tools.append(f"{tool.get('name')}:{','.join(nested)}" if nested else (tool.get("name") or tool.get("type")))
        requests.append({
            "file": name,
            "bytes": len(raw),
            "memoryLines": sum(1 for line in memory if line in text),
            "skillsInstructions": "<skills_instructions>" in text,
            "goalTools": [tool for tool in GOAL_TOOLS if tool in text],
            "userInputTools": sorted({name for name in tool_names if name in USER_INPUT_TOOLS}),
            "viewImage": "view_image" in text,
            "serviceTier": body.get("service_tier"),
            "tools": tools,
        })
    threads = [load_json(os.path.join(directory, name)) for name in numbered(directory, "thread-start")]
    turns = [load_json(os.path.join(directory, name)) for name in numbered(directory, "turn-start")]
    notifications = []
    path = os.path.join(directory, "notifications.jsonl")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            notifications = [json.loads(line) for line in handle if line.strip()]
    outbound = []
    path = os.path.join(directory, "outbound.log")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            outbound = sorted({line.strip() for line in handle if line.strip()})
    paths = []
    path = os.path.join(directory, "paths.log")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            paths = [line.strip() for line in handle if line.strip()]
    return {
        "requests": requests,
        "threadServiceTiers": [thread.get("serviceTier") for thread in threads],
        "threadConfigServiceTiers": [(thread.get("config") or {}).get("service_tier") for thread in threads],
        "turnServiceTiers": [turn.get("serviceTierForTurn") for turn in turns],
        "models": sorted({thread.get("model") for thread in threads if thread.get("model")}),
        "configWarnings": [item.get("params") for item in notifications if item["method"] == "configWarning"],
        # 일반 warning은 기록만 한다(예: --disable code_mode_host 때문에 나오는 Code Mode 안내).
        "warnings": [(item.get("params") or {}).get("message") for item in notifications if item["method"] == "warning"],
        "fakeServerPaths": paths,
        "outboundHosts": outbound,
        "blockedTurns": os.path.exists(os.path.join(directory, "blocked.log")),
        "providerMismatch": os.path.exists(os.path.join(directory, "provider-mismatch.json")),
    }


def case_failures(name, case, expected_tier):
    failures = []
    if not case["requests"]:
        failures.append(f"{name}: no Responses request was captured")
    if case["blockedTurns"] or case["providerMismatch"]:
        failures.append(f"{name}: a thread did not use the local provider")
    if case["configWarnings"]:
        failures.append(f"{name}: {len(case['configWarnings'])} configWarning notification(s)")
    if any(tier != "default" for tier in case["threadConfigServiceTiers"]):
        failures.append(f"{name}: config.service_tier is {case['threadConfigServiceTiers']}, expected 'default'")
    expected = "priority" if expected_tier == "priority" else "default"
    if case["threadServiceTiers"] != [expected] * len(case["threadServiceTiers"]) or \
            case["turnServiceTiers"] != [expected] * len(case["turnServiceTiers"]):
        failures.append(f"{name}: thread/turn tiers {case['threadServiceTiers']}/{case['turnServiceTiers']}, "
                        f"expected {expected!r}")
    for item in case["requests"]:
        if item["memoryLines"] or item["skillsInstructions"] or item["goalTools"]:
            failures.append(f"{name}/{item['file']}: still contains memory, skill or goal context")
        if item["userInputTools"]:
            failures.append(f"{name}/{item['file']}: user input tools {item['userInputTools']} remain "
                            "(the async variant comes from the model catalog and cannot be disabled by thread config; "
                            "needs a user decision)")
        if expected_tier == "priority" and item["serviceTier"] != "priority":
            failures.append(f"{name}/{item['file']}: service_tier is {item['serviceTier']!r}, expected 'priority'")
        if expected_tier == "default" and item["serviceTier"] == "priority":
            failures.append(f"{name}/{item['file']}: requested priority while Fast is off")
        # `$스킬이름` 원문은 SKILL.md가 붙는 크기만 기록한다(계획 4절 남는 위험).
        if expected_tier != "record" and item["bytes"] > BODY_LIMIT:
            failures.append(f"{name}/{item['file']}: body is {item['bytes']}B (> {BODY_LIMIT}B)")
    return failures


def home_changes(run_dir):
    before = load_json(os.path.join(run_dir, "codex-home-before.json"))
    after = load_json(os.path.join(run_dir, "codex-home-after.json"))
    if not before or not after:
        return None
    old, new = before["entries"], after["entries"]
    return {
        "root": after["root"],
        "added": sorted(set(new) - set(old)),
        "modified": sorted(path for path in set(new) & set(old) if new[path] != old[path]),
        "removed": sorted(set(old) - set(new)),
    }


def report(run_dir, output):
    memory = memory_lines()
    entries = load_json(os.path.join(run_dir, "cases.json"), {})
    cases, failures = {}, []
    if not memory:
        # 비교할 메모리 줄이 없으면 '메모리 줄 0개'는 아무것도 확인하지 않은 채 통과한다.
        failures.append(f"memory summary has no lines to check "
                        f"({os.path.join(codex_home(), 'memories', 'memory_summary.md')}); memory check unverified")
    for name, entry in entries.items():
        directory = os.path.join(run_dir, name)
        if not os.path.isdir(directory):
            failures.append(f"{name}: no capture directory")
            continue
        cases[name] = analyze_case(directory, memory)
        cases[name]["model"] = entry.get("model")
        cases[name]["modelSource"] = entry.get("modelSource")
        failures.extend(case_failures(name, cases[name], entry.get("expectation")))
    changes = home_changes(run_dir)
    if changes is None:
        failures.append("codex home snapshot is missing; config.toml change check unverified")
    else:
        for kind in ("added", "modified", "removed"):
            if "config.toml" in changes[kind]:
                failures.append(f"{changes['root']}/config.toml was {kind} during the capture")
    full = {
        "codex": load_json(os.path.join(run_dir, "executable.json")),
        "helper": load_json(os.path.join(run_dir, "helper.json")),
        "memorySummaryLinesChecked": len(memory),
        "bodyLimitBytes": BODY_LIMIT,
        "cases": cases,
        "codexHomeChanges": changes,
        "failures": failures,
    }
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(full, handle, ensure_ascii=False, indent=2)

    def short(case):
        return {
            "model": case.get("model"),
            "bodyBytes": [item["bytes"] for item in case["requests"]],
            "memoryLines": sum(item["memoryLines"] for item in case["requests"]),
            "skillsInstructions": any(item["skillsInstructions"] for item in case["requests"]),
            "goalTools": sorted({tool for item in case["requests"] for tool in item["goalTools"]}),
            "userInputTools": sorted({tool for item in case["requests"] for tool in item["userInputTools"]}),
            "configWarnings": len(case["configWarnings"]),
            "warnings": len(case["warnings"]),
            "threadServiceTier": case["threadServiceTiers"],
            "turnServiceTier": case["turnServiceTiers"],
            "requestServiceTier": [item["serviceTier"] for item in case["requests"]],
            "models": case["models"],
            "outboundHosts": case["outboundHosts"],
        }

    summary = {
        "codex": full["codex"],
        "models": (full["helper"] or {}).get("models"),
        "memorySummaryLinesChecked": len(memory),
        "cases": {name: short(case) for name, case in cases.items()},
        "codexHomeWrites": None if changes is None else changes["added"] + changes["modified"] + changes["removed"],
        "failures": failures,
        "report": output,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "snapshot":
        sys.exit(snapshot(sys.argv[2]))
    if command == "report":
        sys.exit(report(sys.argv[2], sys.argv[3]))
    # proxy 모드: CodexTranslationClient가 넘기는 인자(app-server --stdio --disable ...)를 그대로 전달한다.
    sys.exit(proxy(sys.argv[1:]))
