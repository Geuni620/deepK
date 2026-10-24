# Codex 번역 후속 개선: 실행 파일 탐색·주입 프롬프트 정리·Fast 선택

상태: 2026-10-06 계획 수립·검토, 2026-10-07 구현과 오프라인 검증 완료. [PR #44](https://github.com/Geuni620/deepK/pull/44)로 PR #42 브랜치에 머지했고, PR #42와 함께 main에 반영했다(2026-10-07, `865ca79`). 실측과 실제 앱 확인은 아래 10절에 기록한다.
- [PR #42](https://github.com/Geuni620/deepK/pull/42)(대기 스레드, `codex/codex-translation-prewarm`, `84a24f0`) 위에 쌓은 후속 PR이다. PR #44를 PR #42 브랜치에 먼저 머지해 7절의 base 변경 절차는 필요 없어졌다.
- 범위는 사용자와 합의한 세 작업(A: 실행 파일 탐색, B: 주입 프롬프트 정리, C: Fast 선택)이다. 계측 보강과 사용 한도 안내는 사용자 결정으로 제외했다.
- 계획 검토는 세 관점(탐색, config 키, Fast·테스트)으로 나눠 코드와 `openai/codex` 소스(rust-v0.155.0·v0.160.0)를 대조했고, 결과를 통합 검증해 반영했다.
- 2026-10-07 사용자 결정: Codex 버전 고정 스크립트(`setup-codex.sh`)는 넣지 않는다. 평소에는 탐색으로 최신 Codex를 쓰고, 업데이트로 문제가 생기면 `codexExecutablePath`로 검증된 버전을 직접 지정한다.

## 1. 배경

2026-10-06 진단(실측 trace, 가짜 서버 요청 캡처, `openai/codex` 소스 추적)에서 확인한 사실이다.

| 항목 | 값 | 근거 |
| --- | --- | --- |
| 현재 main의 Codex 단문 | 약 3.1–3.4초 | trace 2건(0.155.0, Fast) |
| PR #42 대기 스레드 적용 후 단문 | 중앙값 2,054.6ms(이전 4,123.6ms) | `benchmarks/runs/20261004-codex-prewarm-ab.json` |
| 대기 스레드로도 남는 Codex 내부 대기 | 약 0.38초 | 새 스레드의 첫 turn에서 git-attribution 확장이 `GET /backend-api/wham/settings/user`를 await한다. 캐시가 스레드 단위라 새 스레드마다 다시 조회하고, 끄는 설정이 없다(`ext/git-attribution/src/lib.rs:40-61`, `policy.rs:71-74`, `app-server/src/extensions.rs:90`@rust-v0.160.0). 로컬 로그 DB 기준 첫 turn 중앙값 380ms(n=125), 같은 스레드의 이후 turn 18.7ms(n=76) |
| 단문 한 건의 요청 본문 | 46,739B(입력 약 10.5k 토큰). 번역 지시와 원문은 약 0.2KB | Codex가 자동으로 붙이는 내용: 개인 메모리 16.5KB, 스킬 설명 14.6KB, 코딩 도구 정의 약 10.7KB(goal 도구 3종 3.0KB 포함), 전역 AGENTS.md 0.9KB, 환경·권한 안내 약 0.9KB. `memory_summary.md`의 40자 이상 줄 72개가 모두 들어 있었다 |
| 주입 차단 설정을 적용한 본문 | 11,184B, 메모리 줄 0개 | 같은 방법의 캡처. `features.goals=false`, `features.hooks=false`를 포함한 설정이다. goals를 빼면 goal 도구 3종이 남아 약 14.2KB가 된다 |
| Fast(priority) 계층 | 2026-09-30 PR #38부터 모든 번역에 기본 적용 | 단문 출력이 12–14토큰이라 생성 속도 1.5배의 이득이 거의 없다. 사용량은 늘어난다. 카탈로그 설명: "1.5x speed, increased usage". 이전 1회 측정: 4.72초 vs 4.41초 |
| 실행 파일 탐색 | `open`으로 실행한 앱에서 실패 | 아래 2절 |

**목표**

1. Codex 설치 위치나 ChatGPT.app 업데이트와 무관하게 Codex를 찾는다. 실제로 쓰는 경로와 버전을 보여 준다.
2. 번역 스레드에서만 Codex의 코딩용 자동 주입을 끈다. 개인 메모리 전송을 멈추고 사용량을 줄인다. deepK의 번역 지시와 원문은 바꾸지 않는다.
3. Fast를 기본으로 끄고 설정에서 켤 수 있게 한다.

**예상 효과(추정, 실측으로 확정)**
- 단문 약 1.8–2.0초, 번역당 사용량 약 1/4–1/3.
- Fast를 끄면 긴 글이 0.5–1.0초 느려질 수 있다. 토글로 되돌릴 수 있다.
- git-attribution 0.38초는 deepK에서 줄일 수 없다.

## 2. 기반 브랜치에서 확인한 코드 위치

기준 커밋 `84a24f0`(PR #42).

| 위치 | 현재 동작 | 문제 |
| --- | --- | --- |
| `CodexTranslationClient.swift:1071-1105` `resolveLaunchTarget` | `configuration.executableURL` → 환경변수 → 고정 후보 → 없으면 `/usr/bin/env codex`. 고정 후보: `~/.npm-global/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/Applications/ChatGPT.app/Contents/Resources/codex` | ChatGPT.app의 CLI가 `Contents/Resources/codex-cli/` 아래로 옮겨져 고정 후보가 모두 없다. `open`으로 실행하면 PATH가 `/usr/bin:/bin:/usr/sbin:/sbin`이라 `env: codex: No such file or directory`(exit 127)로 실패한다 |
| `CodexTranslationClient.swift:1108-1125` `nativeCodexExecutable` | npm 래퍼(`codex.js`)를 플랫폼 네이티브 바이너리로 바꾼다 | 유지 |
| `CodexTranslationClient.swift:360` | `private let configuration` | 클라이언트를 만든 뒤에는 설정을 바꿀 수 없다 |
| `CodexTranslationClient.swift:387-418, 524-529` | `PreparedThread`, `setPrewarm`, `claimPreparedThread`가 모델만 비교한다 | 계층이 바뀌어도 이전 대기 스레드를 그대로 쓴다 |
| `CodexTranslationClient.swift:544`, `:796` | 스레드 `serviceTier: "priority"`, turn `serviceTierForTurn: "priority"` 고정 | Fast가 항상 켜져 있다 |
| `CodexTranslationClient.swift:949-980` `translationConfig` | 적용 중: MCP 서버별 비활성화, `project_doc_max_bytes: 0`, apps 비활성화(`default_tools_enabled` 포함), `service_tier: "default"`, web_search 끔, features 6개 끔 | 메모리·스킬·goal·환경 안내는 그대로 주입된다. `apps._default.default_tools_enabled`는 0.155에서도 `AppsDefaultConfig`에 없는 키라 원래 효과가 없었고, 0.160부터 알 수 없는 키로 configWarning을 낸다 |
| 프로세스 인자 `--disable` 6개(`Configuration` 기본값) | shell_tool, apps, multi_agent, code_mode_host, computer_use, plugins를 끈다 | 유지. 스레드 `config.features` 객체는 이 값을 통째로 대체하므로(`config/src/overrides.rs`, `merge.rs:63-70`@rust-v0.160.0) 스레드 쪽에도 6개를 모두 다시 적어야 한다 |
| `AppModel.swift:85-88` | Codex 클라이언트에 실행 경로를 넘기지 않는다 | Claude 쪽은 `claudeExecutablePath`를 읽는다(:90) |
| `FinalSettingsView.swift:411-433` | Codex가 연결된 상태의 메뉴에는 '연결 해제'와 '로그아웃'만 있다 | 연결 중에는 '연결 확인'으로 다시 탐색할 수 없다 |

이 Mac의 실제 설치 상태(2026-10-06):

- **ChatGPT.app:** 번들 ID는 `com.openai.codex`이다. `Contents/Resources/codex-cli/` 안에 `codex-package.json`(layoutVersion 1, entrypoint `bin/codex`, version)이 있다. `bin/codex`는 셸 래퍼이고 `CodexCLI.app/Contents/MacOS/codex`를 실행한다. 버전은 0.160.0이며 앱과 함께 자동 업데이트된다. LaunchServices에는 휴지통의 이전 사본도 등록되어 있다.
- **nvm:** Node 버전마다 다른 Codex가 있다(0.136.0, 0.137.0, 0.142.5 2개, 0.160.1). 모두 `bin/codex` → `codex.js` 심볼릭 링크이다. nvm은 `~/.zshrc`(대화형 셸)에서만 로드되므로 로그인 셸 조회로는 찾을 수 없다.
- **없음:** Homebrew와 `~/.npm-global` 설치는 없다.

## 3. 작업 A — Codex 실행 파일 탐색 정리

새 경로를 고정 목록에 추가하는 방식은 쓰지 않는다. 앱 번들 안의 위치는 공개된 약속이 아니어서 업데이트로 다시 바뀔 수 있다. 그래서 **탐색을 단계로 나누고, 후보마다 실제로 실행해 검증한다.**

### 탐색 위치와 앱 연결

- **탐색 주체**
  - `CodexTranslationClient` 안의 중첩 타입 `ExecutableResolver`가 탐색한다. `startIfNeeded()`가 새 app-server 프로세스를 띄울 때 실행된다.
  - AppModel(@MainActor)에서는 탐색하지 않는다. 벤치마크와 스모크 테스트도 `CodexTranslationClient()` 기본값으로 이 탐색을 쓴다.
  - 새 파일로 나누지 않는 이유: `benchmark-codex-speed.sh`가 기준선 파일에서 액터 이름만 바꿔 같은 모듈로 컴파일하기 때문이다. 최상위 타입이 생기면 이후 이 PR을 기준선으로 쓸 때 중복 선언이 된다.
- **`Configuration.executableURL`:** 검증된 고정 실행 대상으로 유지한다. 값이 있으면 탐색, `--version`, 최소 버전 검사를 모두 건너뛰고 그대로 실행한다. 단위 테스트의 `codex-fake-server.py`와 벤치마크 고정에 쓴다.
- **사용자 지정 경로**
  - init 시점이 아니라 탐색 시점에 읽는다. `Configuration.userExecutablePathProvider: @Sendable () -> String?`를 두고, AppModel은 `{ UserDefaults.standard.string(forKey: "codexExecutablePath") }`를 넘긴다.
  - 덕분에 `defaults write` 뒤 앱을 재실행하지 않아도, 새 프로세스를 띄울 때 반영된다.
- **결과 공개:** `public struct ExecutableInfo: Sendable, Equatable { path, displayPath, version, source }`와 `public var executableInfo`로 공개한다. AppModel은 `connectProvider(.codex)`가 성공하든 실패하든 끝난 뒤 이 값을 읽어 설정에 표시한다.
- **실행 파일 바꾸기:** 연결된 상태에는 '연결 확인'이 없다. 바이너리를 바꾸려면 '연결 해제 → 연결 확인'으로 새 프로세스를 띄워야 하고, 그때 다시 탐색한다. README에 적는다.

### 탐색 순서

| 순서 | 출처 | 규칙 |
| --- | --- | --- |
| 1 | 사용자 지정 경로(`codexExecutablePath`) | 있으면 이것만 쓴다. 실행·버전 검증에 실패하면 다른 바이너리로 조용히 넘어가지 않고 "지정한 Codex 경로를 실행할 수 없습니다"로 안내한다. Codex 업데이트로 문제가 생겼을 때 이전 버전으로 되돌리는 수단이기도 하다 |
| 2 | 환경변수 `CODEX_EXECUTABLE`, `CODEX_CLI_PATH` | 기존 동작 유지(개발·테스트용) |
| 3 | 사용자 설치 위치 | Homebrew(`/opt/homebrew/bin`, `/usr/local/bin`), npm 전역(`~/.npm-global/bin`), `~/.local/bin`, Volta(`~/.volta/bin`), Bun(`~/.bun/bin`). nvm은 `NVM_DIR`이 있으면 그 아래 `versions/node/*/bin/codex` 전체를, 없으면 `~/.nvm` 아래를 본다 |
| 4 | 현재 프로세스 PATH의 각 디렉터리 | `/usr/bin/env codex` 대신 PATH 디렉터리를 직접 훑고 같은 검증을 거친다. 터미널에서 실행하는 벤치마크와 mise·asdf·fnm·pnpm·Nix 설치를 계속 지원한다 |
| 5 | ChatGPT/Codex 앱 번들 | 번들 ID `com.openai.codex`로 앱 위치를 찾는다(`NSWorkspace.urlForApplication(withBundleIdentifier:)`. 앱은 샌드박스가 아니어서 쓸 수 있다). 앱 안에서는 `Contents/Resources/*/codex-package.json`(layoutVersion 1)의 `entrypoint`를 실행한다. 없으면 이전 배치인 `Contents/Resources/codex`를 본다. 셸 래퍼 `bin/codex`는 그대로 실행하고 내부 Mach-O로 우회하지 않는다. 앱 내부 부품이고 자동 업데이트되므로 사용자 설치보다 뒤에 둔다 |

**검증과 선택**
- **실행 검증:** 후보마다 `nativeCodexExecutable`을 적용한 뒤 `--version`을 실행한다. 후보별 3초 제한, 병렬 실행, 30–90ms 수준이다. 제한 시간 초과는 '버전 미달'과 구분하고, 한 번 더 길게 시도한다.
- **최소 버전은 0.155.0으로 고정한다**(`minimumCodexVersion`).
  - 로컬에서 스키마와 소스를 모두 확인할 수 있는 가장 낮은 버전이다. 0.154.0은 태그와 스키마가 없어 검증할 수 없다.
  - deepK가 쓰는 기능이 모두 v0.155.0 비실험 스키마와 rust-v0.155.0에 있다: `thread/start`(ephemeral·serviceTier·baseInstructions·developerInstructions·config), `turn/start`(serviceTierForTurn·sandboxPolicy·effort), `mcpServerStatus/list`(detail=toolsAndAuthOnly), `app/installed`, `item/agentMessage/delta`, `--disable` 기능 키 6개.
  - gpt-6-luna의 `minimal_client_version`도 0.155.0이다.
  - 0.142.5 같은 이전 버전은 `--disable code_mode_host`에서 'Unknown feature flag'로 exit 1 종료한다. exit 127 조건으로는 걸러지지 않으므로 최소 버전 검사가 유일한 방어선이다.
- **버전 해석:** `codex-cli X.Y.Z[-pre]`에서 숫자 세 개를 읽는다. 프리릴리스는 같은 정식 버전보다 낮게 보고, 자동 탐색에서는 정식 버전을 우선한다. `0.0.0`(소스 빌드)은 사용자 지정 경로일 때만 허용한다.
- **고르는 규칙:** 같은 순서 단계 안에서는 가장 높은 버전을 고른다. 예: nvm에서는 0.160.1.
- **검증 범위보다 새 버전:** 검증한 최신 버전(`testedCodexVersion`, 현재 0.160.x)보다 높아도 막지 않고 고른다. 설정에 '검증 범위보다 새 버전'을 함께 표시한다.
- **후보가 없을 때:** `/usr/bin/env codex`로 넘기지 않는다. "Codex CLI를 찾지 못했습니다"와 함께 설치 방법과 경로 지정 방법을 안내한다.
- **캐시와 재탐색**
  - 탐색 결과(경로, 버전, 출처 단계)는 캐시한다.
  - 캐시한 경로로 새 프로세스를 띄울 때마다 `--version`을 다시 실행한다. 버전이 바뀌었으면 표시를 갱신하고, 최소 버전 미만이 되면 전체를 다시 탐색한다.
  - 실행 실패(프로세스 시작 오류, exit 127)나 사용자의 '연결 확인' 때도 다시 탐색한다.
- **SIGPIPE 방지:** Codex stdin 파이프에 `F_SETNOSIGPIPE`를 적용한다. 실행 직후 종료된 프로세스에 쓰다가 deepK가 SIGPIPE로 죽는 것을 막는다(Claude 쪽과 같은 방식).

### 표시와 안내

- `ClientError`에 `executableNotFound`, `executableUnsupported`, `configuredExecutableInvalid`를 추가하고 한국어 설명을 단다. `AppModel.providerState(for:error:)`에서 세 경우를 `.cliMissing`으로 바꾼다.
- 설정의 Codex 제공자 영역에 "실행 파일: `~/.nvm/…/codex` · 0.160.1"처럼 실제 경로(홈은 `~`로 축약)와 버전을 표시한다.
- `installInstructions(.codex)` 문구와 README의 Codex 설치 안내를 탐색 순서와 경로 지정 방법으로 바꾼다.
  - 지정: `defaults write com.deepk.app codexExecutablePath -string <경로>`
  - 해제: `defaults delete com.deepk.app codexExecutablePath`

### 버전 고정 스크립트: 넣지 않음(2026-10-07 사용자 결정)

검증한 버전을 앱 전용으로 설치해 고정하는 `scripts/setup-codex.sh`(`setup-claude.sh` 방식)는 만들지 않는다. 기본 동작은 탐색으로 최신 Codex를 따라가는 것이다. 업데이트로 깨지면 설정의 경로·버전 표시로 알아채고, `codexExecutablePath`에 검증된 버전(예: nvm의 다른 Node 버전 아래 설치)을 지정해 되돌린다. 같은 문제가 반복되면 후속 작업으로 다시 검토한다.

### 완료 기준

- [ ] `open`으로 실행한 앱이 두 경우 모두 Codex에 연결된다: nvm 설치만 있을 때, ChatGPT.app만 있을 때. (10절의 `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin` 재현에서 nvm 0.160.1과 ChatGPT.app 번들을 고르는 것은 확인했다. 실제 앱 확인은 남았다.)
- [x] 지정 경로가 잘못되면 다른 바이너리를 쓰지 않고 안내한다.
- [x] 최소 버전 미만 후보는 고르지 않는다. nvm의 여러 버전 중 가장 높은 버전을 고른다.
- [ ] 설정에 실제 경로와 버전이 표시된다. (Codex 제공자 행의 ‘실행 파일’ 줄로 구현했다. 실제 앱 화면 확인은 남았다.)
- [x] 탐색기는 다음을 모두 주입받는다: 홈 디렉터리, 절대 경로 후보 목록, 환경변수, PATH, 사용자 지정 경로, 번들 URL 조회 함수, `--version` 실행 함수(제한 시간 포함). 테스트에서 실제 `/Applications/ChatGPT.app`이나 `~/.nvm`의 Codex가 실행되지 않는다.
- [x] 임시 디렉터리의 가짜 실행 파일로 다음을 검사한다(`DeepKTests/CodexExecutableResolverTests.swift`).
  - 우선순위, 잘못된 지정 경로
  - 최소 버전(가장 높은 후보가 미달인 경우 포함), nvm 다중 버전
  - 번들 탐색(`codex-package.json`), PATH 탐색, 후보 없음
  - npm 래퍼(`bin/codex` → `codex.js`)가 `node_modules/@openai/codex-darwin-arm64/vendor/<triple>/bin/codex`와 끌어올린 배치(`../codex-darwin-arm64/...`)로 바뀌는지
  - 프리릴리스·`0.0.0` 해석, `--version` 제한 시간 초과, 실행 실패 후 재탐색
- [x] 즉시 종료하는 실행 파일(exit 127)에서 `connect()`가 오류를 던지고, 테스트 프로세스가 SIGPIPE로 죽지 않는다.
- [x] 기존 `CodexTransportTests`가 가짜 서버 수정 없이 통과한다(B·C의 안전 조건 변경은 예외).

## 4. 작업 B — Codex 자동 주입 프롬프트 정리

deepK가 보내는 번역 지시(`baseInstructions`, `developerInstructions`)와 원문은 바꾸지 않는다. Codex app-server가 코딩 에이전트용으로 **스스로 붙이는 내용만** 번역 스레드의 `thread/start` `config`로 끈다.
- 사용자 `~/.codex/config.toml`은 건드리지 않으므로 평소 Codex 코딩 작업에는 영향이 없다. 모든 키가 스레드 단위로 적용됨을 소스에서 확인했다.
- PR #42의 대기 스레드도 같은 `thread/start`를 쓰므로 그대로 적용된다.

| Codex가 붙이는 것 | 크기 | 처리 | 설정 |
| --- | --- | --- | --- |
| 개인 메모리 요약 | 16.5KB | 제거 | `features.memories=false`, `memories.use_memories=false`, `memories.generate_memories=false` |
| 스킬 설명 | 14.6KB | 제거 | `skills.include_instructions=false`, `skills.bundled.enabled=false` |
| goal 도구 3종(create_goal·get_goal·update_goal, exec 설명 안) | 약 3.0KB | 제거 | `features.goals=false` |
| `request_user_input` 도구 | 약 1.4KB | 제거 | `tools.experimental_request_user_input.enabled=false` |
| exec 설명 안 `view_image` | 약 0.65KB | 제거 | `features.view_image=false` |
| 환경·권한·앱·협업 안내 | 약 1KB | 제거 | `include_environment_context`, `include_permissions_instructions`, `include_apps_instructions`, `include_collaboration_mode_instructions` = false |
| 사용자 훅(SessionStart·UserPromptSubmit) 실행 | — | 제거 | `features.hooks=false` |
| 스킬 선택 처리(번역마다 약 30ms) | — | 제거 | `features.skill_search=false` |
| 셸 스냅샷(스레드 생성 때 로그인 셸 2회, `~/.codex/sessions` 정리 스캔) | — | 제거 | `features.shell_snapshot=false` |
| 하위 에이전트, sleep 도구(구현 중 추가) | — | 제거 | `agents.enabled=false`, `features.sleep_tool=false`. 두 키 모두 rust-v0.155.0·v0.160.0에 있고 0.160.1에서 configWarning이 없다 |
| 효과 없는 키 | — | 삭제 | `apps._default.default_tools_enabled` |
| exec·wait 골격과 apply_patch | 약 5.6KB | 남음 | 모델 카탈로그의 `tool_mode=code_mode_only`가 강제한다(`core/src/tools/mod.rs:75-85`@rust-v0.160.0) |
| 전역 `~/.codex/AGENTS.md` | 0.9KB | 남음 | `project_doc_max_bytes: 0`이어도 주입된다. `CODEX_HOME`을 바꾸는 방법은 부작용이 커서 쓰지 않는다 |

- **기능 키 위치:** 스레드 `config.features` 객체는 프로세스 `--disable` 값을 통째로 대체한다. 그래서 기존 6개(shell_tool, apps, multi_agent, code_mode_host, computer_use, plugins)를 스레드 `features`에도 모두 적고, 새 키를 더한다. 새 기능 키는 프로세스 `--disable`에 넣지 않는다. 모르는 키가 하나라도 있으면 'Unknown feature flag'로 app-server가 시작하지 못하기 때문이다.
- **버전 호환**
  - rust-v0.155.0과 rust-v0.160.0에서 모든 키가 같은 경로·타입으로 있음을 확인했다. 그래서 버전별로 키를 빼지 않는다.
  - 알 수 없는 키: 0.155에서는 조용히 무시되고, 0.160부터 configWarning 하나만 나며 스레드는 생성된다.
  - 값의 타입이 틀리면 `thread/start`가 실패한다.
  - 0.155에서는 오타가 경고 없이 통과하므로 `CodexTransportTests`가 정확한 키 집합을 검사한다.
- **남는 위험(PR #52에서 대응):** 원문에 `$스킬이름`(예: `$diff`)이나 `[$이름](경로)`가 있으면 Codex가 해당 SKILL.md를 turn에 주입한다. `include_instructions=false`와는 무관하다(`core/src/session/turn.rs:1083-1100`@rust-v0.160.0). → 2026-10-12 PR #52에서 원문의 모든 `$` 뒤에 WORD JOINER(U+2060)를 넣어 보내고 부분·최종 결과에서 되돌리는 방식으로 막았다(`CodexTranslationClient.guardingSkillMentions`, `skills/src/mentions.rs`의 이름 문자 규칙 기준). 가짜 서버 테스트(`$create-pr`·`[$diff](경로)`·`$5`)로 확인했고, 실제 Codex 요청 캡처로 SKILL.md가 붙지 않는지는 아직 확인하지 않았다. `scripts/capture-codex-request.sh`의 `skill` 표본은 지금도 크기만 기록한다.

### 완료 기준

- [x] 가짜 Responses 서버로 실제 `~/.codex`를 쓴 요청을 캡처했을 때 다음을 모두 만족한다(10절 캡처 표, `scripts/capture-codex-request.*`).
  - 본문 10KB 이하(예상 약 9.1KB). 단, `gpt-6-luna`는 모델 카탈로그(`experimental_supported_tools`)가 `request_user_input_async`(약 1.5KB)를 강제로 붙여 약 10.7KB가 되며, 스레드 config로 끌 수 없으므로(`core/src/tools/spec_plan.rs:1178-1201`@rust-v0.160.0) 허용한다. 이 도구는 변경 전에도 붙어 있었다
  - `memory_summary.md` 줄 0개
  - `<skills_instructions>`·goal 도구 없음
  - configWarning 알림 0개
  - 캡처는 deepK가 실제로 보내는 `thread/start` config에 `model_providers`만 더해서 한다. 기존 config 위에 덮어쓰는 방식은 쓰지 않는다. configWarning은 응답이 아니라 별도 알림이므로 알림을 수집해 확인한다.
  - 진단 때 쓴 캡처 도구(`/private/tmp/deepk-codex-diag-fake`)는 재부팅하면 사라지므로 `scripts/capture-codex-request.*`로 옮긴다.
- [x] `CodexTransportTests`가 `thread/start` config의 정확한 키 집합(아래 7절)을 검사한다.
- [x] 실측에서 번역 품질이 기존과 같다(표본 10개 중대 오류 0건, 사용 가능 8/10 이상). 10절 실측에서 10개 표본 모두 세 비교군의 의미가 같았다.
- [x] `~/.codex/config.toml`과 사용자의 일반 Codex 세션 동작이 바뀌지 않는다(캡처 전후 `config.toml` 해시 불변, 모든 키는 스레드 단위).

## 5. 작업 C — Fast 계층 선택

- **기본값은 끔.** 끈 상태에서도 계층을 생략하지 않고 명시한다(PR #38 이전 방식).
  - `thread/start`의 `serviceTier`와 `turn/start`의 `serviceTierForTurn`에 끔이면 `"default"`, 켬이면 `"priority"`를 보낸다.
  - `serviceTierForTurn`은 그 turn에서 스레드 계층을 덮어쓰고, 생략하면 스레드 계층을 물려받는다(TurnStartParams 스키마, `turn_context.rs:1091-1095`@rust-v0.160.0).
  - 두 값은 항상 같게 보낸다. 다르면 Codex 내부 예열 응답을 이어 쓰지 못한다(`client.rs:389`).
- **`translationConfig`의 `service_tier: "default"`는 끔·켬과 관계없이 항상 보낸다.**
  - 0.155.0과 0.160.0에서 유효하고 경고를 내지 않는다(`config_toml.rs:404-407`, `config_types.rs:533-537`@rust-v0.160.0).
  - 이 키가 없으면 스레드 계층이 사용자 `~/.codex/config.toml`의 `service_tier`를 따른다(`config/mod.rs:3965-3969`). Codex 앱은 Fast 설정을 이 키에 저장하므로, 키를 빼면 deepK 번역도 조용히 priority가 된다.
  - 사용자 설정이 `features.fast_mode=false`면 켬 상태에서도 priority가 빠질 수 있다. 켬 상태 캡처로 실제 요청의 `service_tier`를 확인한다.
- **계층은 불변 `Configuration`에 넣지 않는다.**
  - 번역: AppModel 번역 클로저가 provider·model을 고정할 때 계층(UserDefaults `codexFastServiceTier`, 기본 false)도 함께 읽어 `translate(..., fastServiceTier:)`로 넘긴다.
  - 대기 스레드: `setPrewarm(model:fastServiceTier:generation:)`으로 넘긴다.
  - `PreparedThread`에 계층을 저장한다. `claimPreparedThread`는 계층이 요청 계층과 같을 때만 그 스레드를 쓴다.
  - 계층이 바뀌면 이미 만든 대기 스레드와 준비 중인 작업을 모두 무효화하고 새 계층으로 다시 준비한다. `translate`의 준비 대기 조건과 `updateCodexPrewarm`의 중복 방지 조건은 (모델, 계층) 쌍으로 비교한다. 진행 중인 번역은 그대로 둔다.
- **설정 화면:** '번역' 탭 '모델' 행 아래에 `app.selectedProvider == .codex`일 때만 기존 `settingToggleRow`로 넣는다(`FinalSettingsView.swift:322-347, 454-475`).
  - 제목: "Codex 빠른 응답(Fast)"
  - 보조 문구: "더 빠른 생성 · 구독 사용량 증가". 정확한 배수는 카탈로그에 없으므로 숫자를 쓰지 않는다.
- **번역 캐시 키에는 계층을 넣지 않는다.** 계층은 속도와 사용량만 바꾼다. 그래서 같은 원문은 캐시 결과가 나오므로, 토글 확인은 새 원문이나 '다시 번역'으로 한다.
- **README:** "Codex 번역은 기본으로 일반 계층을 쓰며 설정에서 Fast(priority)를 켤 수 있다"로 고친다.

### 완료 기준

- [x] 끈 상태: 스레드·turn이 모두 `default`이고 `priority`가 0회. 켠 상태: 둘 다 `priority`(테스트와 캡처).
- [x] 대기 스레드를 준비한 뒤 계층을 바꾸면 이전 스레드가 unsubscribe되고, 다음 번역은 새 계층 스레드를 쓴다.
- [x] 준비 중에 계층을 바꾸면 이전 계층 스레드가 게시되지 않는다. 낮은 세대의 변경은 무시된다. 계층이 다른 대기 스레드는 쓰지 않는다.
- [ ] 재실행 후에도 설정이 유지된다. (UserDefaults `codexFastServiceTier`에 저장한다. 실제 앱 재실행 확인은 남았다.)

## 6. 검증 순서

1. **오프라인(쿼터 0)**
   - `./scripts/test.sh`, `./scripts/build.sh`
   - 벤치마크 컴파일 확인: `setPrewarm`·`translate` 시그니처 변경 반영
   - 가짜 서버 캡처 검사(4절 기준)
2. **실측(구독 사용량 사용).** 측정 전에 `scripts/benchmark-codex-speed.*`를 고친다.
   - 비교군
     - (a) `DEEPK_BASELINE_REF=84a24f0`: PR #42, Fast 켬, 주입 그대로. 스크립트 기본값 48c2b95는 PR #42 이전이라 쓰지 않는다.
     - (b) 현재 코드 + Fast 끔
     - (c) 현재 코드 + Fast 켬
   - 세 비교군 모두 `setPrewarm` → 준비 완료 대기 → 3초 간격을 똑같이 적용하고, 순서는 표본마다 돌린다.
   - 모든 비교군에 `CODEX_EXECUTABLE`로 같은 Codex를 고정하고, 결과 JSON에 경로와 버전을 기록한다.
   - 규모: 반복 1회, literals 표본 제외로 3 × 10 = 30 turn.
   - 입력 크기는 실측에서 판정하지 않는다(클라이언트가 `thread/tokenUsage/updated`를 무시한다). 1단계 캡처로 판정한다.
   - 판정: (b) 단문 p50 ≤ (a) 단문 p50 + 150ms, 품질 동일. 긴 글에서 (b)와 (c)의 차이를 기록한다.
3. **실제 앱:** `open`으로 실행해 Codex 연결, 설정의 경로·버전 표시, Fast 토글 전환(새 원문으로)을 확인한다.

## 7. 순서, PR 관계, 테스트 보강

### PR 관계
- 이 PR의 base는 `codex/codex-translation-prewarm`(PR #42)이다.
- PR #42는 PR #41 머지 뒤 `main`과 `DeepK/AppModel.swift`에서 충돌한다. 다음 순서로 진행한다.
  1. AppModel을 고치기 전에 PR #42 브랜치에 `main`을 **merge commit**으로 병합해 충돌을 먼저 푼다.
  2. 그 브랜치를 이 브랜치에 병합한다. rebase와 강제 push는 하지 않는다.
  3. PR #42 머지 직후 `gh pr edit <번호> --base main`으로 이 PR의 base를 바꾼다. 브랜치 자동 삭제가 꺼져 있어 수동으로 해야 한다.
  4. 머지 전에는 임시 워크트리에서 최신 `main`을 병합해 test·build로 검증한다.
- 구현 커밋은 A → B → C 순서로 나눈다. B와 C는 같은 `thread/start` 파라미터를 고치므로 같은 테스트 픽스처를 공유한다.

### 테스트 보강
- **`codex-fake-server.py`의 `SAFETY_OK`**
  - 지우는 조건: `default_tools_enabled is False`, `serviceTier == "priority"`, 그리고 turn의 `serviceTierForTurn == "priority"`.
  - 대신 다음을 모두 만족할 때만 통과하게 한다.
    - `default_tools_enabled`가 없다.
    - 스레드 `config.features`에 기존 6개와 새 키(memories, goals, hooks, skill_search, shell_snapshot, view_image)가 모두 false다.
    - `memories.use_memories`·`generate_memories`, `skills.include_instructions`, `skills.bundled.enabled`, `tools.experimental_request_user_input.enabled`, `include_*` 4개가 false다.
  - `config.service_tier == "default"`는 계속 요구한다.
- **계층 기록:** `tier/thread|<serviceTier>|<threadId>`, `tier/turn|<serviceTierForTurn>|<threadId>`처럼 별도 줄로 기록한다. 기존 `turn/start|low` 정확 일치 검사(`CodexTransportTests.swift:283`)를 깨지 않기 위해서다.
- **C 테스트:** 5절 완료 기준의 여섯 경우(끔, 켬, 준비 후 변경, 준비 중 변경, 낮은 세대, 계층 불일치).
- **A 테스트:** 3절 완료 기준.
- **swiftc 목록 정리:** `scripts/test-incremental-live.sh`, `scripts/benchmark-translation.sh`는 `84a24f0`에서 이미 `TranslationLiteralPlan.swift`가 빠져 컴파일되지 않는다(검토자 typecheck). 함께 고치고 확인한다.

## 8. 위험

| 위험 | 대응 |
| --- | --- |
| Codex 업데이트로 config 키나 프로토콜이 바뀜(0.160에서 알 수 없는 키 configWarning 추가, `thread/rollback` 제거 사례) | 버전 검증과 최소 버전, 정확한 키 집합 테스트, configWarning 캡처 검사. 깨지면 `codexExecutablePath`로 검증된 버전 지정 |
| 탐색이 예상과 다른 바이너리를 고름 | 설정에 경로와 버전 표시, `codexExecutablePath`로 지정 |
| 후보마다 `--version` 실행 비용 | 새 프로세스를 띄울 때만, 병렬·제한 시간, 결과 캐시 |
| 계층 변경 직후 이전 계층 대기 스레드로 과금 | (모델, 계층) 쌍으로 대기 스레드를 식별하고 변경 시 무효화 |
| Fast를 끄면 긴 글이 느려짐 | 토글 제공. 필요하면 별도로 `gpt-6-luna` A/B 검토 |
| 주입을 끄면 번역 품질이 달라질 가능성 | 실측 품질 대조. 번역과 무관한 블록이라 영향은 작을 것으로 예상 |
| 원문의 `$스킬이름`이 SKILL.md 주입을 일으킴 | 2026-10-12 PR #52에서 `$` 뒤에 U+2060을 넣어 보내고 결과에서 되돌리도록 막았다. 실제 Codex 요청 캡처 확인은 남았다(4절 ‘남는 위험’) |

## 9. 범위 밖

- 계측 보강, 사용 한도 안내: 사용자 결정으로 제외.
- git-attribution 설정 조회 0.38초: Codex 내부 기능이라 deepK에서 끌 수 없다. 프로세스 단위 캐시나 ephemeral 스레드 생략을 `openai/codex`에 제안하는 것은 별도 작업이다.
- Codex 버전 고정 스크립트(`setup-codex.sh`): 사용자 결정으로 제외, 필요해지면 후속.
- `gpt-6-luna` 전환, Sign in with ChatGPT 직접 호출, 유료 API.
- Claude 경로.

## 10. 구현 결과 — 2026-10-07

- 기반: PR #42에 `main`을 merge commit으로 병합해 `DeepK/AppModel.swift` 충돌을 해결했다(`7bfea2f`). 두 PR의 대기 준비 힌트를 같은 시점에 함께 보내고, 중복 등록된 잠자기 관찰자를 하나로 합쳐 Claude와 Codex에 모두 알린다.
- 오프라인 검증: `./scripts/test.sh` 2회, `./scripts/build.sh`, `git diff --check` 통과. 3관점 리뷰 지적 7건(major 1)을 모두 확인·수정했다.
- 요청 본문 캡처(가짜 Responses 서버, 쿼터 0, 메모리 요약 72줄 대조, `~/.codex/config.toml` 해시 불변):

| 모델 | Fast | 본문 | 메모리 줄 | 스킬·goal | configWarning | 계층(thread/turn) |
| --- | --- | --- | --- | --- | --- | --- |
| gpt-5.6-luna | 끔 | 8,902B | 0 | 없음 | 0 | default/default |
| gpt-5.6-luna | 켬 | 8,928B | 0 | 없음 | 0 | priority/priority |
| gpt-6-luna | 끔 | 10,703B | 0 | 없음 | 0 | default/default |
| gpt-6-luna | 켬 | 10,729B | 0 | 없음 | 0 | priority/priority |

- 실행 파일 탐색(`env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `open` 실행 환경 재현): nvm의 0.160.1을 골랐다(0.136.0·0.137.0·0.142.5 제외). nvm이 없는 입력에서는 ChatGPT.app 번들(0.160.1)을 골랐다. 0.142.5 지정 경로는 최소 버전 미만으로 거부했다.
- 알려진 남은 사항: `CodexTransport` 테스트가 실행마다 `$TMPDIR/deepK-codex-<UUID>` 빈 폴더를 남긴다(이 PR 이전부터 있던 동작). 설정 창 번역 탭은 Fast 행이 추가되어 약 1pt 넘쳐 스크롤될 수 있었다. 이후 PR #49에서 복사 형식 행까지 다섯 행(제공자 둘·모델·Fast·복사 형식)이 되어 설정 창 높이를 320 → 376pt로 늘렸다. 실제 앱 화면 확인은 여전히 필요하다.

### 실측 — 2026-10-07

`DEEPK_RUN_LIVE_BENCHMARK=1 ./scripts/benchmark-codex-speed.sh`, 모델 `gpt-6-luna`(앱 설정), Codex `~/.nvm/…/codex` 0.160.1로 세 비교군 고정, 대기 스레드 준비 후 3초, 표본마다 순서 회전, 30 turn 모두 성공. [원본](../benchmarks/runs/20261007-codex-followup-ab.json).

| 분량 | n | (a) PR #42 기준 | (b) 정리 + Fast 끔 | (c) 정리 + Fast 켬 |
| --- | ---: | ---: | ---: | ---: |
| 단문 전체 p50 | 4 | 2,094ms | **1,885ms** | 1,730ms |
| 단문 첫 글자 p50 | 4 | 1,739ms | 1,487ms | 1,562ms |
| 문단 전체 p50 | 4 | 2,458ms | 2,518ms | 2,032ms |
| 긴 글 전체 p50 | 2 | 3,382ms | 3,180ms | 4,736ms |

- 판정: (b) 단문 p50 1,885ms ≤ (a) + 150ms(2,244ms) 통과. 10개 표본 모두 세 비교군의 의미가 같았다(부정, 숫자·단위, `cancel()`·`requestID`와 줄바꿈, 긴 글 3문단 유지). 중대 오류 0건.
- 셀당 n이 2–4라 분량별 차이, 특히 긴 글과 Fast 효과는 판단하기 어렵다. 단문에서 Fast를 꺼도 느려지지 않았다는 점과 입력 축소가 속도를 해치지 않았다는 점만 확인한 것으로 기록한다.
- 미확인: 실제 앱을 `open`으로 실행한 Codex 연결·경로 표시·Fast 토글(PR #49에서 376pt로 늘린 설정 창에서 다섯 행과 실행 파일 줄이 잘리지 않는지 포함). 실행 중인 앱을 종료해야 하고 재빌드 후 권한 재허용이 필요할 수 있어 사용자 확인으로 남긴다.
