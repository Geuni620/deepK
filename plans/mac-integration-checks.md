# Mac integration checks

검증일: 2026-09-19
환경: macOS 26.6.2, Xcode 26.1.1 (17B100)

## 범위와 방법

/private/tmp/deepk-fixtures/ 아래 synthetic fixture만 사용했다.

- TextEdit fixture: deepk-textedit-rerun.txt
- Browser fixture: deepk-textarea.html
- Browser는 기존 사용자 프로필과 분리한 Chrome temporary profile로 열었다.
- 기존 문서·탭을 읽거나 닫지 않았다. synthetic TextEdit 문서는 검증 후 열려 있다.
- /private/tmp/deepk-fixtures/RealAppInvocationSmoke.swift가 fixture를 frontmost로 만들고 AX selected range를 전체 문장으로 설정한 뒤 InvocationSession.capture()를 호출했다.
- deepK를 활성화한 뒤 await session.restoreFocus()를 호출하고, 현재 AX target을 확인한 다음 고정 replacement를 한 번 삽입했다.
- 번역 모델·유료 API·클립보드는 사용하지 않았다.

검증 명령:

~~~sh
swiftc -swift-version 6 -parse-as-library -warnings-as-errors \
  -module-cache-path /private/tmp/deepk-fixtures/cache \
  DeepK/MacIntegration/InvocationSession.swift \
  /private/tmp/deepk-fixtures/RealAppInvocationSmoke.swift \
  -o /private/tmp/deepk-fixtures/real-app-smoke
/private/tmp/deepk-fixtures/real-app-smoke
~~~

deepK는 com.deepk.app, build version 1이었다. 아래 PID는 해당 실행 시점의 값이다.

## TextEdit

앱: TextEdit 1.20 (build 415), bundle com.apple.TextEdit, PID 11174.

- 원문 AXValue: deepK TextEdit synthetic fixture: replace this sentence.\n
- 캡처 selected range: (0, 57)
- 캡처 selected text: 원문 전체와 일치
- AXSelectedText settable: true
- focus restore: 성공. 캡처 UUID와 receipt UUID가 일치하고 원래 AXTextArea를 다시 확인했다.
- replacement: deepK TextEdit AX replacement.
- insertion: 성공
- readback AXValue: deepK TextEdit AX replacement.
- readback selected range: (30, 0)
- readback selected text: ""

TextEdit에서는 직접 AXSelectedText 쓰기 후 값과 caret 위치를 확인할 수 있었다. synthetic 문서의 내용은 replacement 상태로 남아 있다.

## Chrome textarea

앱: Google Chrome 153.0.8010.50 (build 8010.50), bundle com.google.Chrome, isolated temporary profile, PID 12569.

- 원문 AXValue: deepK browser synthetic fixture: replace this sentence.
- 캡처 selected range: (0, 55)
- 캡처 selected text: 원문 전체와 일치
- AXSelectedText settable: true
- focus restore: 성공. 캡처 UUID와 receipt UUID가 일치하고 원래 AXTextArea를 다시 확인했다.
- replacement: deepK browser AX replacement.
- insertion: copyFallbackRequired(.readbackMismatch)
- readback AXValue: 원문 그대로
- readback selected range: (0, 55)
- readback selected text: 원문 그대로

Chrome은 settable 플래그를 주지만 직접 쓰기 뒤 값이 바뀌지 않았다. dispatch 성공만으로 삽입 성공을 보고하지 않고 readback mismatch를 copy fallback으로 반환한 현재 경계가 실제 textarea에서 확인됐다. 이 검증에서는 clipboard fallback을 실행하지 않았다.

### 명시적 pasteboard 삽입 경로

같은 synthetic textarea에 대해 insertUsingPasteboard(_:)를 별도 선택 경로로 검증했다. 이 경로는 AX selected-text 쓰기를 먼저 호출하지 않고, 검증된 Chrome bundle에서만 원본 pasteboard의 모든 item/type/data를 저장한 뒤 한 번의 PID 대상 Command-V를 보낸다.

- 실행 Chrome PID: 22757
- replacement: deepK browser AX replacement.
- pasteboard 원본 snapshot 복원: 성공
- readback AXValue: deepK browser AX replacement.
- readback selected range: (29, 0)
- 두 번째 paste 시도: staleSession으로 거부
- 최종 pasteboard snapshot: 원본과 일치

검증 중 pasteboard changeCount가 외부 변경으로 달라지면 복원을 시도하지 않고 pasteboardChanged fallback을 반환한다. timeout과 readback 실패도 재시도하지 않는다. 이 경로는 현재 측정한 Chrome textarea에만 연결하며 다른 브라우저에는 자동으로 적용하지 않는다.

## 남은 경계

- 두 앱 모두 Accessibility trust가 있는 실행 환경에서 확인했다. 권한 없음, 앱 종료, 창 미생성 상태는 이 실행에 포함하지 않았다.
- Chrome textarea는 명시적 pasteboard 경로에서만 삽입을 확인했다. 직접 AX 경로는 readback mismatch였고, pasteboard 경로는 검증된 Chrome bundle에 한정된다.
- 위 결과는 synthetic fixture와 해당 앱 버전의 결과이며, 다른 브라우저 버전·웹 편집기·Electron 앱에 대한 지원을 의미하지 않는다.

## 단축키 무반응 복구 재검증 — 2026-09-19

- 실제 이전 deepK 설정 화면에서 ChatGPT 연결 정상, 입력 모니터링 권한 부족 상태를 읽었다. 감시가 시작되지 않은 실패 안내가 숨겨진 창 안에만 있던 경로를 확인했다.
- 새 빌드의 실제 설정 화면에서 `⌘C 두 번 · 감지 중`과 Luna 선택을 확인했다. 사용자도 접근성 권한을 켰고 **실제 키보드로 단축키 창이 뜬다**고 확인했다. 이것만으로 원래 위치 삽입 성공이나 모든 앱 지원을 완료 처리하지 않는다.
- 실제 deepK 앱에 합성 CGEvent로 안전한 예시 원문 `Please keep the original window open.`의 두 번 복사를 전달했다. 입력 표시와 실제 Luna 번역 결과를 AX로 확인했다. 폴링 관측상 창 표시 약 249ms, 전체 약 5,540ms. 이는 합성 입력과 폴링을 포함한 단일 측정이며 하드웨어 입력 지연이나 p95가 아니다.
- 예시 결과: `원래 창을 열어 둔 상태로 유지해 주세요.`. 실제 화면은 `docs/evidence/recovery/luna-double-copy.png`, 설정은 `provider-settings.png`에 보관한다.
- 임시 입력 호스트는 셸 종료 trap으로 정리했다. 테스트 원문이 클립보드에 남아 있을 때만 원래 데이터를 복원했다. 일반 사용자 문서·브라우저 탭은 변경하지 않았다.
- 모델 단독 추가 확인은 `benchmarks/runs/20260919-luna-revalidation.json`: 구독 Luna/low/표준 계층 3회 모두 성공, 전체 3.62–4.85초. 1초 미달이며 작은 표본으로 보편적 최속을 주장하지 않는다.

## 캐시·디자인·종료 검증 추가

- 현재 실행 중인 검증 호스트가 없음을 프로세스로 확인했다. 수동 검증 호스트에 환경 변수+인자 이중 제한을 추가했고, 환경 변수가 없으면 창 없이 exit 64로 끝나는 것을 확인했다. 임시 창 크기와 표시 목적, 30초 자동 종료도 소스에 반영했다. 이후 실제 캐시 확인은 deepK 자체 입력창에서만 수행했다.
- 실제 앱에서 Haiku로 예시를 번역한 후 앞 공백·중복 공백·끝 엔터를 더했고 약 21–38ms에 ‘저장된 번역’ 표시를 확인했다. `docs/evidence/recovery/cache-hit.png`가 실제 결과다. 추가 호출 억제는 TranslationStoreTests의 요청 카운터로 검증했다.
- pen.dev 선택 팝오버와 확정 메인 창을 대조했고 실제 창의 420×296 크기를 확인했다. 빠른 설정은 `quick-settings.png`에 기록한다. 권한이 없는 상태도 해당 화면에 실제로 표시된다.
- 앱이 외부 CLI 정리를 기다리며 종료되지 않는 경로를 발견해 2초 종료 대기 상한을 추가했고, 정상 종료를 요청한 뒤 프로세스가 실제 종료됨을 확인했다.
- 기존 cdhash 기반 서명에서 인증서 기반 서명으로 전환했다. 사용자에게 새 서명 앱의 입력 모니터링·손쉬운 사용 재연결을 요청했으며, 이 최종 서명에서의 전체 삽입 검증은 아직 대기한다. 이전 서명에서의 ‘단축키 창이 뜬다’는 사용자 확인과 구분한다.

- 최종 420×296 화면에서 710자 합성 원문을 Haiku로 번역해 표시했다. 원문/결과 스크롤 값을 각각 0.0→0.6으로 바꿨고 다른 영역의 값이 유지됨을 확인했다. 별도 검증 호스트는 열지 않았다. 연결 해제 후 ‘번역 제공자 연결 전’ 안내, 연결 설정 진입 및 재연결도 실제 앱에서 확인했다.

- 추가 확인에서 설정 시트를 열린 채 종료하면 여전히 종료가 지연됐다. ‘모든 설정’을 독립 NSWindow로 분리한 뒤 빠른 설정 → 모든 설정 → 정상 종료를 실행했고 실제 프로세스 종료를 확인했다. 앞선 2초 상한만으로 설정 시트 문제가 해결됐다는 결론은 사용하지 않는다.

## ⌘W 창 닫기 복구 — 2026-09-20

표준 파일 메뉴의 창 닫기 항목이 없어 ⌘W가 동작하지 않았다. 대상이 고정되지 않은 NSWindow.performClose: 메뉴를 추가해 현재 창의 기존 닫기 위임 처리에 연결했다.

- 수정 전 실제 앱에 PID 대상으로 ⌘W 이벤트를 전달했을 때 표시 창이 1개 그대로 남았다.
- 수정 후 번역 창은 1→0개, 같은 프로세스 생존 및 accessory 정책 유지가 확인됐다. 같은 PID로 재호출한 뒤 다시 1→0개로 닫혔다.
- 설정 창이 앞에 있을 때는 2→1개로 줄어 설정 창만 닫혔다.
- 빌드·개발 인증서 서명·git diff --check 통과. 검증은 실제 앱에 전달한 합성 키 이벤트이며 하드웨어 입력이라고 표현하지 않는다. 별도 검증 입력 창과 모델 요청은 실행하지 않았다.

## 권한 스위치와 실제 감시 불일치 — 2026-09-20

사용자가 제공한 화면에서는 입력 모니터링의 deepK 스위치가 켜져 있었다. 이 사실을 권한 미허용으로 단정하지 않는다. deepK에 한정한 tccd 로그에서 ListenEvent와 Accessibility 모두 기존 코드 요구사항과 현재 앱의 요구사항이 일치하지 않는 오류를 확인했다. 이전 기록은 임시 서명의 cdhash, 현재 앱은 개발 인증서 기반 서명이다. 인증서 이름·개인 정보는 이 기록에 포함하지 않는다.

추가 확인에서는 이벤트 감시 객체가 생성됐지만 마스크가 4096(flagsChanged만)이었고 keyDown/keyUp이 없었다. 따라서 객체 생성·활성화만으로 ‘감지 중’이라고 표시할 수 없다. 앱은 자기 프로세스가 새로 만든 탭의 마스크를 확인하고 필수 키 이벤트가 빠진 탭은 해제한다. flagsChanged만 허용된 경우를 회귀 테스트로 추가했다. 수정 빌드에서 잘못된 준비 완료 표시와 부분 감시가 남지 않는 것을 확인했다. 실제 키 입력 정상 검증은 기존 권한 항목의 등록 갱신 후 진행한다.

메뉴 막대 시안은 Popover가 아니라 `mgb4W` 아래 Light/Dark의 ‘ㅋ’ 글리프였다. 기존 MenuBarIcon은 이미 18pt 템플릿 이미지였지만 실패 분기가 이를 경고 아이콘으로 교체하고 있었다. 이 교체를 제거하고 템플릿을 명시했다. 실제 메뉴 막대 아이콘 영역만 `docs/evidence/menu-permission/menu-glyph.png`에 캡처했다. 팝오버나 전역 macOS 테마를 변경하지 않았다.

## 추가 UI 검증 — 그룹 설정·권한 안내·시스템 팝업

- 기준 디자인: `Wtsit` 제목에 대응하는 `bPiUX`의 `l5GMR` 그룹 설정. 계정/번역/권한 헤더와 관리 버튼을 반영한다. 기존 기본 제공자 선택은 유지하며 시안의 예시 모델·구독 등급을 실제 값으로 오인하지 않는다.
- 시스템 스위치가 켜져 있다는 사용자 확인을 유지한다. 실행 앱에서 권한 API가 false를 반환하면 미허용으로 단정하지 않고 현재 앱 연결 미확인으로 표현한다. 실제 감시 성공, 단축키 끄기, 과거 오류를 구분한다.
- 권한 요청은 빠른 설정 팝오버를 먼저 닫고 deepK의 상시 표시 창을 숨겨 시스템 안내를 가리지 않게 한다. 번역 내용은 유지한다.
- 완료 조건: 통합 빌드/테스트, 그룹 설정 실제 화면, 토글 OFF에 감지 중·실패 잔존 없음, 권한 요청 때 deepK 창 가림 없음. OS 등록 갱신이 필요한 현재 환경의 실제 두 번 복사/삽입 성공은 별도 미완료로 유지한다.

통합 검증 결과: 6개 테스트 프로그램과 최종 앱 빌드·서명 검증 통과. 별도 AppModel 하네스로 미확인/연결됨/감지 중/단축키 OFF 상태 조합을 확인했다. 실제 새 앱에서 그룹 설정을 열고 접근성 연결 버튼을 눌렀을 때 표시 중인 deepK 본문 창이 0개로 줄어 시스템 권한 안내를 가리지 않음을 확인했다. 번역 내용은 유지된다. 그룹 화면은 `docs/evidence/menu-permission/grouped-settings.png`에 기록했다. 권한 등록 불일치와 실제 키보드/삽입 재검증은 여전히 남아 있으며, 수정 완료된 UI 작업과 구분한다.

## 누락 감사 후 보강

Luna Max 읽기 감사에서 권한 사전 조회가 true여도 실제 감시가 실패한 경우 녹색 ‘연결됨’이 될 수 있는 경로를 발견했다. 빠른 설정의 입력 모니터링은 실제 감시 준비 상태만으로 색상·문구를 정하고, 사용자가 단축키를 끈 경우 ‘감시 꺼짐’으로 구분한다. 실제 AppModel을 실행하는 회귀 테스트를 정규 테스트에 추가하여 사전 조회 성공/감시 실패 조합과 OFF 상태를 검증한다. OS 권한 등록 문제의 해결 여부와 이 UI 상태 수정은 별개다.

복사 실패도 갱신 없음·빈 텍스트(공백/개행 포함)·비텍스트로 분리했다. 파일 URL은 문자열 표현이 함께 있어도 번역하지 않는다. 클립보드를 비운 뒤 문자열이 늦게 채워지는 앱을 위해 기존 250ms 대기를 유지하고, 읽기 전후 변경 횟수가 달라진 중간 값은 버린다. 정상 텍스트만 즉시 전달한다. 순수 회귀 테스트는 이전 문자열 거절, 빈 값, 비텍스트, 파일 URL 및 정상 원문 보존을 검증한다. 실제 외부 앱 두 번 복사는 권한 등록 갱신 후 별도로 검증해야 한다.

최종 통합 7개 테스트 프로그램과 앱 빌드·서명 검증을 통과했다. 새 앱의 설정에서 ‘감시 연결 안 됨’을 실제 확인하고 `docs/evidence/menu-permission/monitor-status.png`에 기록했다. 이는 권한 미허용 단정이 아니라 현재 감시 준비 상태의 표시다.

## 실제 앱 확인 대기 — 2026-10-12

PR #48·#49·#52·#53은 main에 머지했지만 아래 항목은 실제 앱에서 확인하지 않았다. 단위 테스트·가짜 서버·합성 이벤트 결과로 완료 처리하지 않는다. 확인하면 앱·OS 버전과 함께 이 절에 기록한다.

PR #53에서는 Chrome 데모 문단을 ⌘C 두 번으로 번역하고, 손쉬운 사용 API로 인라인 코드 칩 4개(고정폭 14pt)와 번역 제목의 링크 속성을 확인했다.

- [ ] 민감 복사(#52): 실제 비밀번호 관리자(1Password·Bitwarden·KeePassXC 등)에서 ⌘C 두 번 → 원문 창에 값이 나타나지 않고 번역 요청이 없으며 ‘비밀번호 등 민감한 항목으로 표시된 복사는 번역하지 않습니다’가 보인다. 문자열을 쓴 뒤 표시를 따로 붙이는 앱은 표시가 10ms 넘게 늦거나 두 번째 ⌘C 뒤 대기 한도(250ms) 직전에 쓰면 걸러지지 않을 수 있으므로 앱별 결과를 남긴다. `pollSecondCopy` 루프와 AppModel의 안내 분기는 단위 테스트 밖이다.
- [ ] 링크 첫 클릭(#53): 원래 앱이 앞에 있는 비활성 상태에서 결과의 링크를 처음 클릭하면 deepK를 활성화하지 않고 바로 열린다.
- [ ] 링크 툴팁·커서(#53): 비활성 상태에서도 URL·원문 제목 툴팁과 손가락 커서가 보인다.
- [ ] 복사 형식별 붙여넣기(#49·#53): 서식 포함/마크다운만 각각으로 결과를 복사해 Notion·Slack·Google Docs·Pages·TextEdit·Chrome textarea·메모(Notes)·VS Code·Terminal에 붙여넣고 코드 블록·인라인 코드·링크가 들어가는 모양을 기록한다.
- [ ] 삽입(#53): 링크·인라인 코드가 있는 결과를 TextEdit(AX 경로)와 Chrome textarea(pasteboard 경로)에 삽입하면 URL 없이 링크 글자만 들어가고, 원문에 없던 백틱은 빠진다.
- [ ] 코드 블록 표시(#49·#50·#57·#58): 실제 창에서 코드 카드(머리줄·블록 복사·접기·문법 색), 긴 줄 줄바꿈, 끝까지 스크롤했을 때 카드 아래 여백, 카드 위 선택 하이라이트, 짝 없는 펜스 제거를 확인한다. 스타일별 세부 항목은 [결과 창 코드 표시](code-display.md)의 확인 절을 따른다.
- [ ] Claude 모델 선택(#48): 설정의 번역 탭에 Haiku 5.5·Sonnet 5.5·Opus 5.5·Fable 5.1이 보이고 각 선택으로 실제 번역된다.
- [ ] 설정 창(#44·#49): 높이 376pt 창에서 Codex를 선택했을 때 다섯 행과 실행 파일 경로·버전 줄이 잘리지 않고, Codex 연결·Fast·복사 형식 선택이 재실행 뒤에도 유지된다.
- [ ] 꼬리 입력 뒤 복사·삽입(#53): 링크가 있는 복사 뒤에 문단을 덧붙여 꼬리로 번역한 결과를 복사·삽입하면 위쪽 링크·칩과 덧붙인 문단이 함께 들어간다.

앱 밖 확인(#52):

- [ ] 리뷰 반영(`f6e9563`·`3b13739`) 뒤 실제 구독 live 테스트(`DEEPK_RUN_LIVE_TRANSLATION_TESTS=1 scripts/test-incremental-live.sh`)를 다시 실행한다.
- [ ] 실제 Codex 요청을 캡처해 원문의 `$스킬이름`이 SKILL.md를 주입하지 않는지 확인한다. 현재 근거는 upstream 파서 소스와 가짜 서버다.

## 명시 경계(U1) 실제 앱 확인 대기 — 2026-10-13

[명시 경계 번역](explicit-boundary-translation.md)은 창 없는 AppKit 테스트(`SourceEditorTests`, `TranslationResultTextViewTests`, `StableAppendIntegrationTests`)와 가짜 제공자로만 확인했다. GUI 테스트와 실제 앱 실행은 하지 않았다. 확인하면 앱·OS 버전과 함께 이 절에 기록한다.

- [ ] `DEEPK_RUN_GUI_TESTS=1 ./scripts/test-input.sh`(창을 연다). 원문 편집기 생성 경로를 앱과 같은 `SourceEditor.makeScrollView`로 바꿨고, `---⏎⏎` 바로 뒤 한글 조합 유지와 조합 중 ⌘↩(확정 뒤 덧붙임)를 더했다. 구현 단계에서는 컴파일만 했다.
- [ ] 코드 기호와 링크가 있는 Chrome 문단을 ⌘C 두 번 → 번역 창의 원문 끝을 클릭 → ⌘↩ → 다른 메시지 ⌘V. 요청 1회, T(A) 링크 클릭, 결과 선 표시, 복사·삽입에 `---` 없음.
- [ ] A 번역 중 `⌘↩ ⌘V B ⌘↩ ⌘V C`. 요청 3회가 차례로, 선 2개, 원문 가로줄 2개.
- [ ] ⌘C 두 번 직후(번역 창을 클릭하기 전, 포커스는 원래 앱) ⌘↩는 deepK가 받지 않고 원래 앱이 받는다. 메일·댓글 제출이 일어나지 않게 텍스트 편집기 같은 안전한 앱에서 확인하고, README 안내('먼저 번역 창을 클릭')가 충분한지 본다.
- [ ] 결과 창을 클릭한 상태에서 ⌘↩는 원문 끝에 덧붙이고 커서를 원문 창으로 옮긴다. 설정 창이 key이면 ⌘↩는 아무 일도 하지 않는다. 열린 ```` ``` ```` 펜스 안에서도 아무 일도 하지 않는다(메뉴 항목이 꺼져 키를 먹는다).
- [ ] 한글 조합 중 ⌘↩, 가로줄 바로 아래 줄에서 한글 입력. 가로줄 유지, 조합 밑줄·후보 창 정상. (`---` 같은 줄 뒤에는 커서가 가지 않으므로 `---한`은 입력으로 만들 수 없다.)
- [ ] 원문 창 가로줄(2026-10-13 사용자 피드백으로 회색 대시+가는 선에서 바꿈): `---` 글자는 보이지 않고 글 왼쪽 끝부터 스크롤바 여백 앞까지 선 하나만 보인다. `---`를 치는 순간(한글 입력기를 켠 채로도) 선이 그어지고 커서가 그 아래 새 줄로 간다. 커서는 선 위에 서지 않는다: 선의 위쪽 절반을 클릭하면 선 위 줄 끝, 아래쪽 절반이면 아래 줄 첫머리에 서고(누른 채 조금 끌어도 같다), ↑·↓·←·→로 지나가면 건너뛴다. 맨 아래 선 밑을 클릭하거나 ↓를 누르면 그 아래에 새 줄이 생긴다. 선 바로 아래 줄 첫머리에서 ⌫를 누르면 선이 통째로 지워진다. 타이핑·붙여넣기·지우기·창 크기 전환(작게↔크게, 글꼴 13↔14pt)·스크롤 뒤에 선이 그 줄 가운데에 있고 예전 자리에 남지 않는다. 선의 다시 그리기는 창 없는 테스트로 확인할 수 없다.
- [ ] 원문 창 스크롤바 여백: 긴 원문을 스크롤하거나 마우스를 오른쪽 끝에 올려 overlay 스크롤바가 굵어져도 글자를 가리지 않는다(번역 창과 같은 18pt). 스크롤바가 나타나고 사라질 때 줄바꿈이 바뀌지 않는다.
- [ ] legacy 스크롤바(마우스 연결 또는 시스템 설정 '스크롤 막대 보기: 항상'): 두 창 모두 글과 원문 가로줄이 스크롤바 바로 앞까지 오고 그 사이에 18pt 빈 띠가 없다. 창이 열린 채로 설정을 바꿔도(자동↔항상) 줄바꿈이 새 방식에 맞게 바뀐다.
- [ ] 흰 배경에서 결과 선과 원문 가로줄(둘 다 `separatorColor` 1pt)의 대비. 작게·크게 창. 패널이 라이트로 고정이라 다크 모드는 확인하지 않는다.
- [ ] 위·아래·가운데 블록 삭제에서 네트워크 없이 즉시 복원(연결을 끊고 확인).
- [ ] 완료된 B를 고칠 때 T(B)가 비는 동안의 느낌(D4), '전체 다시 번역'이 블록마다 도는 시간.
- [ ] 자동 방향에서 한국어 A 뒤 펜스 없는 짧은 명령(`docker compose up -d`, `make test`)은 영어로 확신해 A부터 다시 번역한다(측정값은 계획 문서 '구현 결과'). 실제 사용에서 거슬리는지 본다.

## 하단 막대 실제 앱 확인 대기 — 2026-10-13

[하단 막대](window-size-and-layout.md#하단-막대--2026-10-13사용자-피드백)는 순수 함수 테스트(`TranslationFooterStateTests`), 앱 상태·창 없는 그리기 테스트(`PermissionPresentationTests`), 결과 글 메뉴 테스트(`TranslationResultTextViewTests`)로만 확인했다. 앱은 실행하지 않았다. 확인하면 앱·OS 버전과 함께 이 절에 기록한다.

- [ ] 작게·크게 창에서 막대 높이(40/44), 왼쪽 끝이 원문 글, 오른쪽 끝이 결과 칸 여백과 맞는지. 두 글 칸이 한 줄에서 끝나는지(크게). 작게 창에서 원문 가로줄·칸 구분선·결과 단위 선의 왼쪽 끝이 한 세로줄(18)에 맞는지(`A⏎⏎---⏎⏎B` 번역).
- [ ] 평소 막대 왼쪽이 비어 있고, 마우스를 올리면 `<제공자> · <모델> · n.n초`가 조용히 나타났다 사라지는지. 제공자를 바꾼 뒤에도 보이는 결과의 원래 모델을 가리키는지. 다른 앱에서 ⌘C 두 번으로 띄운 직후(창을 누르기 전, deepK 비활성)에도 나타나는지(`.activeAlways` 추적). 상태 문구를 누르는 데 방해가 없는지.
- [ ] 번역 중 문구 뒤의 작은 진행 표시, ‘추가 내용 입력 중…’ → ‘추가 내용 번역 중…’에서 글자가 옆으로 움직이지 않는지. 오류 문구를 누르면 팝오버에 전체 문구, 툴팁에 제공자·모델.
- [ ] 입력 감시 권한이 없는 상태에서 번역한 뒤 다른 앱을 눌렀다 돌아와(활성화마다 감시 실패 안내가 다시 선다) 방향을 바꾸거나 ‘다시 시도’: 막대에 ‘번역 중…’과 진행 표시, 실패하면 그 오류가 보이고, 끝나면 감시 실패 안내가 다시 보이는지.
- [ ] ‘복사’를 누르면 그 알약이 ‘복사됨’으로 바뀌었다가 약 2초 뒤 돌아오는지, 그동안 알약 폭과 옆 버튼이 그대로인지, 막대 왼쪽에는 아무것도 뜨지 않는지. 읽기 전용 위치(Safari 본문 등)에서 ⌘C 두 번 뒤 막대에 삽입 불가 안내가 없고 ‘복사’ 툴팁에 있는지.
- [ ] ‘삽입’(밝은 회색)·‘복사’(먹색) 알약의 높이·모서리·글자, 누를 때의 눌림, 꺼진 ‘복사’가 분명히 꺼져 보이는지. 글자 버튼(‘다시 시도’·‘다시 번역’·‘↓ 새 번역 보기’)이 강조색이고 꺼진 ‘다시 번역’이 흐린지.
- [ ] 결과가 없을 때 결과 칸 왼쪽 위의 문구·진행 표시와 막대가 같은 말을 되풀이하지 않는지. 첫 번역이 제공자 오류로 끝나면 긴 오류가 빈 칸에 여러 줄로 보이고 선택·복사되는지. 긴 번역 중 아래에 글이 붙으면 막대 오른쪽 ‘↓ 새 번역 보기’로 이동하는지.
- [ ] 결과 글을 오른쪽 클릭(또는 ⌃클릭)하면 메뉴 맨 위에 ‘전체 다시 번역’, 그 아래 구분선과 찾아보기·복사·서비스 등 기본 항목이 있는지. 번역 중에는 꺼져 있는지. 고르면 블록마다 다시 번역하는지. 결과 글 아래 빈 곳이나 스크롤바에서는 메뉴가 없어도 된다.
- [ ] 키보드 탐색(시스템 설정의 키보드 탐색 켬)에서 막대 버튼에 Tab으로 갈 수 있는지와 VoiceOver가 상태·버튼 이름을 읽는지. 알약은 사용자 정의 버튼 스타일이다.
