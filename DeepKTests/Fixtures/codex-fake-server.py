#!/usr/bin/env python3
"""Small deterministic JSONL app-server fixture for CodexTranslationClient tests."""

import json
import os
import re
import sys
import time


MODE = sys.argv[1] if len(sys.argv) > 1 else "normal"
SAFETY_OK = False
INTERRUPTED = False
TURN_COUNT = 0
CURRENT_TURN_ID = "fixture-turn"
AUTH_ERROR_SENT = False
ACCOUNT_READ_COUNT = 0
THREAD_COUNT = 0
CURRENT_THREAD_ID = "fixture-thread"
THREAD_SAFETY = {}
THREAD_TIERS = {}
USED_THREADS = set()
IS_PREWARM = MODE.startswith("prewarm")
SERVICE_TIERS = ("default", "priority")
# 프로세스 --disable 6개와 번역 스레드에서만 끄는 자동 주입 기능 7개다. 정확히 이 키만 false여야 한다.
DISABLED_FEATURES = {
    "shell_tool", "apps", "multi_agent", "code_mode_host", "computer_use", "plugins",
    "memories", "goals", "hooks", "skill_search", "shell_snapshot", "view_image", "sleep_tool",
}


def record_environment():
    """실제 실행 환경에 어떤 부모 값이 남았는지 테스트가 확인할 수 있게 기록한다."""
    path = os.environ.get("DEEPK_ENVIRONMENT_FILE")
    if not path:
        return
    keys = (
        "GITHUB_TOKEN", "OPENAI_API_KEY", "AWS_SECRET_ACCESS_KEY",
        "HTTPS_PROXY", "no_proxy", "SSL_CERT_FILE", "CODEX_CA_CERTIFICATE", "LC_ALL", "VOLTA_HOME",
    )
    with open(path, "w", encoding="utf-8") as handle:
        json.dump({key: os.environ[key] for key in keys if key in os.environ}, handle, sort_keys=True)


record_environment()


def is_false(value, *path):
    for key in path:
        if not isinstance(value, dict):
            return False
        value = value.get(key)
    return value is False


def thread_config_is_safe(params):
    config = params.get("config", {})
    features = config.get("features", {})
    apps = config.get("apps", {}).get("_default", {})
    return (
        is_false(config, "mcp_servers", "fixture-mcp", "enabled")
        and isinstance(features, dict)
        and set(features) == DISABLED_FEATURES
        and all(value is False for value in features.values())
        and apps.get("enabled") is False
        and "default_tools_enabled" not in apps
        and is_false(config, "memories", "use_memories")
        and is_false(config, "memories", "generate_memories")
        and is_false(config, "skills", "include_instructions")
        and is_false(config, "skills", "bundled", "enabled")
        and is_false(config, "tools", "experimental_request_user_input", "enabled")
        and is_false(config, "agents", "enabled")
        and is_false(config, "include_environment_context")
        and is_false(config, "include_permissions_instructions")
        and is_false(config, "include_apps_instructions")
        and is_false(config, "include_collaboration_mode_instructions")
        and config.get("service_tier") == "default"
        and params.get("serviceTier") in SERVICE_TIERS
    )


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def respond(request_id, result=None, error=None):
    message = {"id": request_id}
    if error is None:
        message["result"] = result if result is not None else {}
    else:
        message["error"] = error
    send(message)


def record_interrupt():
    marker = os.environ.get("DEEPK_INTERRUPT_MARKER")
    if marker:
        with open(marker, "w", encoding="utf-8") as handle:
            handle.write("interrupted")


def record_call(method, detail=None):
    path = os.environ.get("DEEPK_CALL_COUNT_FILE")
    if not path:
        return

    suffix = f"|{detail}" if detail is not None else ""
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(f"{method}{suffix}\n")


for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    request_id = message.get("id")

    if request_id is None:
        continue

    detail = None
    if method == "turn/start":
        detail = message.get("params", {}).get("effort")
        if IS_PREWARM:
            detail = f"{detail}|{message.get('params', {}).get('threadId', '')}"
    elif method == "thread/start" and IS_PREWARM:
        detail = message.get("params", {}).get("model")
    record_call(method, detail)

    if request_id == "fixture-server-request":
        if "error" in message and SAFETY_OK:
            send(
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": CURRENT_THREAD_ID,
                        "turn": {
                            "id": CURRENT_TURN_ID,
                            "status": "completed",
                            "items": [
                                {
                                    "id": "fixture-item",
                                    "type": "agentMessage",
                                    "text": "안녕하세요",
                                }
                            ],
                        },
                    },
                }
            )
        continue

    if method == "initialize":
        respond(
            request_id,
            {
                "codexHome": "/private/tmp",
                "platformFamily": "unix",
                "platformOs": "macos",
                "userAgent": "deepK-test-fixture",
            },
        )
    elif method == "config/read":
        respond(
            request_id,
            {
                "config": {"mcp_servers": {"fixture-mcp": {"command": "ignored"}}},
                "origins": {},
                "layers": None,
            },
        )
    elif method == "account/logout":
        logout_marker = os.environ.get("DEEPK_INTERRUPT_MARKER")
        if logout_marker:
            with open(logout_marker, "w", encoding="utf-8") as handle:
                handle.write("logout")
        respond(request_id, {})
    elif method == "account/read":
        ACCOUNT_READ_COUNT += 1
        account_file = os.environ.get("DEEPK_ACCOUNT_TYPE_FILE")
        account_type = open(account_file, encoding="utf-8").read().strip() if account_file else "chatgpt"
        if MODE == "non-chatgpt" or (MODE == "account-switch" and ACCOUNT_READ_COUNT >= 2) or account_type == "apiKey":
            respond(
                request_id,
                {"account": {"type": "apiKey"}, "requiresOpenaiAuth": False},
            )
        else:
            respond(
                request_id,
                {
                    "account": {
                        "type": "chatgpt",
                        "email": "fixture@example.com",
                        "planType": "plus",
                    },
                    "requiresOpenaiAuth": False,
                },
            )
    elif method == "model/list":
        if IS_PREWARM:
            models = [{"id": model, "model": model, "displayName": model, "hidden": False,
                       "isDefault": model == "fixture-model", "defaultReasoningEffort": "medium",
                       "supportedReasoningEfforts": [{"reasoningEffort": "low", "description": "low"}]}
                      for model in ["fixture-model", "fixture-other"]]
            respond(request_id, {"data": models, "nextCursor": None})
            continue
        respond(
            request_id,
            {
                "data": [
                    {
                        "id": "fixture-model",
                        "model": "fixture-model",
                        "displayName": "Fixture",
                        "hidden": False,
                        "isDefault": True,
                        "defaultReasoningEffort": "medium",
                        "supportedReasoningEfforts": [
                            {"reasoningEffort": "low", "description": "low"}
                        ],
                    }
                ],
                "nextCursor": None,
            },
        )
    elif method == "thread/start":
        THREAD_COUNT += 1
        if MODE == "prewarm-fail-once" and THREAD_COUNT == 1:
            respond(request_id, error={"code": -32000, "message": "fixture preparation failure"})
            continue
        thread_start_marker = os.environ.get("DEEPK_THREAD_START_MARKER")
        if thread_start_marker:
            with open(thread_start_marker, "w", encoding="utf-8") as handle:
                handle.write("received")
        params = message.get("params", {})
        config_file = os.environ.get("DEEPK_THREAD_CONFIG_FILE")
        if config_file:
            with open(config_file, "w", encoding="utf-8") as handle:
                json.dump(params.get("config"), handle, ensure_ascii=False)
        SAFETY_OK = thread_config_is_safe(params)
        if MODE == "thread-cancel" or MODE == "prewarm-slow":
            time.sleep(0.5)
        new_thread_id = f"fixture-thread-{THREAD_COUNT}" if IS_PREWARM else "fixture-thread"
        THREAD_SAFETY[new_thread_id] = SAFETY_OK
        THREAD_TIERS[new_thread_id] = params.get("serviceTier")
        # 기존 'thread/start|...' 정확 일치 검사를 깨지 않도록 계층은 별도 줄로 남긴다.
        record_call("tier/thread", f"{params.get('serviceTier')}|{new_thread_id}")
        respond(
            request_id,
            {
                "thread": {"id": new_thread_id},
                "approvalPolicy": "never",
                "approvalsReviewer": "user",
                "cwd": message.get("params", {}).get("cwd", "/private/tmp"),
                "model": "fixture-model",
                "modelProvider": "openai",
                "sandbox": "read-only",
            },
        )
    elif method == "mcpServerStatus/list":
        respond(request_id, {"data": [], "nextCursor": None})
    elif method == "app/installed":
        respond(request_id, {"apps": []})
    elif method == "turn/start":
        TURN_COUNT += 1
        CURRENT_TURN_ID = f"fixture-turn-{TURN_COUNT}"
        CURRENT_THREAD_ID = message.get("params", {}).get("threadId", "fixture-thread")
        if IS_PREWARM and CURRENT_THREAD_ID in USED_THREADS:
            respond(request_id, error={"code": -32011, "message": "thread was used twice"})
            continue
        USED_THREADS.add(CURRENT_THREAD_ID)
        turn_tier = message.get("params", {}).get("serviceTierForTurn")
        record_call("tier/turn", f"{turn_tier}|{CURRENT_THREAD_ID}")
        # turn 계층은 항상 명시하고 스레드 계층과 같아야 한다.
        if (
            not THREAD_SAFETY.get(CURRENT_THREAD_ID, SAFETY_OK)
            or turn_tier not in SERVICE_TIERS
            or turn_tier != THREAD_TIERS.get(CURRENT_THREAD_ID)
        ):
            respond(
                request_id,
                error={"code": -32010, "message": "fixture safety config was incomplete"},
            )
            continue

        if MODE == "auth-error" and not AUTH_ERROR_SENT:
            AUTH_ERROR_SENT = True
            respond(
                request_id,
                error={"code": 401, "message": "authentication required"},
            )
            continue

        # partial-cancel-once: 첫 turn은 조각 하나를 보내고 turn/interrupt를 기다린다. 다음 turn은 normal처럼 끝난다.
        retried = MODE == "partial-cancel-once" and TURN_COUNT > 1
        if retried:
            # 취소된 첫 turn의 늦은 조각이다. 클라이언트가 이미 정리한 turn이라 어느 호출에도 가면 안 된다.
            send({"method": "item/agentMessage/delta", "params": {"threadId": CURRENT_THREAD_ID, "turnId": "fixture-turn-1", "delta": "늦은 조각"}})
        if MODE == "normal" or retried:
            send({"method": "item/agentMessage/delta", "params": {"threadId": CURRENT_THREAD_ID, "turnId": CURRENT_TURN_ID, "delta": "안녕"}})
        if MODE == "cancel-start-gated":
            # The server owns a live turn, but its id is deliberately unavailable to the client.
            marker = os.environ.get("DEEPK_TURN_START_MARKER")
            release = os.environ.get("DEEPK_TURN_START_RELEASE")
            if not marker or not release:
                sys.stderr.write("cancel-start-gated requires both marker and release paths\n")
                sys.exit(2)
            if marker:
                with open(marker, "w", encoding="utf-8") as handle:
                    handle.write(CURRENT_TURN_ID)
            deadline = time.monotonic() + 5
            while release and not os.path.exists(release) and time.monotonic() < deadline:
                time.sleep(0.001)
            if not os.path.exists(release):
                sys.stderr.write("cancel-start-gated release deadline expired\n")
                sys.exit(2)
        if MODE == "cancel-start-gated":
            # Record before publishing: absence of this line proves no response was sent yet.
            record_call("response/turn-start", CURRENT_TURN_ID)
        respond(request_id, {"turn": {"id": CURRENT_TURN_ID}})
        if MODE == "cancel":
            # Observing this callback proves that the client has installed the turn's handler.
            send({"method": "item/agentMessage/delta", "params": {"threadId": CURRENT_THREAD_ID, "turnId": CURRENT_TURN_ID, "delta": "진행 중"}})
        if MODE == "normal" or retried:
            send({"method": "item/agentMessage/delta", "params": {"threadId": CURRENT_THREAD_ID, "turnId": CURRENT_TURN_ID, "delta": "하세요"}})
        if MODE == "partial-cancel-once" and TURN_COUNT == 1:
            send({"method": "item/agentMessage/delta", "params": {"threadId": CURRENT_THREAD_ID, "turnId": CURRENT_TURN_ID, "delta": "원문"}})

        turn_start_marker = os.environ.get("DEEPK_TURN_START_MARKER")
        if turn_start_marker and MODE != "cancel-start-gated":
            with open(turn_start_marker, "w", encoding="utf-8") as handle:
                handle.write(CURRENT_TURN_ID)

        if MODE == "reject-server-request":
            send(
                {
                    "id": "fixture-server-request",
                    "method": "item/tool/requestUserInput",
                    "params": {"questions": []},
                }
            )
        elif MODE == "failure":
            send(
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": CURRENT_THREAD_ID,
                        "turn": {
                            "id": CURRENT_TURN_ID,
                            "status": "failed",
                            "items": [],
                            "error": {"message": "fixture failure"},
                        },
                    },
                }
            )
        elif MODE in ("normal", "late", "auth-error", "account-switch", "literal-echo") or IS_PREWARM or retried:
            text = "안녕하세요" if MODE in ("normal", "auth-error", "account-switch") or retried else ("첫 번째" if TURN_COUNT == 1 else "두 번째")
            if IS_PREWARM:
                text = "안녕하세요"
            if MODE == "literal-echo":
                prompt = message.get("params", {}).get("input", [{}])[0].get("text", "")
                captured = re.search(r"<source_text>\n(.*?)\n</source_text>", prompt, re.S)
                text = captured.group(1) if captured else "missing source"
                # Codex가 스킬 호출로 읽는 `$이름`이 그대로 오면 실패로 돌려준다(skills/src/mentions.rs).
                if re.search(r"\$[A-Za-z0-9_:\-]", text):
                    text = "skill mention reached Codex"
                # 링크·인라인 코드 지시가 실제 turn까지 왔는지 결과 앞에 표시한다.
                elif "numbered tags such as <a1>" in prompt:
                    text = "[inline] " + text
                for character in text:
                    send({"method": "item/agentMessage/delta", "params": {
                        "threadId": CURRENT_THREAD_ID, "turnId": CURRENT_TURN_ID, "delta": character}})
            send(
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": CURRENT_THREAD_ID,
                        "turn": {
                            "id": CURRENT_TURN_ID,
                            "status": "completed",
                            "items": [
                                {
                                    "id": "fixture-item",
                                    "type": "agentMessage",
                                    "text": text,
                                }
                            ],
                        },
                    },
                }
            )
        # 시간 초과·취소 모드는 turn/interrupt가 올 때까지 기다린다.
    elif method == "thread/unsubscribe":
        marker = os.environ.get("DEEPK_UNSUBSCRIBE_MARKER")
        if marker:
            with open(marker, "a", encoding="utf-8") as handle:
                handle.write(f"{message.get('params', {}).get('threadId', '')}\n")
        respond(request_id, {"status": "unsubscribed"})
        if MODE == "late" and TURN_COUNT == 1:
            send(
                {
                    "method": "item/agentMessage/delta",
                    "params": {
                        "threadId": CURRENT_THREAD_ID,
                        "turnId": "fixture-turn-1",
                        "itemId": "stale-item",
                        "delta": "stale",
                    },
                }
            )
            send(
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": CURRENT_THREAD_ID,
                        "turn": {
                            "id": "fixture-turn-1",
                            "status": "completed",
                            "items": [
                                {
                                    "id": "stale-item",
                                    "type": "agentMessage",
                                    "text": "오래된 결과",
                                }
                            ],
                        },
                    },
                }
            )
    elif method == "turn/interrupt":
        INTERRUPTED = True
        record_interrupt()
        respond(request_id, {})
        if MODE in ("cancel", "cancel-start-gated", "partial-cancel-once"):
            send(
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": CURRENT_THREAD_ID,
                        "turn": {
                            "id": CURRENT_TURN_ID,
                            "status": "interrupted",
                            "items": [],
                        },
                    },
                }
            )
    elif method == "account/login/start":
        respond(
            request_id,
            {
                "type": "chatgpt",
                "authUrl": "https://auth.example.test/login",
                "loginId": "fixture-login",
            },
        )
    else:
        respond(
            request_id,
            error={"code": -32601, "message": f"unknown fixture method {method}"},
        )

if MODE == "hold-old":
    # 재연결 경합을 재현하려고 표준 입력이 닫혀도 이전 출력 파이프를 잠시 유지한다.
    # 이전 연결의 EOF가 새 연결을 종료시키지 않는지 확인한다.
    time.sleep(1)
