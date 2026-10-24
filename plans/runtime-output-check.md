# 실행 중 번역 결과 검사

상태: 2026-10-12 구현(PR A), 2026-10-13 PR #55로 main에 머지했다. 테스트·빌드와 저장된 벤치마크 출력 검사만 했다. 실제 앱 확인은 아직이다.

## 1. 문제

- impeccable.style 문서에서 코드 위젯이 있는 구간을 복사하자 Haiku 5.5가 영어 원문을 그대로 돌려줬다. 앱은 빈 결과만 걸렀으므로 이 답을 성공으로 보여 주고 300초 동안 캐시했다(로그 `trigger→final 1771 ms`). 보강 전 벤치마크에서도 60개 중 3개가 같은 실패였다.
- 한국어 결과에 중국어 간체가 섞였다("보안이 确保된", "궁금한 点이").
- 두 출력 모두 `TranslationOutputLint`(`sourceEcho`, `foreignScript`)가 잡지만, 이 검사기는 벤치마크·테스트에만 연결돼 있었다.

## 2. 결정

- 원문 반복만 다시 요청한다. 첫 시도에서 한 번, 새 요청으로 보낸다. 스트리밍 중에 찾으면 남은 스트림을 기다리지 않고 바로 끊는다.
- 다시 요청한 답도 원문 반복이면 결과로 보여 주되 경고를 붙이고 캐시하지 않는다. 복사·삽입은 막지 않는다.
- 한국어 결과의 한자는 Unihan 한글 독음으로 결정적으로 바꾼다(确保 → 확보). 바꾼 결과를 캐시한다.
- 지울 수 있는 머리말("번역: …")은 완료 때 잘라 낸다.
- 나머지 규칙은 로그만 남긴다. 다시 요청하지 않는다.
- 모든 검사의 원문은 모델이 실제로 본 글(`TranslationRequest.modelInput`)이다. `request.input`은 쓰지 않는다.

## 3. 규칙별 처리

| 규칙 | 처리 |
| --- | --- |
| `sourceEcho` | 첫 시도: 1회 다시 요청(캐시를 거치지 않음). 둘째 시도: 경고 행과 '전체 다시 번역', 캐시 안 함 |
| `foreignScript` 중 한국어 결과의 한자 | 독음 치환. 조각과 완료 결과 모두 |
| 독음이 없거나, 코드·URL 안이거나, 범위 조건(5절) 밖의 한자 | 그대로 두고 수만 기록 |
| `foreignScript` 중 가나, 영어 결과의 한글·한자 | 로그만(#47 재설계 대기) |
| `preamble` fixable(첫 줄, 콜론까지) | 완료 때 잘라 냄. 잘라 낸 글을 캐시. 머리말과 번역문을 구별할 수 없는 원문(5절)은 보지 않음 |
| `preamble` retry, `literalMismatch`, `structure` | 로그만 |

## 4. 처리 순서

조각(`receivePartialText`)마다 `TranslationOutputCheck.partial`을 거친다.

- 첫 시도는 조각이 24 UTF-16 단위 이상 늘 때마다 원문 반복을 본다. 반복이면 요청 작업을 취소하고 초안을 지운 뒤 같은 원문을 `attempt: 2`로 새로 요청한다. 새 요청 ID 때문에 첫 시도의 늦은 조각·완료는 `accepts()`가 버린다.
- 반복이 아니면 한자를 고친 앞부분을 보여 준다. 판정이 남은 끝 한자 묶음은 다음 조각까지 보류한다. 보이는 글은 뒤에만 붙는다.
- 조각이 없는 경로(Claude one-shot·대체 경로 등)는 완료 때만 다시 요청한다.

완료(`complete` → `finalizeOutput`)는 아래 순서다. 번호는 PR B와의 약속이고, B가 6번에 코드 블록 가드를 넣는다.

1. `review`: 한자 치환과 원문 반복 판정(고치기 전 글 기준)
2. 반복이고 첫 시도면 `retryAfterEcho(early: false)`
3. `TranslationMarkup.normalized(review.text, source: request.input)`
4. 빈 결과 검사
5. 지울 수 있는 머리말 제거. 원래 문자열에서 잘라 내 CRLF가 그대로다
6. (PR B) `CodeBlockGuard.restore`
7. 크기 검사
8. 세그먼트에 `unresolvedEcho` 표시
9. 캐시. 반복이 남은 세그먼트와 그것을 포함한 접두는 저장하지 않는다
10. 보고(`onOutputReport`)

## 5. 판정

**원문 반복** (`TranslationOutputLint.EchoProbe`)

- 원문의 문장 중 25자 이상, 원문 언어 글자 10자 이상, 코드처럼 보이지 않고, 영어는 4낱말 이상에 기능어가 있는 문장이 후보다. 번역에서도 그대로 두는 것은 후보에서 뺀다: 제목, 따옴표로 감싼 문장, 링크만 있는 줄, 참고문헌 항목. 참고문헌 항목은 줄 머리(`[n]`·`n.`·`-` 뒤)가 저자 이름(Vaswani, A. 등)이고 연도·et al.·doi가 있는 줄이다. ACL·ACM 형식도 참고문헌 항목이다. 이름이 앞에 오는 저자(Jacob Devlin) 뒤에 쉼표나 " and "가 오고, 줄 안에 ". 2019." 같은 연도 문장이 있는 줄이다. 본문 문단 속 인용("Titanic (1997)", "Vaswani et al. introduced", "John Smith, the CEO, said in 2019")은 후보로 남는다.
- 판정은 비율이다. 결과에 그대로 있는 후보의 글자 수 / 모든 후보의 글자 수가 0.4 이상이거나, 2문장 이상이면서 0.3 이상이면 반복이다. 후보가 2개 이하인 짧은 원문은 모든 후보가 그대로 있을 때만 반복이다. 로그·오류 문구 한 줄을 영어 그대로 두는 번역은 정상이라서다("added 245 packages …" 줄을 둔 npm 안내).
- 펜스 블록·인라인 코드는 원문과 결과 양쪽에서 빼고 비교한다. 완료 판정은 `TranslationMarkup.roles`처럼 짝 없는 펜스를 스트레이로 보고, 조각 판정은 왼쪽만 보는 인과 모드라 코드를 더 넓게 본다.
- 펜스 줄의 정보 문자열은 결과 창(`TranslationMarkup.reading(of:)`)과 똑같이 읽는다. 아는 태그와 속성이 붙은 정보 문자열은 닫는 줄까지 가는 블록이다. 아는 명령(```pwd)과 그 밖의 글(```npm install)은 채팅식 블록이라 백틱으로 끝나는 코드 줄에서도 닫힌다. 모르는 한 낱말(```node)은 펜스 뒤 첫 비어 있지 않은 줄이 정한다. 린트 파일은 혼자 컴파일되므로 태그·명령 목록을 복제했다. 한쪽 목록을 바꾸면 다른 쪽도 바꾼다. `HanjaRepairTests`의 판정 일치 테스트가 두 쪽이 같게 읽는지 확인한다.
- 공백(U+00A0 포함)은 빈칸 하나로, 보이지 않는 문자(U+00AD, U+200B–200D, U+2060, U+FEFF)는 빼고, 둥근 따옴표는 곧은 따옴표로 맞춘다.
- 찾은 문장은 글이 길어져도 사라지지 않으므로, 조각에서 반복이면 완료 글에서도 반복이다. 그래서 조기 중단이 완료 판정과 어긋나지 않는다.
- `lint()`는 한 문장 규칙을 그대로 쓴다. 코드를 뺀 산문 문장(위의 길이·글자·코드·기능어 조건) 하나라도 결과에 그대로 있으면 `sourceEcho`다. 그대로 두는 것(제목·따옴표 문장·링크만 있는 줄·참고문헌 항목)은 거르지 않으므로 벤치마크 판정이 줄지 않고 기준선도 그대로다. 보고의 `rules`에서는 `sourceEcho`를 실행 중 판정으로 바꾼다.

**머리말** (`TranslationOutputLint.removingPreamble`)

- 결과 첫 줄 맨 앞의 머리말 문구부터 같은 문장 안의 첫 콜론까지 잘라 낸다.
- 원문만으로 머리말과 번역문을 구별할 수 없으면 보지 않는다. 런타임 제거와 `lint()`의 `preamble` 보고가 같은 조건을 쓴다.
  - 원문에 라벨·지시문 줄이 있다("번역: …", "Time: 3 PM").
  - 원문의 어느 줄이 콜론 앞에서 번역을 말한다(번역, translat-, 翻訳, 翻译). 예: "다음은 이 책의 영어 번역본에 대한 소개이며 … 설명한다: …"의 충실한 번역 "Below is an introduction to the English translation of this book, … like this: …". 결과의 콜론이 원문 콜론의 번역이라 잘라 내면 번역문이 사라진다.
  - 콜론 없는 원문의 낱말("start translating …")만으로는 끄지 않는다. 그런 원문에 붙은 "다음 텍스트를 한국어로 번역해 주세요:"가 벤치마크에서 실제로 나온 머리말이다(haiku55-prompt-v2 en-long-1#1).

**한자 치환** (`HanjaReading`, `HanjaRepair`)

- 데이터: Unicode 18.0.0 Unihan의 `kHangul`과 간체→번체 변형(确 → 確 → 확). `scripts/generate-hanja-readings.py`가 `HanjaReadingData.swift`(약 58KB)를 만든다. Unihan.zip SHA-256을 고정했고, `--check`로 커밋본과 비교한다. Unicode License v3 고지는 생성 파일 머리말과 README에 있다.
- 자주 쓰는 독음은 `OVERRIDES`로 정한다(樂 락, 率 률, 不 불 등 31자). 번체 여러 글자를 합친 간체 4자는 `MERGED`로 중국어에서 흔한 쪽 번체 글자의 독음을 쓴다(征 → 徵 징 特征 특징, 于 → 於 어, 么 → 麽 마 什么 십마, 净 → 淨 정). 자기 독음(征 정, 于 우)이나 변형 순서(么 → 幺 요)를 따르면 뜻이 다른 낱말이 되고, 净은 독음이 없었다. 이 독음은 각 글자의 kHangul에 없으므로 `OVERRIDES`의 검사 대신 번체 글자의 kHangul에서 가져온다. 두음법칙(年末 → 연말, 2015年 → 2015년), 모음·ㄴ 받침 뒤 렬·률 → 열·율, ㄷ·ㅈ 앞의 不 → 부를 적용한다.
- 모델 입력에 있는 한자는 고치지 않는다. 이어진 묶음에 그런 한자가 하나라도 있으면 묶음 전체를 둔다. 보호 기준이 그 단위의 모델 입력뿐이라 문단 캐시는 키만으로 정해진다.
- 코드 블록, 인라인 코드, URL 안은 고치지 않는다(번역된 코드 주석 포함). `<aN>` 링크 사이의 낱말은 번역된 산문이라 고친다.
- 범위 조건: 4자 이하 묶음이고, 결과의 앞쪽 어디든(앞 줄 포함) 한글이 있었거나 바로 뒤(공백·탭 3개 이내)가 한글일 때만 고친다. 목록 항목·표 칸·제목에 혼자 놓인 낱말도 고친다. 중국어 문단이 통째로 온 답은 한글 음 나열로 바꾸지 않고 그대로 둔다. "앞쪽 어디든"은 일부러 넓게 잡았다.
- 그래도 두는 묶음(`kept`로 센다):
  - 바로 앞 글자가 가나이거나, 바로 뒤(공백·탭 3개 이내를 건너뛴) 글자가 가나(ー 포함)나 전각 문장 부호(U+3000–303F의 、。「」 등, ，：；！？)인 묶음. 한국어 문단 뒤에 온 중국어·일본어 문장이다("首先，确保安全。", "まず、安全を確認します。"). 한국어 문장은 보통 ASCII 문장 부호를 쓰므로 "보안이 确保된", "确保."는 그대로 고친다.
  - 괄호 바로 안에 꼭 맞게 놓인 묶음("예(禮)와 정명(正名)", "（禮）"). 한글 낱말에 붙인 한자 병기라 독음으로 바꾸면 "예(예)"가 된다.
  - 모두 왼쪽과 이미 읽은 다음 글자로만 정하므로 조각과 완료의 판정이 같다.
- 한자와 한글 음절은 모두 UTF-16 한 단위라 길이와 위치가 그대로이고 ASCII는 바뀌지 않는다. 결과 창의 블록·스팬 판정과 뒤에만 붙는 표시가 그대로 유지된다.

## 6. 화면

| 상태 | 하단 막대 왼쪽 | 동작 |
| --- | --- | --- |
| 다시 요청 중 | 스피너 + "원문이 그대로 나와 다시 번역하는 중…" | 없음 |
| 다시 요청한 답도 반복 | 주황 경고 표시 + "원문이 그대로 남아 있을 수 있습니다" | '전체 다시 번역'. 아래에 새 번역이 있으면 '↓ 새 번역 보기'가 앞선다. 경고는 반복 세그먼트가 문서에 남는 동안 계속되므로, 뒤에 이어 붙인 문단으로 가는 동작과 VoiceOver 이름("아래에 추가된 번역으로 이동")이 가려지지 않게 한다. 경고 문구는 그대로 남는다 |
| 다시 요청 성공 | 평소와 같음 | 평소와 같음. 시간은 두 시도를 합친 값 |

2026-10-14 명시 경계(U1) PR에서 창 아래쪽을 막대 하나로 줄이며 예전 결과 칸 상태 행이 없어졌다. 위 문구와 동작은 그 막대의 왼쪽 칸과 오른쪽 글자 버튼으로 옮겼다(`TranslationFooterState`). 진행 표시는 문구 뒤, 경고 표시는 문구 앞이다. 우선순위는 [창 크기와 배치](window-size-and-layout.md#하단-막대--2026-10-13사용자-피드백)에 있다.

- 상태는 `store.outputNotice`(저장소 상태)에서 오므로 복사·삽입 피드백이 가리지 않는다. 하단 표시 우선순위는 그대로다.
- 다시 요청할 때 완료된 글이 화면에 없으면 표시 식별자를 새로 만든다(결과 창이 처음부터 그린다). 이어 붙이는 꼬리의 재요청은 앞의 완료 글을 그대로 둔다.
- VoiceOver: 다시 요청할 때 "원문이 그대로 나와 다시 번역합니다", 반복이 남으면 "번역 결과에 원문이 그대로 남아 있을 수 있습니다"를 알린다.
- 경고가 붙은 결과도 복사·삽입할 수 있다. 같은 글을 다시 복사하면 지금처럼 중복으로 보고 요청하지 않는다. 원문을 지우고 다시 복사하거나 '전체 다시 번역'을 누르면 첫 시도부터 다시 요청한다.

## 7. 비상 스위치

재빌드 없이 끈다. 앱을 다시 실행하면 반영된다.

```sh
defaults write com.deepk.app outputEchoRetry -bool false    # 다시 요청·조기 중단을 끈다. 반복은 바로 경고와 함께 보이고 캐시하지 않는다
defaults write com.deepk.app outputHanjaRepair -bool false  # 한자 치환을 끈다
defaults delete com.deepk.app outputEchoRetry               # 기본(켜짐)으로 되돌린다
```

앱은 시작할 때 `TranslationStore.applyOutputCheckSwitches(from:)`로 읽는다. 키가 없으면 켜짐이다.

## 8. 로그

`log stream --info --predicate 'subsystem == "com.deepk.app" && category == "latency"'`로 본다. 원문·번역문은 남기지 않는다.

```
trigger→first partial 560 ms provider=claude attempt=1
output echo retry 820 ms early=1 unit=document provider=claude coverage=0.57 candidates=4
trigger→first partial 2950 ms provider=claude attempt=2
output check accepted attempt=2 unit=document provider=claude rules=none coverage=0.00 candidates=4 hanja=0 unreadable=0 kept=0 incode=0 preamble=0 code=0:0:0:0
trigger→final 4100 ms provider=claude retries=1
```

- `output check`의 결과는 `accepted` 또는 `unresolvedEcho`다. `rules`는 마지막 글의 `lint()` 규칙 이름이고, `sourceEcho`만 `review`의 비율 판정으로 바꾼다.
- `hanja`는 바꾼 글자, `unreadable`은 독음이 없어 둔 글자, `kept`는 범위 조건이나 원문 한자 때문에 둔 글자, `incode`는 코드·URL 안이라 둔 글자다.
- `unit`은 전체 번역(`document`)과 이어 붙인 문단(`tail`)을 가른다.
- `code`는 PR B의 코드 블록 가드 결과다. 앱이 펜스를 씌운 블록을 그대로·되돌림·다시 펜스·다시 넣음 순으로 센다(`kept:restored:refenced:inserted`).

## 9. 알려진 한계

- 스트리밍 중 보이는 머리말은 완료 때 한 번 제자리에서 지워진다.
- 조기 중단은 Claude 프로세스 기동 한 번(약 1.5초)을 더 쓴다. 취소한 프로세스가 끝나기 전에 같은 차례에서 다시 요청하므로, 재요청은 대기 프로세스 없이 새로 띄운 프로세스(`onDemandStream`)가 맡는다. 대신 반복 스트림의 나머지를 기다리지 않는다.
- 한자 치환은 조각과 완료 모두 왼쪽만 보는 인과 모드다. 짝 없는 맨 펜스(코드 안에서 시작한 선택의 닫는 줄 등) 뒤의 글은 코드로 보므로 그 뒤의 한자는 고치지 않고 `incode`로 센다.
- 범위 조건은 앞의 한글을 결과 전체에서 본다. 한국어 문단 뒤에 온 중국어·일본어 문장은 전각 문장 부호와 가나 덕분에 대부분 그대로지만, ASCII 쉼표·마침표로 끊긴 4자 이하 묶음("首先, 确保安全.")은 독음으로 바뀐다(5자 이상 묶음은 그대로). 한글이 나오기 전의 묶음은 바로 뒤가 한글일 때만 고친다.
- 두음법칙의 낱말 경계는 바로 앞 글자로 짐작한다. 글자·숫자 바로 뒤면 낱말 안, 공백 등의 뒤면 첫머리로 본다. 그래서 "데이터를利用"은 리용, "3 年"은 3 연이 된다.
- `~~~…~~~` 구간은 기본 린트처럼 원문 반복 후보에서 뺀다. 그 안의 산문이 그대로 나와도 반복으로 세지 않는다.
- 조각마다의 검사(원문 반복, 한자 치환)는 결과 길이에 선형이다. 입력 한도(4,000자)에서는 무시할 만하다.
- 가나, 영어 결과의 한글·한자는 고치지 않는다(#47).
- `benchmark-claude.swift`는 원래 출력을 그대로 검사한다. 앱이 보는 값(반복 비율, 치환 뒤 `foreignScript`)은 `scripts/lint-benchmark-outputs.sh`가 함께 보여 준다.

## 10. 검증

- `./scripts/test.sh`: `TranslationOutputLintTests`, `HanjaRepairTests`(코드 판정이 `TranslationMarkup`과 같은지: 고정 픽스처와 섞은 줄 2만 건), `TranslationOutputCheckTests`, `OutputCheckStoreTests`(가짜 번역기로 조기 중단·완료 시 재요청·반복 2회·꼬리·편집 취소·킬 스위치와 그 UserDefaults 읽기·한자·머리말·채팅식 펜스 뒤 로그 블록 오탐·로그 한 줄을 둔 짧은 원문·재요청 중 결과가 같은 편집), `StableAppendIntegrationTests`(한자 치환 스트림이 코드 블록 옆에서도 뒤에만 붙음), Claude·Codex 전송 테스트(스트리밍 중 취소와 같은 차례의 재요청, 대기 프로세스 재기동, 늦은 조각 버림).
- `./scripts/lint-benchmark-outputs.sh benchmarks/translation-samples-v2.json benchmarks/runs/20261008-haiku45-quality-v2.json benchmarks/runs/20261008-haiku55-quality-v2.json benchmarks/runs/20261008-haiku55-prompt-v2.json`: 기존 줄은 기준선과 같다(0/60, 3/60 sourceEcho, 2/60 머리말 1·foreignScript 1). 반복 비율은 알려진 반복 3건만 1.00이고 나머지 177개는 0.00이다. 치환 뒤 `foreignScript`는 0/180이다. 2026-10-13 리뷰 반영(짧은 원문 규칙, 머리말 조건, ACL 참고문헌, 괄호 병기, 중국어·일본어 문장, `MERGED`) 뒤에도 출력이 같다.
- `python3 -I scripts/generate-hanja-readings.py --unihan <Unihan.zip> --check`: 최신.
- 미확인(사용자 승인 필요, 쿼터 사용): 실제 앱에서 impeccable 구간, 참고문헌·내비게이션 같은 오탐 유발 페이지, 한국어 문단(ko→en), Codex 2회.
