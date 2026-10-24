#!/usr/bin/env python3
"""실제 계정을 사용하지 않는 Claude CLI 응답 모의 서버.

argv에 `--input-format stream-json`이 있으면 단일 사용 stream-json 프로세스처럼
동작하고, 없으면 기존 `--output-format json` one-shot 응답을 낸다.
"""

from __future__ import annotations

import json
import os
import signal
import sys
import time
from pathlib import Path


MODE = os.environ.get("DEEPK_CLAUDE_FIXTURE_MODE", "normal")
VERSION = os.environ.get("DEEPK_CLAUDE_FIXTURE_VERSION", "2.1.278")
ARGS_MARKER = os.environ.get("DEEPK_CLAUDE_ARGS_FILE")
ENV_MARKER = os.environ.get("DEEPK_CLAUDE_ENV_FILE")
START_MARKER = os.environ.get("DEEPK_CLAUDE_START_MARKER")
TERM_MARKER = os.environ.get("DEEPK_CLAUDE_TERM_MARKER")
INPUT_MARKER = os.environ.get("DEEPK_CLAUDE_INPUT_FILE")
EXIT_MARKER = os.environ.get("DEEPK_CLAUDE_EXIT_MARKER")
STREAM_MODE = os.environ.get("DEEPK_CLAUDE_STREAM_MODE") or MODE
STREAM_BOOT_DELAY = float(os.environ.get("DEEPK_CLAUDE_STREAM_BOOT_DELAY", "0") or "0")
DEFAULT_MODEL = "claude-haiku-5-5"

ARGS = sys.argv[1:]
IS_STREAM = "--input-format" in ARGS and ARGS[ARGS.index("--input-format") + 1 :][:1] == ["stream-json"]


def write_marker(path: str | None, value: str) -> None:
    if not path:
        return
    Path(path).write_text(value, encoding="utf-8")


def append_marker(path: str | None, value: str) -> None:
    if not path:
        return
    with Path(path).open("a", encoding="utf-8") as handle:
        handle.write(value)


def terminate(_signum: int, _frame: object) -> None:
    append_marker(TERM_MARKER, "terminated\n")
    if IS_STREAM:
        append_marker(EXIT_MARKER, "terminated\n")
    raise SystemExit(143)


signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)


def emit(value: object) -> None:
    sys.stdout.write(json.dumps(value, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def argument_value(flag: str) -> str | None:
    for index, argument in enumerate(ARGS):
        if argument == flag and index + 1 < len(ARGS):
            return ARGS[index + 1]
    return None


def fixture_arguments() -> dict[str, object]:
    values: dict[str, object] = {
        "argv": ARGS,
        "cwd": os.getcwd(),
        "mode": STREAM_MODE if IS_STREAM else MODE,
        "tools": argument_value("--tools"),
        "strict_mcp_config": "--strict-mcp-config" in ARGS,
        "mcp_config": argument_value("--mcp-config"),
        "setting_sources": argument_value("--setting-sources"),
        "settings": argument_value("--settings"),
        "model": argument_value("--model"),
        "no_session_persistence": "--no-session-persistence" in ARGS,
        "output_format": argument_value("--output-format"),
        "input_format": argument_value("--input-format"),
        "verbose": "--verbose" in ARGS,
        "include_partial_messages": "--include-partial-messages" in ARGS,
        "print": "-p" in ARGS,
        "safe_mode": "--safe-mode" in ARGS,
        "system_prompt": argument_value("--system-prompt"),
        "permission_mode": argument_value("--permission-mode"),
        "no_chrome": "--no-chrome" in ARGS,
    }
    return values


def write_atomically(path: str, text: str) -> None:
    """읽는 쪽이 비었거나 반쯤 쓴 파일을 보지 않도록 임시 파일을 rename한다."""
    temporary = Path(f"{path}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def record_launch() -> None:
    if ARGS_MARKER:
        write_atomically(ARGS_MARKER, json.dumps(fixture_arguments(), ensure_ascii=False, sort_keys=True))
    if ENV_MARKER:
        visible_environment = {
            key: os.environ[key]
            for key in (
                "ANTHROPIC_API_KEY",
                "ANTHROPIC_AUTH_TOKEN",
                "CLAUDE_CODE_USE_BEDROCK",
                "AWS_PROFILE",
                "ANTHROPIC_BASE_URL",
                "CLAUDE_CODE_OAUTH_TOKEN",
                "CLAUDE_CODE_OAUTH_REFRESH_TOKEN",
                "DISABLE_AUTOUPDATER",
                "CLAUDE_CODE_DISABLE_TERMINAL_TITLE",
                "CLAUDECODE",
                "CLAUDE_CODE_ENTRYPOINT",
                "CLAUDE_CODE_SESSION_ID",
                "CLAUDE_CODE_MESSAGING_SOCKET",
                "CLAUDE_CODE_EMIT_STARTUP_TIMING",
                "CLAUDE_CODE_DISABLE_ATTACHMENTS",
                "GITHUB_TOKEN",
                "OTEL_LOG_USER_PROMPTS",
                "HTTPS_PROXY",
                "NODE_EXTRA_CA_CERTS",
                "CLAUDE_CODE_CLIENT_CERT",
                "DISABLE_TELEMETRY",
                "LC_ALL",
                "VOLTA_HOME",
                "NODE_OPTIONS",
            )
            if key in os.environ
        }
        write_atomically(ENV_MARKER, json.dumps(visible_environment, ensure_ascii=False, sort_keys=True))


def hang() -> None:
    while True:
        time.sleep(0.1)


def translation_count() -> int:
    """이 fixture 묶음에서 메시지를 받은 프로세스 수(시작 마커의 translation 줄)."""
    if not START_MARKER or not Path(START_MARKER).exists():
        return 0
    return Path(START_MARKER).read_text(encoding="utf-8").splitlines().count("translation")


if "--version" in ARGS:
    append_marker(START_MARKER, "version\n")
    sys.stdout.write(f"{VERSION}\n")
    sys.stdout.flush()
    raise SystemExit(0)


if ARGS[0:2] == ["auth", "status"]:
    append_marker(START_MARKER, "auth\n")
    time.sleep(float(os.environ.get("DEEPK_CLAUDE_AUTH_DELAY", "0") or "0"))
    auth_mode = os.environ.get("DEEPK_CLAUDE_AUTH_MODE", "subscription")
    status: dict[str, object] = {
        "loggedIn": auth_mode != "logged-out",
        "authMethod": "claude.ai" if auth_mode == "subscription" else "api_key",
        "apiProvider": "firstParty",
        "subscriptionType": "max",
    }
    api_key_source = os.environ.get("DEEPK_CLAUDE_AUTH_API_KEY_SOURCE")
    if api_key_source:
        status["apiKeySource"] = api_key_source
    print(json.dumps(status))
    raise SystemExit(0)


# --- stream-json 단일 사용 프로세스 -------------------------------------------


def stream_event(event: dict[str, object]) -> dict[str, object]:
    return {"type": "stream_event", "event": event, "session_id": "fixture", "parent_tool_use_id": None}


def text_delta(text: str) -> dict[str, object]:
    return stream_event({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text}})


def message_start(model: str) -> dict[str, object]:
    return stream_event({"type": "message_start", "message": {"model": model, "role": "assistant", "content": []}})


def stream_result(model: str, result: str, model_usage: dict[str, object] | None = None, **extra: object) -> dict[str, object]:
    value: dict[str, object] = {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "duration_ms": 345,
        "duration_api_ms": 300,
        "ttft_ms": 120,
        "num_turns": 1,
        "result": result,
        "stop_reason": "end_turn",
        "session_id": "fixture",
        "usage": {"input_tokens": 481, "output_tokens": 3},
        "modelUsage": model_usage if model_usage is not None else {model: {}},
    }
    value.update(extra)
    return value


def wait_for_eof_and_exit(status: int = 0) -> None:
    """단일 사용 계약: result 뒤 stdin이 열려 있으면 다음 줄이나 EOF를 기다린다."""
    while True:
        line = sys.stdin.readline()
        if not line:
            append_marker(EXIT_MARKER, "eof\n")
            raise SystemExit(status)
        append_marker(START_MARKER, "second-message\n")


def validate_stream_flags() -> None:
    if argument_value("--output-format") != "stream-json":
        sys.stderr.write("Error: --input-format=stream-json requires output-format=stream-json.\n")
        raise SystemExit(1)
    if "--include-partial-messages" not in ARGS:
        sys.stderr.write("fixture: --include-partial-messages is required for streaming\n")
        raise SystemExit(1)
    if "--verbose" not in ARGS:
        sys.stderr.write("Error: When using --print, --output-format=stream-json requires --verbose\n")
        raise SystemExit(1)


def stream_main() -> None:
    validate_stream_flags()
    # args를 다 쓴 뒤 spawn을 알린다. 테스트가 spawn 마커를 보는 즉시 args를 읽기 때문이다.
    record_launch()
    append_marker(START_MARKER, "spawn\n")
    mode = STREAM_MODE
    model = argument_value("--model") or DEFAULT_MODEL

    if mode == "unsupported":
        sys.stderr.write("error: unknown option '--input-format'\n")
        raise SystemExit(1)
    if mode == "die-idle":
        # 살아 있지만 stdin을 더 읽지 않는 대기 프로세스다. 쓰기는 EPIPE가 되어야 한다.
        os.close(0)
        append_marker(START_MARKER, "idle-closed\n")
        time.sleep(1.0)
        sys.stderr.write("fixture idle crash\n")
        raise SystemExit(3)

    time.sleep(STREAM_BOOT_DELAY)
    line = sys.stdin.readline()
    if not line:
        append_marker(EXIT_MARKER, "eof\n")
        raise SystemExit(0)
    if INPUT_MARKER:
        append_marker(INPUT_MARKER, json.dumps({"transport": "stream", "line": line.rstrip("\n")}, ensure_ascii=False) + "\n")
    message = json.loads(line)
    if message.get("type") != "user" or message.get("message", {}).get("role") != "user":
        sys.stderr.write("Error: Expected message role 'user'\n")
        raise SystemExit(1)
    append_marker(START_MARKER, "translation\n")

    if mode in {"timeout", "cancellation"}:
        hang()
    if mode == "early-exit":
        sys.stderr.write("fixture setup crash\n")
        raise SystemExit(1)

    init_source = os.environ.get("DEEPK_CLAUDE_INIT_API_KEY_SOURCE") or (
        "ANTHROPIC_API_KEY" if mode == "api-key" else "none"
    )
    emit(
        {
            "type": "system",
            "subtype": "init",
            "cwd": os.getcwd(),
            "session_id": "fixture",
            "tools": [],
            "mcp_servers": [],
            "model": model,
            "permissionMode": "dontAsk",
            "apiKeySource": init_source,
            "claude_code_version": VERSION,
        }
    )
    if mode == "api-key":
        # 실제 CLI처럼 요청은 계속 진행하지만 클라이언트가 init에서 종료해야 한다.
        time.sleep(0.2)

    if mode == "malformed":
        sys.stdout.write("not-json\n")
        sys.stdout.flush()
        raise SystemExit(0)

    emit({"type": "system", "subtype": "status", "status": "requesting", "session_id": "fixture"})

    if mode == "control-request":
        emit({"type": "control_request", "request_id": "fixture-1", "request": {"subtype": "can_use_tool", "tool_name": "Bash"}})
        response_line = sys.stdin.readline()
        try:
            response = json.loads(response_line)
            subtype = response["response"]["subtype"]
            request_id = response["response"]["request_id"]
        except (ValueError, KeyError, TypeError):
            subtype, request_id = "invalid", ""
        append_marker(START_MARKER, f"control-response {subtype} {request_id}\n")

    if mode == "auth-error":
        emit(
            {
                "type": "assistant",
                "error": "authentication_failed",
                "message": {"role": "assistant", "content": [{"type": "text", "text": "Not logged in · Please run /login"}]},
                "parent_tool_use_id": None,
            }
        )
        emit(
            {
                "type": "result",
                "subtype": "success",
                "is_error": True,
                "result": "Authentication required: log in to Claude Code with a Pro or Max subscription.",
                "api_error_status": 401,
                "modelUsage": {},
            }
        )
        wait_for_eof_and_exit(1)

    if mode == "model-error":
        # 실제 CLI처럼 assistant 오류 분류와 is_error result를 함께 낸다.
        emit(
            {
                "type": "assistant",
                "error": "model_not_found",
                "message": {"role": "assistant", "content": [{"type": "text", "text": "Unknown model requested"}]},
                "parent_tool_use_id": None,
            }
        )
        emit({"type": "result", "subtype": "success", "is_error": True, "result": "Unknown model requested", "modelUsage": {}})
        wait_for_eof_and_exit(1)
    if mode == "setup-error":
        emit({"type": "result", "subtype": "error_during_execution", "is_error": True, "errors": ["turn setup failed"]})
        wait_for_eof_and_exit(1)
    if mode == "rate-limit":
        emit({"type": "rate_limit_event", "rate_limit_info": {"status": "rejected", "rateLimitType": "five_hour"}})
        emit(
            {
                "type": "assistant",
                "error": "rate_limit",
                "message": {"role": "assistant", "content": [{"type": "text", "text": "You've hit your limit · resets 5pm"}]},
                "parent_tool_use_id": None,
            }
        )
        emit({"type": "result", "subtype": "success", "is_error": True, "result": "You've hit your limit · resets 5pm", "modelUsage": {}})
        wait_for_eof_and_exit(1)

    emit(message_start(model))
    emit(stream_event({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}))

    if mode == "partial-hang-once" and translation_count() == 1:
        # 첫 번역만 조각 하나를 보내고 멈춘다(스트리밍 중 취소). 다음 프로세스는 정상으로 끝난다.
        emit(text_delta("원문"))
        hang()

    if mode == "failure":
        emit(text_delta("안"))
        sys.stderr.write("fixture translation failed\n")
        sys.stderr.flush()
        raise SystemExit(7)
    if mode == "no-result":
        emit(text_delta("안"))
        raise SystemExit(0)
    if mode == "retry-reset":
        emit(text_delta("잘못"))
        emit({"type": "system", "subtype": "api_retry", "attempt": 1, "max_retries": 10, "error": "overloaded"})
        emit(message_start(model))

    if mode == "empty":
        emit(stream_result(model, ""))
        wait_for_eof_and_exit()

    for chunk in ("안", "녕", "하세요"):
        emit(text_delta(chunk))
    emit(
        {
            "type": "assistant",
            "message": {"model": model, "role": "assistant", "content": [{"type": "text", "text": "안녕하세요"}]},
            "parent_tool_use_id": None,
            "session_id": "fixture",
        }
    )
    emit(stream_event({"type": "content_block_stop", "index": 0}))
    emit(stream_event({"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 3}}))
    emit(stream_event({"type": "message_stop"}))
    emit({"type": "keep_alive"})
    emit({"type": "rate_limit_event", "rate_limit_info": {"status": "allowed", "rateLimitType": "five_hour"}})
    emit({"type": "future_unknown_type", "value": 1})

    usage = {"claude-sonnet-5": {}} if mode == "model-mismatch" else None
    emit(stream_result(model, "안녕하세요", usage))
    wait_for_eof_and_exit()


if IS_STREAM:
    stream_main()
    raise SystemExit(0)


# --- 기존 one-shot JSON 경로 --------------------------------------------------

record_launch()
append_marker(START_MARKER, "translation\n")
if INPUT_MARKER:
    content = sys.stdin.read()
    append_marker(INPUT_MARKER, json.dumps({"transport": "json", "content": content}, ensure_ascii=False) + "\n")


if MODE in {"timeout", "cancellation"}:
    hang()

if MODE == "malformed":
    sys.stdout.write("not-json\n")
    sys.stdout.flush()
    raise SystemExit(0)

if MODE == "auth-error":
    emit(
        {
            "type": "result",
            "subtype": "error_during_execution",
            "is_error": True,
            "result": "Authentication required: log in to Claude Code with a Pro or Max subscription.",
        }
    )
    raise SystemExit(1)

if MODE == "failure":
    sys.stderr.write("fixture translation failed\n")
    sys.stderr.flush()
    raise SystemExit(7)

if MODE == "empty":
    emit({"type": "result", "subtype": "success", "is_error": False, "result": ""})
    raise SystemExit(0)

if MODE == "model-error":
    emit(
        {
            "type": "result",
            "subtype": "error_during_execution",
            "is_error": True,
            "result": "Unknown model requested",
        }
    )
    raise SystemExit(1)

emit(
    {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "result": "안녕하세요",
        "duration_ms": 345,
        "duration_api_ms": 300,
        "ttft_ms": 120,
        "modelUsage": {argument_value("--model") or DEFAULT_MODEL: {}},
    }
)
