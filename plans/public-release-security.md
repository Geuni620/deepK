# 공개 전 보안 점검

상태: 초기 비공개 개발 단계의 보안 점검과 남은 한계를 관리한다. 현재 저장소는 당시 소스의 최신 스냅샷에서 새 Git 이력으로 시작하며, 과거 PR·커밋 참조는 비공개 보관 이력에 해당한다. 공개 여부는 GitHub 설정을 기준으로 확인한다.

## 1. 지키는 것

deepK는 복사한 원문을 사용자의 Codex app-server 또는 Claude Code CLI로 보내 번역한다.

- 번역 요청에는 번역 지시와 복사한 원문이 들어간다. 로컬 파일, 부모 앱의 환경 변수, 설치된 스킬, 저장소 문맥은 섞이지 않는다. 예외로 Codex에는 전역 `~/.codex/AGENTS.md`가 있으면 끌 수 없어 함께 들어간다(4절).
- ⌘C 두 번으로 가져온 복사 중 비밀번호 관리자가 민감하다고 표시한 것은 외부 모델로 보내지 않는다. 원문 창에 직접 붙여넣은 글은 검사하지 않는다.
- 원문은 프롬프트에서 신뢰하지 않는 데이터로 다루고, 번역 프로세스의 도구 실행을 끈다.
- 공개할 파일과 Git 이력에 개인 정보(작성자 메일, 홈 경로)와 비밀 값이 남지 않는다.

PR #52 이전부터 있던 보호는 다음 문서에 있다.

- Claude: 구독 인증을 확인한 뒤에만 요청하고 API·클라우드 인증 변수를 지운다. safe mode·빈 MCP·도구 차단·별도 cwd·세션 비저장([엔진 계획](engine-candidates.md)).
- Codex: ephemeral 스레드와 빈 임시 cwd, 메모리·스킬 설명·goal 도구 주입 차단([Codex 후속 계획](codex-translation-followup.md)).
- 원문·클립보드 HTML·출처 URL은 로그에 남기지 않는다([웹 수식 복사 정리](web-math-copy.md)). 링크 URL은 모델에 보내지 않고 열기 전에 다시 검사한다([결과 구조 유지](result-structure.md)).

## 2. PR #52에서 막은 경로

| 경로 | 변경 후 동작 | 위치 |
| --- | --- | --- |
| Claude `@경로` 첨부. CLI가 모델 호출 전에 파일을 읽어 붙이며 `--tools ""`·`--safe-mode`로 막히지 않는다(2.1.295 재현) | `CLAUDE_CODE_DISABLE_ATTACHMENTS=1`을 설정값 적용 뒤에 강제한다 | `ClaudeTranslationClient.sanitizedEnvironment` |
| 비밀번호 관리자 복사(`org.nspasteboard.ConcealedType`·`TransientType`) | 표시가 먼저 있으면 문자열을 읽지 않고 거절하며 안내를 보인다. 성공 후보는 다음 poll(10ms)에서 같은 항목에 표시가 없을 때만 확정한다(문자열 뒤에 표시를 붙이는 arboard 방식 대응). 대기 한도(250ms)에 닿은 마지막 후보는 기다리지 않고 바로 확인한다 | `DoubleCopyMonitor.readPasteboard`·`confirmCapture` |
| 부모 환경 상속. Codex는 전체, Claude는 인증값만 뺀 환경을 넘겨 `GITHUB_TOKEN`, `OTEL_*` 등이 전달됐다 | 허용 목록(아래)만 넘긴다 | 두 클라이언트의 `inheritedEnvironmentKeys` |
| Codex `$이름`·`[$이름](경로)`. 설치된 스킬의 SKILL.md가 turn에 들어가며 `skills.include_instructions=false`로 막히지 않는다 | 보낼 때 `$` 뒤에 WORD JOINER(U+2060)를 넣고 부분·최종 결과에서 되돌린다 | `CodexTranslationClient`의 `skillMentionGuard` |
| 커밋된 벤치마크 JSON·계획 문서의 개인 홈 경로 | `~`로 바꿨다(현재 파일만) | `040d4d5` |

허용 목록은 [README](../README.md#보내는-내용과-실행-환경)의 표가 기준이며 코드의 두 `inheritedEnvironmentKeys`와 같다. 명시한 `configuration.environment`(테스트·벤치마크)는 그 뒤에 적용하고, Claude 인증값 제거는 그 뒤에도 유지한다. 키를 더하면 두 클라이언트의 기대 키 전체 비교 테스트와 README 표를 함께 고친다.

## 3. 일부러 넣지 않은 것

| 항목 | 이유 |
| --- | --- |
| `NODE_OPTIONS` 전달 | `--require`로 CLI 프로세스에 임의 코드를 넣을 수 있다 |
| `NODE_TLS_REJECT_UNAUTHORIZED` 전달 | TLS 검증을 끈다. 사설 CA는 `NODE_EXTRA_CA_CERTS`·`CLAUDE_CODE_CERT_STORE`로 쓴다 |
| Codex telemetry 거부 변수 | 같은 역할의 변수를 확인하지 못했다 |
| 출력 크기 상한, 입력 바이트 상한, 로그인 URL 검증, 실행 파일 신뢰 확인 | 위험이 낮다고 보고 제외했다 |

## 4. 남은 한계와 미검증

- 실제 비밀번호 관리자 앱에서 복사해 보지 않았다. 개별 pasteboard 테스트로만 확인했다.
- 민감 표시를 문자열보다 10ms 넘게 늦게 붙이는 앱이나 두 번째 ⌘C 뒤 대기 한도(250ms) 직전에 문자열을 쓰는 앱은 걸러지지 않을 수 있다.
- 원문 창에 직접 붙여넣은 글은 민감 표시를 검사하지 않는다.
- Codex 요청에는 전역 `~/.codex/AGENTS.md`(있으면)가 들어간다. 2026-10-24에는 합성 HOME·설정과 외부 네트워크 차단을 사용한 실제 CLI 검증에서 전역 지침 표식이 요청에 포함됨을 확인했다. 실제 사용자 파일이나 인증정보는 사용하지 않았다. `CODEX_HOME`을 바꾸는 방법은 부작용이 커서 쓰지 않았다([Codex 후속 계획](codex-translation-followup.md)).
- `pollSecondCopy` 루프 자체(이벤트 탭 필요)와 AppModel의 `.clipboardConcealed` 안내 분기는 단위 테스트 밖이다.
- Codex `$이름` 보호는 upstream 파서와 가짜 서버에 더해 2026-10-24 격리한 실제 CLI로 확인했다. 합성 스킬을 사용한 요청에서 보호가 있을 때 SKILL.md 본문은 빠지고, 보호를 뺀 양성 대조군에서는 들어갔다. 실제 계정·실서비스 경로는 검증하지 않았다. `./scripts/capture-codex-request.sh`의 `skill` 사례(`Run $diff …`)는 모델 쿼터 없이 본문을 캡처하므로 이 확인에 쓸 수 있다. 지금은 크기만 기록한다. 계정 확인·모델 목록 조회는 실제 계정으로 나간다.
- 리뷰 반영(`f6e9563`·`3b13739`) 뒤 live 테스트(`DEEPK_RUN_LIVE_TRANSLATION_TESTS=1 scripts/test-incremental-live.sh`)를 다시 돌리지 않았다.
- 회사망에서 허용 목록에 없는 변수가 필요하면 CLI 연결이 실패할 수 있다. 그때는 README 표와 코드의 허용 목록에 키를 더한다.

## 5. 공개 전 남은 조건

- [x] 이전 Git 이력은 비공개 보관 저장소에 유지하고 현재 소스에서 새 이력으로 시작한다. 새 커밋에는 GitHub `noreply` 주소를 사용하며, 이전 커밋·브랜치·태그·PR 이력을 가져오지 않는다.
- [x] 새 시작점의 현재 문서에서 개인 홈 경로를 제거한다. 이전 파일 버전과 개인 이메일이 들어 있는 커밋은 새 이력에 포함하지 않는다.
- [ ] 공개 직전 새 저장소의 전체 파일과 커밋 메타데이터를 다시 검사한다. 현재 파일 검사와 Git 이력 검사를 구분하고, 토큰 탐지 결과가 임의 형식의 모든 비밀정보 부재를 보장하지는 않음을 기록한다.
- [ ] 라이선스와 버그·보안 제보 경로(SECURITY.md)를 정한다. 지금은 LICENSE와 보안 정책 파일이 없다([개인 베타 계획](macos-distribution.md)의 오픈소스 항목).
- 4절의 실제 비밀번호 관리자 복사, Codex 요청 캡처, live 테스트 재실행은 [Mac 연동 기록](mac-integration-checks.md#실제-앱-확인-대기--2026-10-12)에서 추적하며 공개 전에 끝낸다.

## 6. 참고

- [PR #52](https://github.com/Geuni620/deepK/pull/52) 본문과 독립 리뷰 코멘트(7건 모두 확인·수정, 반박 단계 기각 1건)
- 관련 계획: [개인 베타 계획](macos-distribution.md), [Codex 후속 계획](codex-translation-followup.md), [엔진 계획](engine-candidates.md), [결과 구조 유지](result-structure.md)
