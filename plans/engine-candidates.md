# 번역 엔진 후보 조사

조사일: 2026-09-19
상태: **Codex/ChatGPT 구독과 Claude Code/Claude 구독** 연결을 구현해 main에 반영했다. 새 설치의 기본값은 Codex Luna다. Claude 모델은 기본 Haiku 5.5이고 Sonnet 5.5·Opus 5.5·Fable 5.1을 고를 수 있다(2026-10-08, PR #48). Codex는 기존 사용자 모델 선택을 보존하고, Claude는 선택지에 없는 저장값(Haiku 4.5 등)을 기본값으로 되돌린다. 각 구독 연결·모델 실측과 제공자 선택 UI는 2026-09 구현 때 확인했다. PR #48에서 늘린 모델 4개가 설정 화면에 보이는지와 실제 앱 번역은 확인하지 않았다.

## 후보

현재 계정에 대한 읽기 전용 `account/read`·`model/list` 확인(`codex-cli 0.154.0`, `account.type: chatgpt`)에서 다음 모델을 확인했다. 이는 현재 계정의 가용성만 보여 주며 속도·품질 측정 결과가 아니다.

| 모델 | 현재 카탈로그 설명·설정 | 역할 |
| --- | --- | --- |
| `gpt-5.6-luna` | “Fast and affordable agentic coding model”; `low` 추론과 `fast` 계층 지원 | 첫 후보 |
| `gpt-5.6-terra` | “Balanced agentic coding model for everyday work”; `low` 추론과 `fast` 계층 지원 | 균형 비교 |
| `gpt-5.6-sol` | “Latest frontier agentic coding model”; `low` 추론과 `fast` 계층 지원 | 품질 상한 비교 |

`fast`·`balanced`·`frontier`는 제공자 설명이다. 측정 전 최속을 주장하지 않으며, 구현 시 `model/list`와 `supportedReasoningEfforts`를 읽어 모델을 선택한다. 기본 측정은 `low` 추론·일반 서비스 계층으로 시작한다. `fast`/`priority` 계층은 사용량이 늘 수 있으므로 별도 조건으로만 기록한다.

## 인증과 app-server 경계

- 앱은 `codex app-server`를 **stdio JSON-RPC 프로세스로 한 번 실행해 유지**한다. 요청마다 CLI 프로세스를 새로 만들면 1초 목표에 프로세스 기동 비용이 반복되기 때문이다.
- 연결마다 `initialize` → `initialized`를 먼저 보내고, `thread/start` 또는 `thread/fork` 뒤 `turn/start`를 호출한다. 전체 번역 결과가 도착하고 `turn/completed`가 된 시점을 완료로 본다.
- `account/login/start`의 `type: "chatgpt"`는 브라우저 OAuth, `chatgptDeviceCode`는 기기 코드 로그인을 시작한다. `account/read`에서 인증 방식과 가능한 `planType`을 확인한다.
- 인증 토큰·로그인 캐시를 앱이 읽거나 추출하지 않는다. Codex가 관리하는 로그인·갱신·저장 경로를 사용한다.
- 현재 공식 문서는 app-server를 실험적이며 프로덕션 워크로드에 지원되지 않는 기능으로 설명한다. 개인용 로컬 앱의 검증 경계로 남기며 안정적인 공개 배포 계약으로 표시하지 않는다.

현재 CLI 0.154.0에서 생성한 app-server v2 스키마에는 `ThreadStartParams`/`ThreadForkParams`의 `developerInstructions`, `model`, `cwd`, `ephemeral`이 있다. 번역용 ephemeral thread와 전용 빈 `cwd`를 사용해 저장소의 `AGENTS.md`, 코드, 이전 번역이 요청에 섞이지 않게 한다. `sandbox`는 읽기 전용으로 설정하고 번역에 불필요한 도구를 비활성화한다. 읽기 전용만으로 도구 실행이 차단된다고 가정하지 않고 실제 프로토콜과 설정으로 검증한다.

초기 조사 때 정한 개발자 지시는 다음과 같다.

> Translate the supplied source text to the requested target language. Return only the translation. Preserve paragraph and list breaks, code, numbers, units, dates, names, negation, conditions, and request IDs. Do not explain the translation or perform file or shell actions.

이후 변경: 현재 지시는 `CodexTranslationClient.translationDeveloperInstructions`에 있다. 원문을 지시가 아닌 데이터로 다루라는 문구는 첫 구현부터 들어갔고, 독립된 코드·셸 명령을 언어 태그 펜스로 감싸는 규칙은 PR #49에서 개발자 지시와 turn 프롬프트에 더했다. 링크·인라인 코드가 있는 요청에만 turn 프롬프트(`translationPrompt`)에 링크 번호 태그·백틱 유지 지시를 덧붙인다(PR #53).

품질 표본은 [`benchmarks/translation-samples.json`](../benchmarks/translation-samples.json)의 10개 입력을 사용한다. 중대 오류는 의미 반전, 부정·조건·시점 변경, 누락·추가, 숫자·단위·날짜·코드·요청 ID 변경, 목표 언어가 아닌 답변이다. **중대 오류 0건**, 전체 10개 중 **8개 이상 사용 가능**, 양방향 각각 **4개 이상**을 초기 합격선으로 제안한다.

## 지연과 사용량 측정

- **app-server cold**: 서버 프로세스 시작·ChatGPT 로그인 확인·JSON-RPC 초기화·스레드 준비를 분리해 기록한다.
- **app-server warm**: 유지된 연결에서 `turn/start`부터 `turn/completed`까지 잰다. 첫 토큰이나 부분 출력은 보조 지표다.
- **앱 전체**: 두 번째 ⌘C 감지부터 클립보드 갱신, 요청, 전체 번역문 UI 반영까지 잰다. 엔진 단독 시간과 분리한다.
- 모델 ID, 추론 강도, 서비스 계층, CLI/app-server 버전, ChatGPT 플랜, 네트워크, `cwd`를 결과에 남긴다.
- 기존 계획의 후보·방향·분량별 30회 반복을 적용하되, 사용량 제한으로 중단하면 실제 횟수와 오류를 기록한다. 오류·타임아웃은 1초 성공률 분모에서 빼지 않는다.
- 이 경로에는 직접 API의 USD/토큰 단가를 적용하지 않는다. `account/rateLimits/read`의 `usedPercent`, 창구 길이, `resetsAt`과 `account/usage/read`를 반복 전후에 기록한다. 제한 도달 시 직접 API로 자동 전환하지 않는다.

현재 1초 목표는 **두 번째 ⌘C부터 전체 번역문 UI 표시까지의 앱 전체 p95 제안값**이다. 모델 설명만으로 목표 달성을 표시하지 않는다.

## 공식 OpenAI 문서

- [Codex app-server와 JSON-RPC 흐름](https://developers.openai.com/ja-JP/docs/app-server)
- [Codex CLI 로그인 및 로컬 사용](https://developers.openai.com/codex/cli)
- [Codex 인증과 ChatGPT 로그인](https://learn.chatgpt.com/zh-Hans/docs/auth)
- [Codex 설정 예시와 `developer_instructions`](https://learn.chatgpt.com/es-419/docs/config-file/config-sample)
- [Codex app-server의 실험적·비지원 경계](https://developers.openai.com/ja-JP/docs/app-server)

## 다음 goal의 제공자별 모델 정의 — 2026-09-19

| 연결 경로 | 다음 기본 모델 | 실행 정책 | 현재 상태 |
| --- | --- | --- | --- |
| Codex / ChatGPT 구독 | `gpt-5.6-luna` | 표준 서비스 계층, app-server가 지원하는 최소 추론 수준(기존 확인은 low) | 연결 구현됨. Luna 기본값 적용. 기존 저장 선택은 보존하며 실제 로컬 앱도 Luna 선택 확인 |
| Claude Code / Claude 구독 | Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) | 빠른 번역 우선. 확장 사고 끔. 미리 띄운 단일 사용 stream-json 프로세스와 스트리밍 표시(2026-10-03) | 어댑터 구현 및 구독 실측 완료. 앱 전용 CLI 2.1.278이 없으면 전역 CLI 사용(2026-10-03 측정 2.1.287) |
| Claude 품질 비교 후보 | Claude Sonnet 5 (`claude-sonnet-5`) | Haiku 품질 미달 문장에서 비교. 사용자 선택으로 사용하며 자동 승격하지 않음 | 최신 문서의 후보이며 로컬 CLI·계정 지원은 별도 확인 |

2026-10-08 갱신(PR #48): 위 표의 Haiku 4.5와 Sonnet 5는 당시 정의이며 지금 선택지에 없다. 현재 선택지(문서 머리의 상태 참고)는 `TranslationProvider.fixedModels`에 있고 첫 항목 `claude-haiku-5-5`가 기본이다. CLI에는 사용량 없이 모델 목록을 읽는 명령이 없어 고정 목록으로 관리한다. CLI 2.1.293에서 네 모델 ID 모두 `modelUsage`에 요청한 모델 하나만 남는 것을 확인했다. 터미널 제목 생성이 Haiku를 한 번 더 부르지 않도록 `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`을 설정한다. 비교 근거는 [Haiku 4.5 ↔ 5.5](../benchmarks/haiku-45-vs-55-summary.md)에 있다.

Luna는 사용자 선택에 따른 다음 기본값이다. 기존 파일럿에서 Terra 중앙값이 더 낮았으므로 Luna가 이미 더 빠르다고 주장하지 않는다. API 문서에는 Luna의 none 추론이 있지만, 구독 app-server의 지원 목록과 같다고 가정하지 않는다. Fast 계층은 기본 사용하지 않는다. 개발용 서브에이전트 Luna Max와 앱 번역 모델의 최소 추론 설정을 구분한다.

다음 작업:

- [x] Luna 기본값을 한 곳에서 관리하고 기존 저장된 Terra/사용자 선택의 전환 정책을 명시한다. 화면에 실제 제공자·모델을 표시해 코드 기본값과 저장값이 다른 문제를 방지한다.
- [x] Claude Code의 공식 지원 호출·구독 인증 경로와 계정의 Haiku 접근을 확인한다. 설치만으로 구독 사용 가능을 단정하지 않으며 토큰을 추출하지 않는다.
- [x] Claude 번역 어댑터와 제공자 선택을 추가한다. 제공자별 모델·연결 상태를 저장하고 변경 시 진행 요청과 이전 결과를 무효화한다.
- [x] 도구·MCP·프로젝트 문맥·세션 저장을 번역에서 제외하는 실제 실행 설정을 검증한다. 요청 취소·오류·지연 계측을 Codex와 같은 계약으로 구현한다.
- [x] 동일한 한영/영한 표본으로 Luna와 Haiku의 첫 요청·반복 요청 지연, 누락·부정·숫자·기술 용어 보존을 비교한다. 모델 응답과 CLI 시작 비용을 분리한다.
- [x] 제공자 간 자동 전환·유료 API 전환·두 모델 동시 요청은 하지 않는다. 모델 접근 불가/한도 초과는 안내하고 사용자가 선택하게 한다.

공식 확인 자료:

- [GPT-5.6 Luna 모델](https://developers.openai.com/api/docs/models/gpt-5.6-luna): 대량·비용 민감 작업용 모델. API 사양과 구독 가용성은 구분한다.
- [Claude Code 모델 설정](https://code.claude.com/docs/en/model-config): 모델 지정과 추론 설정. 최신 문서 기능을 구버전 CLI가 지원한다고 가정하지 않는다.
- [Claude Code 모델·사용량](https://support.claude.com/en/articles/14552983-models-usage-and-limits-in-claude-code): Haiku는 속도 우선 후보. 실제 번역 적합성은 별도 측정한다.

## 설정: 기본 번역 제공자 선택

현재 설정에는 Codex 모델 선택만 있고 Codex/Claude Code 선택은 없다. 여기서 연결 가능 여부는 각 제공자의 로그인·모델 사용 가능 상태이며, macOS 입력 모니터링·접근성 권한과 구분한다.

- [x] 설정에 **기본 번역 제공자** 선택을 추가한다: `Codex · GPT-5.6 Luna` / `Claude Code · Haiku 4.5`. 실제 모델을 변경했다면 해당 모델명을 표시한다.
- [x] 둘 다 연결되었을 때 저장된 사용자 선택을 우선한다. 초기 기본값은 기존 사용 경로인 Codex이며, 새 제공자 로그인이나 연결 완료 순서가 선택을 바꾸지 않는다.
- [x] 제공자별 로그인/연결/모델 사용 가능 상태를 표시하고, 선택값과 제공자별 모델 설정을 재실행 후에도 유지한다. Claude만 사용 가능한 경우에도 선택할 수 있게 한다.
- [x] 기본 제공자를 사용할 수 없으면 재연결 또는 다른 제공자 선택을 안내한다. 다른 계정으로 몰래 전송하거나 두 제공자에 동시에 요청하지 않는다.
- [x] 제공자 변경 시 기존 요청·대기·결과를 무효화한다. 기존 원문은 유지하고 새 제공자로 번역할 수 있도록 연결하며, 연결 준비와 IME 조합 중에는 중복 요청을 막는다.
- [x] 각 요청에 제공자·모델을 고정하고 결과에도 실제 처리한 제공자·모델을 표시한다. 이전 제공자의 늦은 응답이 새 결과를 덮지 못하게 한다.

완료 기준: 양쪽 연결 상태에서 각 제공자를 선택하면 해당 제공자로만 한 번 요청한다. 재실행 후 선택 유지, 선택한 제공자 연결 실패, 요청 중 제공자 변경, 연결 순서 변경을 검증한다. macOS 권한 상태와 번역 제공자 선택은 서로 독립적이다.

## 구현·검증 결과 — 2026-09-19

공식 Claude CLI의 auth status에서 claude.ai / firstParty / 유효한 구독 종류를 확인한 뒤에만 요청한다. 환경의 API/클라우드 인증 경로를 전달하지 않고, safe mode·빈 MCP·도구 차단·별도 cwd·세션 비저장을 사용한다. 원문은 stdin으로 전달하며 응답 modelUsage가 요청한 Haiku 모델인지 확인한다. 설정 시트에서 프로세스 종료 통지가 지연되던 문제는 전용 스레드의 실행/종료 대기로 수정했다. 전역 설치는 바꾸지 않고 scripts/setup-claude.sh가 앱 전용 CLI를 준비한다.

같은 짧은 표본 3개: Luna 3.62–4.85초, Haiku 2.39–2.50초. 추가 한영/영한 10개: 10/10 성공, 중앙값 약 2.92초, 범위 약 2.64–5.34초. fixture 체크 대조에서 중대 오류는 발견하지 못했고 인과 표현이 덜 직접적인 문장은 기록했다. 1초 미달이며 보편적 최속/품질 보증이 아니다. 근거는 benchmarks/runs의 20260919 JSON 세 개다.

## Claude 대기 프로세스·스트리밍 — 2026-10-03

단문 약 2.4초 중 모델 시간은 약 0.8초(`duration_ms`)였고 약 1.5초는 번역마다 `claude -p`를 새로 띄우고 종료하는 비용이었다. 같은 모델·시스템 프롬프트·사용자 프롬프트를 유지한 채 이 비용을 번역 경로 밖으로 옮겼다.

- `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages`에 기존 격리 플래그를 그대로 붙인 프로세스를 하나 미리 띄운다. stream-json 입력은 첫 메시지 전에 설정·인증 준비를 끝내며, text 입력은 stdin EOF까지 기다려 미리 띄울 수 없다. `--bare`는 OAuth를 읽지 않아 쓰지 않는다.
- 번역마다 사용자 메시지 한 줄만 쓰고 `result` 줄에서 확정한 뒤 stdin을 닫아 은퇴시킨다. 한 프로세스는 한 번만 써서 이전 번역이 문맥에 섞이지 않는다. 교체 프로세스는 결과 뒤에 띄운다. `text_delta`는 누적해 화면에 이어 표시하고 최종 값은 `result.result`를 쓴다.
- 메시지를 쓴 뒤 stdout이 전혀 없을 때만 기존 단발 json 경로로 다시 보낸다. 그 밖의 실패는 이미 요청이 나갔을 수 있어 재전송하지 않는다. CLI 인자 오류면 세션 동안 stream을 끈다. `claudeTransport=oneShotJSON`은 기존 방식으로 되돌리는 비상 스위치다.
- 구독 확인(사용자 결정): 번역 창 사용 중 약 25초마다 백그라운드에서 `auth status`를 갱신하고, 30초 안에 시작해 성공한 확인이 있을 때만 보낸다. 매 번역의 init `apiKeySource`가 `none`이나 확인 시점의 출처가 아니면 즉시 중단하고 확인을 무효화한다. 시각은 잠자기를 포함하는 `ContinuousClock`으로 잰다.
- 대기 프로세스는 최대 1개(유휴 RSS 약 211MB, CPU 약 0%)이며 10분, 30분 무활동, 제공자·모델 변경, 연결 해제, 잠자기, 종료 때 정리한다. 활동은 번역, 두 번째 ⌘C, 창 표시, 입력만 센다. 첫 ⌘C는 모든 앱의 복사라 쓰지 않는다.

검증(CLI 2.1.287, Haiku 4.5):

- 메시지 없이 45초 둔 대기 프로세스는 stdout 0바이트, debug 로그의 모델 요청·`quota_check`·`model-check` 0건이었다. 부모가 강제 종료되면 stdin EOF로 스스로 종료했다.
- 같은 세션 교차 60건([결과](../benchmarks/runs/20261003-haiku-warm-spare-ab.json)): 기존 단문 p50 2.3–2.7초 → 0.8–1.1초, 문단 2.5–2.7초 → 1.0–1.3초, 긴 글 3.7–4.7초 → 2.0–3.5초, 첫 글자 0.6–0.8초. CLI 오버헤드 p50은 약 1.43–1.51초 → 0.03–0.05초. 10개 표본 모두 두 경로 중대 오류 0건, 사용 가능 10/10.
- 사용 패턴 35건([결과](../benchmarks/runs/20261003-haiku-warm-spare-usage.json), 48건 계획 중 도구 시간 제한으로 중단): 같은 증명 재사용 정책의 단발 json 2.17–2.47초, 90초 유휴 뒤 0.79–1.07초, 300초 유휴 뒤 0.91–1.24초, 직후 연속 요청 1.36–1.76초, 대기 프로세스 없는 stream 1.29–1.68초. 모두 성공했다.
- 오프라인 `./scripts/test.sh`(가짜 CLI로 stream·fallback·증명·취소·수명 검사)와 Xcode 빌드가 통과했다.

미확인: 실제 앱의 두 번 복사 전체 지연(`com.deepk.app` latency 로그로 측정 가능), 실제 잠자기·깨우기 뒤 첫 번역, 앱 전용 CLI 2.1.278에서의 stream 동작(실패 시 단발 경로로 자동 전환).

## 공개 전 보안 점검 — 2026-10-12

PR #52에서 위 격리 설정(safe mode·빈 MCP·도구 차단·별도 cwd)만으로는 막히지 않는 경로를 찾아 막았다.

- Claude: CLI가 원문의 `@경로`를 모델 호출 전에 파일 첨부로 펼쳤다(2.1.295에서 재현). `--tools ""`·`--safe-mode`와 별개의 경로라서, 설정값을 적용한 뒤에 `CLAUDE_CODE_DISABLE_ATTACHMENTS=1`을 강제한다.
- Codex: 원문의 `$이름`·`[$이름](경로)`을 설치된 스킬 호출로 읽고, 해당 SKILL.md를 turn에 넣는다. `skills.include_instructions=false`와는 무관하다. 그래서 `$` 뒤에 U+2060을 넣어 보내고 결과에서 되돌린다. 실제 Codex 요청 캡처로 SKILL.md가 들어가지 않는 것까지는 확인하지 않았다.
- 실행 환경: 전에는 Codex에 부모 환경 전체를, Claude에 Anthropic·클라우드 인증값만 뺀 환경을 넘겼다. 이제 두 CLI 모두 `inheritedEnvironmentKeys`와 `LC_*`만 넘긴다. Claude는 그 뒤에도 API·클라우드 인증값을 지운다.
- 비밀번호 관리자가 숨김·임시 표시를 붙인 복사는 ⌘C 두 번에서 번역하지 않는다. 표시가 먼저 있으면 문자열을 읽지 않고, 늦게 붙는 표시는 다음 poll(10ms)에서 확정 전에 거절한다.

허용 목록은 [README](../README.md#보내는-내용과-실행-환경)에, 전체 점검 결과는 [공개 전 보안 점검](public-release-security.md)에 있다.
