# 명시 경계 번역 — U1 '구분선 그대로, 경계로 인정'

상태: 2026-10-13 구현 완료. 2026-10-14 최신 main(PR #55–#60)과 합쳐 브랜치 `feature/explicit-boundary`로 PR을 올렸다(이슈 #63). 처음 구현 기준은 `dd2f0f9`였다. 합치며 바뀐 점은 10절 끝 '최신 main과 합치기'에 있다. 실제 앱 확인은 아직이다. 초안을 독립 검토(P0 2건, P1 4건, P2·P3)와 리드 결정(9절 D1–D9)으로 고쳤다. 시안은 저장소 밖 pen.dev '이어서 번역' U1이다. 1–9절은 착수 전 계획이고, 실제 구현과 계획과 다른 점은 10절에 있다. 실제 앱 확인은 [Mac 통합 확인](mac-integration-checks.md)의 '명시 경계(U1)' 절에 남겼다.

## 1. 요청과 완료 기준

사용자는 A의 번역을 보면서 원문 창 끝에 `---` 줄을 치고 B를 ⌘V로 붙인다. 지금은 A에 코드 기호(`|`, `=`, 백틱)가 있거나 A가 구조 복사(`plans/result-structure.md` 2단계)이면 꼬리로 나누지 못해 원문 전체를 다시 번역한다(약 5초). 그 사이 앞 번역의 표현이 바뀌고, 링크·칩이 사라지고, `---`가 결과에 그대로 찍힌다.

사용자 결정(U1 승인): "`---` 뒤에 선이 그어져 위·아래를 따로 다룰 수 있는 구조가 좋다." 규칙은 하나다. **펜스 밖의 `---` 줄은 단위를 끊는다.**

```text
원문  A ⏎⏎ --- ⏎⏎ B        → 요청 B뿐
결과  T(A)
      ───────────────       ← 글자가 아닌 1pt 선
      T(B)
복사  T(A) ⏎⏎ T(B)         ← '---'도 선도 없음
```

필수 합격선:

- [ ] 코드 기호나 구조 복사가 있는 A 뒤에 독립된 `---` 줄을 두고 B를 붙이면 요청은 B 하나다. T(A)의 문자열·링크·칩은 바뀌지 않는다.
- [ ] 구분선을 치는 모든 중간 상태(`⏎`, `⏎⏎`, `-`, `--`, `---`, `---⏎`)에서 T(A)가 흐려지거나 사라지지 않고 요청이 0회다.
- [ ] A가 번역 중일 때 같은 입력을 해도 A 요청을 유지하고, A 완료 뒤 B만 요청한다. 빈 원문에 ⌘V A 후 디바운스(500ms) 안에 ⌘↩·⌘V B를 해도 첫 요청은 A다.
- [ ] 구조 복사 요청(markup 있음)을 뺀 모든 요청의 `request.input`에 경계 구분선과 입력 중 대시가 없다. 첫 요청, 증분 꼬리, '전체 다시 번역', 제공자·방향 재번역 모두 첫 경계에서 자른다(D1).
- [ ] 한 꼬리 안의 여러 경계(붙여넣은 B 안의 `---`, A 번역 중 `⌘↩ ⌘V B ⌘↩ ⌘V C`)는 블록마다 차례로 요청한다. 같은 원문은 입력 속도와 관계없이 같은 단위·선·결과가 된다.
- [ ] 결과 창에 `---` 글자가 없고, 명시 경계로 나뉜 단위 사이에 1pt 선을 그린다. 복사 버튼·삽입·⌘C·드래그·Services는 단위를 빈 줄 하나로 잇고 `---`나 선 문자가 없다.
- [ ] B 뒤에 빈 줄을 두고 C를 붙일 때 B와 C만 일반 텍스트면 C만 요청한다. A는 검사하지 않는다.
- [ ] 아래 블록 삭제(→ `A`, `A⏎⏎---`)는 네트워크 없이 T(A)로, 위 블록 삭제(→ `B`, `---⏎⏎B`)는 네트워크 없이 T(B)로, 가운데 블록 삭제(A---B---C → A---C)는 C 캐시(300초·32개 안)로 네트워크 없이 돌아간다. 완료된 B를 고치면 B′만 요청하고 T(A)는 유지한다.
- [ ] 자동 방향(기본값)에서 코드 위주 B도 B만 요청한다.
- [ ] 원문 창에서 경계로 인정된 구분선 줄만 마크다운 가로줄처럼 대시 없이 선 하나로 보인다(처음 계획은 회색, 2026-10-13 사용자 피드백으로 바꿈, 10절 '원문 창 가로줄'). 글자는 바뀌지 않는다. 인정되지 않은 줄(열린 펜스 안, 구조 복사 원문 안, 빈 줄 없는 맨 앞 머리말)은 보통 글이다.
- [ ] ⌘↩(편집 메뉴 '끝에 구분선 넣기'): deepK 창이 key(클릭해 활성)이면 포커스와 상관없이 원문 끝에 구분선을 덧붙이고 커서를 그 아래 빈 줄에 둔다. 다시 눌러도 중복되지 않고 요청은 0회다. 끝이 `-`·`--`이면 `---`로 채운다. 열린 펜스 안에서는 꺼진다.
- [ ] `A---`, `--- x`, `- 목록`, 들여쓴 `  ---`, 열린 ```` ``` ```` 안의 `---`는 경계가 아니며 지금 규칙을 따른다.
- [ ] Debug 빌드(`-Onone`)에서 `assertionFailure`가 한 번도 걸리지 않는다(3.5 I1). 원문 전체 4,000자 한도와 기존 테스트 전부를 유지한다.

## 2. 확인한 사실

| 위치 | 현재 계약 | U1에서 바꿀 점 |
| --- | --- | --- |
| `DeepK/Translation/IncrementalTranslationPlanner.swift:11-13` | prefix와 새 원문 전체가 모두 `isPlainText`일 때만 꼬리 | 명시 경계는 `isPlainText` 없이 꼬리. 빈 줄 경로의 검사 범위는 prefix의 마지막 경계 뒤(UTF-8 offset 하나, D8) |
| 같은 파일 `:17-25` | 빈 줄 경계는 개행 2개 이상. prefix 끝은 공백만 뗀다(`:22`). 구분자를 치는 중이면 빈 입력 꼬리 | prefix 끝의 GAP_END 전체(공백·구분선·입력 중 대시)를 떼고 계획한다. 꼬리 내용이 prefix 끝보다 앞에서 시작하면 nil(P0-1). 꼬리는 첫 명시 경계에서 자르고 끝 GAP_END를 뗀다 |
| 같은 파일 `:28-40` | `---`는 일반 텍스트다(목록 정규식이 `- `만 잡음). 그래서 꼬리 입력에 `---`가 들어가 모델이 되풀이한다 | 경계 구분선은 separator·trailing으로 간다 |
| `DeepK/Translation/TranslationDocument.swift:17-23` | separator가 비면 앞 개행을 separator로, 끝 공백을 trailing으로 옮김 | 변경 없음. 경계 바이트가 앞 단위 trailing과 뒤 단위 separator에 나뉠 수 있다 |
| 같은 파일 `:36-52` `covering` | 마지막 단위 뒤에는 공백만 허용(`:43`) | `isDelimiter`(구분선·입력 중 대시 허용, 펜스 검사) |
| 같은 파일 `:56-73` `retainingSuffix` | 남은 원문 앞의 개행만 separator로 둠(`:58`) | `leadingDelimiter`(구분선은 빈 줄이 함께 있을 때만) |
| 같은 파일 `:89-101` | `tailStart`·`lastSegmentStart` = 위 단위의 끝(결합 개행 앞) | 선 위치도 같은 규약 |
| 같은 파일 `:116-124` `join` | 결합 개행 = `max(2, separator 개행 + 앞 단위 끝 개행)`(`:122`). `⏎⏎---⏎⏎`이면 4개 | 명시 경계는 정확히 2개 |
| 같은 파일 `:103-105` `isBlank` | `CharacterSet.whitespacesAndNewlines`(NBSP·U+2028 포함) | 경계 문법의 공백도 이 집합을 쓴다(D8, P2-9) |
| `DeepK/Translation/TranslationStore.swift:820-883` `reconcileInput` | covering → 문서 기준 tail이 실패하면 token 검사(`:868-880`)보다 먼저 `invalidateResultAndWork`(`:863`) | covering → 문서 tail → token tail → `replanned` → invalidate. `replanned` 뒤에는 token을 취소한다(P0-2) |
| 같은 파일 `:888-900` `continuesFirstRequest` | 첫 요청 중의 꼬리도 planner로 판정, 언어 검사(`:899`) | 명시 꼬리는 D5 언어 규칙 |
| 같은 파일 `:902-916` `tailMatchesLanguage` | 문단마다 `dominantLanguage == 기준 언어` | 명시 꼬리는 반대 지원 언어로 확신할 때만 거절(D5) |
| 같은 파일 `:1021-1119` `startRequest` | 첫 요청 input·snapshot = 원문 전체. 구분자만인 꼬리는 `restoreCompletedDocument`가 먼저 처리해야 한다(`:1058-1062` `assertionFailure`) | markup이 없으면 첫 단위로 자른다. snapshot = prefix + separator + input. `request.markup = markup(for: input)` |
| 같은 파일 `:1121-1173` `complete` | `basis.input = token.snapshot`. 첫 단위가 끝나면 흐린 이전 번역을 놓음(`:1170`) | `basis.input = request.input`. 흐린 번역은 문서가 원문 끝까지 덮을 때 놓는다 |
| 같은 파일 `:1175-1183` `accepts` | snapshot 같음·공백 확장·planner 꼬리 | 코드 변경 없음(planner를 따른다) |
| 같은 파일 `:1185-1202` `finishSegment` | 첫 단위 뒤 `bypassCache`·`retryNeedsWholeDocument`를 끔(`:1192-1193`) | 원문 전체를 게시할 때만 끈다('전체 다시 번역'이 블록마다 캐시를 우회) |
| 같은 파일 `:1250-1275` `reuseEquivalentActiveRequest` | 원문 전체 key로 비교하고 input·snapshot을 원문으로 다시 묶음. 하네스: 경계 바이트 `⏎⏎`가 A.trailing으로, `---⏎⏎`가 B.separator로 나뉜다 | 비교·다시 묶기를 첫 단위 기준으로(P1-3) |
| 같은 파일 `:152-169` `TranslationDisplay`, `:255-275` `display` | text·tailStart·isStale·inline | `unitBreaks` 추가 |
| 같은 파일 `:298` `hasPartialResult` | 문서가 있고 결과가 없으면 참 | 흐린 이전 번역이 있는 동안은 거짓(상태 문구가 '번역 중…') |
| 같은 파일 `:697-725` `invalidateResultAndWork` | 전체 fallback 동안 이전 번역을 흐리게 보관 | 흐린 글의 선 위치도 보관 |
| 같은 파일 `:810-816` `documentMatchesSelection` | `basis.markup == markup(for: basis.input)`. 구조 복사 뒤 원문을 고치면 `activeMarkup == nil`이라 문서를 계속 쓴다 | 식은 그대로. 잘린 요청에서도 이 식이 성립하도록 `request.markup`을 정한다(3.6) |
| 같은 파일 `:664-690`, `:1036-1044` | 빈 원문 = 공백뿐. 4,000자는 원문 전체 기준 | 빈 원문 = `isBlankSource`(구분선·입력 중 대시 포함). 4,000자 유지 |
| 같은 파일 `:1230-1248` `cacheKey` | 모드 `paragraph-v1`·`document-v1`·`document-inline-v1`. `---`는 structured가 아님 | 버전 유지(3.13) |
| 같은 파일 `:521-529` `retranslateWholeDocument` | 원문 전체를 한 요청으로, 캐시 우회 | 블록마다 차례로, 캐시 우회 유지 |
| `DeepK/Translation/TranslationResultTextView.swift:7-22`, `:109` | `TranslationResultContent`(Equatable). 같은 내용이면 갱신하지 않음 | `unitBreaks` 필드. 비교에 자동 포함 |
| 같은 파일 `:81` | 결과 뷰는 TextKit 1(`usingTextLayoutManager: false`) | 선은 `layoutManager`로 위치를 구한다 |
| 같은 파일 `:119-121`, `:210-211`, `:471-472` | tailStart를 `displayOffset`으로 변환. `fences`·`copyableLength`는 매 갱신 대입하는 속성 | `unitBreaks`도 같은 방식. 변환 결과는 캐시한다(P2-11) |
| 같은 파일 `:610-626` `draw` | 코드 박스·칩을 `super.draw` 전에 뷰 좌표로 그림 | 선도 같은 자리에서 |
| 같은 파일 `:715-728` | ⌘C·드래그·Services는 저장소 문자열(= `displayText`) | 선은 글자가 아니므로 변경 없음 |
| `DeepK/Translation/TranslationMarkup.swift:239-245` | `displayOffset(of:in:limit:inline:)`은 부를 때마다 prefix를 다시 파싱 | 선 위치 변환에 쓰고 결과를 캐시 |
| 같은 파일 `:601`, `:666` | `openFence`는 private. 닫히지 않은 bare ```` ``` ````는 완료 시 stray | 경계 펜스 검사에 재사용하지 않는다 |
| `DeepK/Translation/TranslationView.swift:31` | 창 구분선 = 1pt `separatorColor` | 결과 선도 같은 색·두께 |
| 같은 파일 `:130-132`, `:180-185`, `:191-194`, `:241-243` | SourceEditor 생성, ResultPane 내용, '전체 다시 번역' 메뉴·버튼 | 값 전달만. 버튼 유지(이제 블록마다) |
| `DeepK/Translation/SourceEditor.swift:17` | `Editor()` = TextKit 2(하네스 확인) | TextKit 2 유지. 회색은 rendering attribute(D6) |
| 같은 파일 `:19-21` | 대시·따옴표·텍스트 치환 끔. `---`가 em dash로 바뀌지 않음 | — |
| 같은 파일 `:60-66` | `editor.string =`은 임시 속성을 지우고 커서를 끝으로 | 회색을 다시 단다 |
| 같은 파일 `:78-82` | 재정의한 `unmarkText`가 조합 중이었으면 `onEdit`을 한 번 더 보냄 | ⌘↩를 조합 중 누르면 `onEdit`이 2회다 |
| 같은 파일 `:84-90`, `allowsUndo` 미설정 | keyDown은 Esc만. ⌘Z는 원문 창에서 동작하지 않음 | ⌘Z는 후속 |
| `DeepK/DeepKApp.swift:63-103` | 단축키: `,` `q` `w` ⌘⇧E `z` `x` `c` `v` `a`. ⌘↩ 없음. `.keyboardShortcut`·`CommandMenu` 없음 | 편집 메뉴에 항목 추가 |
| `DeepK/AppModel.swift:244`, `:1211` | 번역 창과 설정 창의 delegate가 모두 AppModel | 메뉴 target은 전용 객체 |
| `DeepK/AppModel.swift:1092`, `:1098` | 패널이 `.aqua`와 `.preferredColorScheme(.light)`로 고정 | 라이트·다크 확인은 의미 없다. 흰 배경 대비만 확인 |
| `DeepK/AppModel.swift:304`, `RichSourceImporter.swift:21` | 구조 복사 한도 4,000자(`inputLimit` 기본값) | 유지 |
| `scripts/test.sh:12`, `:22-30`, `:66-71` | swiftc 파일 목록을 손으로 관리 | 새 테스트 블록 추가 |
| `scripts/test.sh:86-92` | `DeepK/` 전체(DeepKApp.swift 제외)를 컴파일하는 블록. 뒤에 WindowPresentation·LoginItemController 블록이 있다 | 새 의존성이 여기서 컴파일되는지 확인 |
| `scripts/test-input.sh:15-17` | `SourceEditor.swift`를 IME 픽스처와 단독 컴파일하고 창을 연다(GUI) | SourceEditor에 새 의존성을 넣지 않는다. GUI 실행은 사용자 수동 항목 |

하네스로 확인한 현재 동작:

- 일반 A 뒤 `⏎⏎---⏎⏎B`: 꼬리 입력이 `---⏎⏎B`라 결과에 `---`가 찍힌다.
- 코드 기호 A(`x = 1 | y`) 뒤 `⏎`, `⏎`, `-`: 세 번째 키에서 문서가 버려지고, 이전 번역이 흐려지고, 원문 전체를 구조 없이 요청한다.
- 일반 A 뒤 `⏎⏎---`: covering이 실패하고 `---`를 꼬리로 요청한다.
- 완료된 [A, B]에서 B를 고치면 원문 전체를 다시 요청한다. 진행 중인 B만 B′로 다시 요청한다.
- 위 블록 삭제: 일반 A면 `---⏎⏎B`·`⏎⏎---⏎⏎B`는 지금도 유지된다(`---`가 B 단위 입력에 들어 있음). `B`만 남기면 B 단위가 `---`를 품고 있어 전체 재번역이다. 코드 A면 단위가 하나라 모두 전체 재번역이다. 구분선을 separator로 옮기면 `retainingSuffix`도 고쳐야 한다.
- 자동 방향에서 영어 A 뒤 한국어 B는 `---`까지 포함해 전체 재번역한다.

## 3. 설계 결정

### 3.1 경계 문법

- 글자 분류는 `TranslationDocument.isBlank`와 같은 집합을 쓴다(D8, P2-9).
  - NL = `Character.isNewline`(CRLF는 한 글자, U+2028 포함).
  - SP = `isBlank`이면서 NL이 아닌 글자(공백·탭·NBSP 등).
- **구분선 줄**: 줄 시작(원문 시작 또는 NL 바로 뒤)에서 `-`(U+002D) 3개 이상, 뒤에 SP만 있는 줄. `- - -`, `***`, `___`, 들여쓴 `␠␠---`, em dash `—`, `---x`, `|---|`는 아니다.
- **사이 구간(GAP)**: 앞 내용의 마지막 글자 뒤부터 다음 내용 줄의 시작까지. 사양의 `^\n+-{3,}[ \t]*\n+`를 SP·CRLF·여러 줄로 넓힌 문법이다.

```text
LINE     = SP* | -{3,} SP*                 빈 줄 또는 구분선 줄
GAP      = SP* (NL LINE)* NL               다음 내용 앞. separator는 마지막 NL까지(기존 규칙)
GAP_END  = SP* (NL LINE)* (NL -{1,2})?     뒤에 내용 없음(입력 중 포함)
```

- **명시 경계**: GAP 안에 구분선 줄이 하나 이상 있고, 앞 내용이 열린 펜스 안에서 끝나지 않는다(`!endsInsideFence`). 뒤 내용은 앞과 독립된 단위이며 `isPlainText`를 검사하지 않는다.
- **구분선 입력 중**: GAP_END에 구분선 줄 또는 끝의 `NL -`·`NL --`가 있다. `- `(대시+공백, 목록 시작)와 `-x`는 아니다. 완료 prefix를 유지하고 요청하지 않는다.
- **구분자(delimiter)**: 공백만이거나(기존), 구분선이 든 GAP_END이고 펜스 밖이다. covering·planner·요청 자르기가 같은 판정을 쓴다.
- **단일 개행 허용**: `A⏎---⏎B`도 경계다(사양 정규식 `\n+`). Markdown setext 제목(`Title⏎---`)의 의미는 버린다.
- **맨 앞 경계**: 원문 맨 앞의 구분선은 그 앞 GAP에 빈 줄도 있을 때만 경계다(`---⏎⏎B`, `⏎⏎---⏎⏎B`). `---⏎title: x`(YAML 머리말)는 내용이다(D1).
- **펜스 검사**(`endsInsideFence`):
  - 줄 `` ^ {0,3}`{3,} ``가 펜스를 연다. 정보 문자열에 백틱이 있으면 펜스가 아니다(```` ```code``` ````, CommonMark, P3).
  - 연 길이 이상의 `` ` ``(뒤에 SP만)만 있는 줄이 닫는다. 정보 문자열이 붙은 줄(```` ```swift ````)은 닫지 않는다.
  - 닫히지 않은 bare ```` ``` ````도 열린 것으로 본다. TranslationMarkup의 stray 처리보다 보수적이다.
  - `~~~`는 `plans/result-structure.md`의 결정대로 펜스로 보지 않는다. 그래서 `~~~` 안의 `---`는 경계다.

### 3.2 하나의 자르기 규칙(D1)

명시 경계는 어디서나 단위를 끊는다. 요청 종류마다 다르게 다루지 않는다.

| 요청 | markup | 처리 |
| --- | --- | --- |
| 첫 요청(빈 문서, fallback 포함) | 없음 | 펜스 밖 첫 명시 경계에서 자른다. 나머지는 기존 큐가 잇는다(첫 요청 이어가기 → `finishSegment` → 다음 꼬리) |
| 증분 꼬리(빈 줄·명시 모두) | 없음(언제나) | 첫 명시 경계에서 자른다 |
| '전체 다시 번역' | 없음 | 블록마다 차례로, 캐시 우회 |
| 제공자·방향 변경 뒤 '다시 번역', 방향 변경 | 없음 | 블록마다 차례로 |
| 구조 복사(원문 == 복사본) | 있음 | 자르지 않는다(§14 유지) |

- 요청 input 끝의 GAP_END(공백, 구분선 줄, 입력 중 `-`·`--`)는 넣지 않는다. 완료 뒤 covering이 trailing으로 흡수한다.
- 맨 앞 경계는 3.1 조건일 때만 떼어 첫 단위 separator로 둔다. 맨 앞 공백만은 지금처럼 `TranslationSegment.init`이 separator로 옮긴다.
- 요청은 하나씩 차례로 보낸다(D2). 블록 수만큼 요청이 늘고 전체 완료 시간은 합이 된다. 받아들인다.
- 결과(모두 의도):
  - 붙여넣은 B 안의 `---`, 한 디바운스 안의 `B⏎⏎---⏎⏎C`, 구조 없는 두 번 복사 안의 `---`도 경계다. 사용자 규칙 '`---`가 나눈다'를 따른다(P1-4).
  - 빈 원문에 ⌘V A 후 디바운스 안에 ⌘↩·⌘V B를 해도 첫 요청은 A다(P1-3).
  - '전체 다시 번역'이 `---`를 되풀이하지 않고 선·블록 구조를 유지한다(P2-7). 문맥은 블록 안에서만 쓴다.
  - 값싼 M0: B를 둔 채 위 블록 A만 고치면 전체 경로로 가지만 A′만 요청한다. A′ 완료 뒤 B는 `paragraph-v1` 캐시(네트워크 없음)로 붙거나 다시 요청된다. 그동안 이전 번역은 흐리게 유지한다(3.8).

### 3.3 판정 함수 위치

- 모든 판정은 `IncrementalTranslationPlanner`의 순수 static 함수로 둔다. planner·`TranslationDocument`·`TranslationStore`·`AppModel`이 같은 함수를 쓰므로 서로 어긋나지 않는다. Foundation만 쓰고 모든 컴파일 목록(`test.sh:12`, `:22-30`, `:86-92`, `test-incremental-live.sh`)에 이미 들어 있다.

| 함수 | 쓰는 곳 |
| --- | --- |
| `isDelimiter(_ rest:, after content:)` | covering, planner 빈 꼬리, 요청 끝 떼기 |
| `unitEnd(of:) -> Int`(UTF-8) | 끝 GAP_END를 모두 뗀 내용 끝. planner의 `c`, 요청 input 자르기 |
| `isExplicitGap(_:)` | 문서의 명시 여부 유도(3.4), 미리보기 선 |
| `firstUnit(in:) -> Tail` | 첫 요청 자르기(separator = 뗀 맨 앞 경계) |
| `leadingDelimiter(of:)` | `retainingSuffix` |
| `endsInsideFence(_:)` | 경계·⌘↩ |
| `plainScopeStart(of prefix:) -> Int`(UTF-8) | 빈 줄 경로의 `isPlainText` 범위(D8) |
| `boundaryLineRanges(in:excludingUTF8:) -> [NSRange]`(UTF-16) | 원문 창 회색 |
| `isBlankSource(_:)` | 빈 원문 판정(공백·구분선·입력 중 대시뿐) |
| `boundaryInsertion(after:) -> String?` | ⌘↩ 덧붙일 글. 펜스 안·내용 없음이면 nil |

- `SourceEditor`는 이 함수를 부르지 않는다. 회색 범위는 `[NSRange]`로, ⌘↩ 글은 클로저로 받는다. `test-input.sh`의 단독 컴파일이 그대로 유지된다.
- `TranslationMarkup`에 넣지 않는다. 결과 표시용 펜스 규칙(stray, `~~~`)과 경계 규칙은 목적이 다르다.

### 3.4 separator 저장

- `TranslationSegment`에 필드를 더하지 않는다. 명시 여부는 `앞 단위.trailing + 이 단위.separator`에 구분선 줄이 있는지(`isExplicitGap`)로 매번 유도한다.
- 이유: 경계 바이트가 `reuseEquivalentActiveRequest`·covering을 거치며 앞 단위 trailing과 뒤 단위 separator로 나뉠 수 있다(`⏎⏎-` + `--⏎⏎`도 가능). 생성 지점(`complete`, `restoreCachedTail`, covering, `retainingSuffix`, 캐시 복원)을 고치지 않아도 되고, 캐시 항목도 옮길 필요가 없다.
- 문서에 들어오는 구분선은 모두 경계로 받아들인 것이다. covering과 planner가 펜스 안의 구분선을 trailing·separator로 보내지 않기 때문이다.
- `Tail`에 `var explicit = false`를 기본값으로 더한다. 언어 규칙(D5)과 테스트가 쓰며 저장하지 않는다. 기존 `Tail(separator:input:)` 호출은 그대로 컴파일된다.

### 3.5 꼬리 계획(`tail(after:in:)`)

1. prefix가 비었거나 새 원문의 바이트 prefix가 아니면 nil(기존).
2. `c = unitEnd(prefix)`: prefix 끝의 GAP_END 전체(공백, 펜스 밖 구분선 줄, 입력 중 `-`·`--`)를 뗀 내용 끝이다(P0-1). 펜스 안이면 공백만 뗀다.
3. `source[c...]`가 구분자(3.1)이면 `Tail(separator: suffix 전체, input: "", explicit: 구분선 포함 여부)`다.
4. 아니면 `source[c...]`를 GAP + 내용으로 나눈다. **내용이 prefix 끝보다 앞에서 시작하면 nil**이다(대시 줄을 고치는 중이거나 trailing의 대시가 내용이 됨). `replanned`의 'trailing 비우기'가 처리한다.
5. GAP에 구분선이 있고 `!endsInsideFence(source[..<c])`이면 명시 꼬리다. 개행 수와 `isPlainText`는 보지 않는다.
6. 아니면 기존 빈 줄 규칙이다. `isPlainText`는 `o = plainScopeStart(prefix)` 하나로 `prefix[o...]`와 `source[o..<꼬리 끝]`에 적용한다(D8, P2-12). 다른 스냅샷에 `String.Index`를 넘기지 않는다.
7. 5·6 모두 꼬리를 펜스 밖 첫 명시 경계에서 자르고(D1) 끝 GAP_END를 뗀다. separator는 GAP 중 suffix 몫(`source[prefix 끝..<내용 시작]`)이다.

구분선은 Markdown에서 블록을 끊고, 그 너머로 이어질 수 있는 것은 펜스뿐이며 펜스 검사로 막는다. 그래서 6의 범위를 줄여도 안전하다.

불변식(테스트로 고정):

- I1: planner가 빈 입력 꼬리를 주면 같은 문서의 `covering`도 성공한다. 깨지면 `startRequest:1060`의 `assertionFailure`가 Debug에서 트랩하고 Release에서는 `.waiting`에 멈춘다.
- I2: 꼬리가 있으면 `prefix + separator + input`은 원문의 바이트 prefix이고, 남은 부분은 비었거나 GAP_END이거나 명시 GAP으로 시작한다. 원문 바이트가 빠지거나 겹치지 않는다.
- I3: 경계 구분선과 입력 중 대시는 markup이 없는 모든 요청의 `request.input`, 모든 `segment.input`·`segment.text`, 문서 `text`에 들어가지 않는다. 예외는 구조 복사 요청, 펜스 안, 빈 줄 없는 맨 앞 머리말이다.
- I4: 스트리밍 미리보기는 최종 `text`의 prefix다(같은 결합 규칙).
- I5: 첫 요청은 `token.separator + request.input == token.snapshot`, 꼬리는 `document.input + token.separator + request.input == token.snapshot`이다. 뗀 끝 바이트는 snapshot에 없다.
- I6: 요청을 만들 때 `request.markup == markup(for: request.input)`(꼬리는 nil)이다. 그래서 완료 문서의 `basis.markup == markup(for: basis.input)`가 성립한다.

### 3.6 첫 요청과 요청 단위(`startRequest`)

- 계획: `tail`이 있으면 꼬리, 없으면 `activeMarkup == nil ? firstUnit(in: sourceText) : Tail(separator: "", input: sourceText)`이다.
- `request.input = plan.input`. `request.markup = incremental ? nil : markup(for: plan.input)`.
  - 자르지 않은 요청은 input이 원문이므로 지금과 같다(`activeMarkup`).
  - 잘린 첫 단위가 복사본과 정확히 같으면 구조를 싣는다. I6을 지키는 필수 조건이다. 싣지 않으면 `documentMatchesSelection`이 거짓이 되어 같은 A를 끝없이 다시 요청한다.
  - 덤: 구조 복사 A 뒤에 경계와 B를 둔 원문을 다시 번역해도 A의 링크·칩이 남는다(§14 한계의 일부 해소).
- `token.separator`: 첫 요청은 `plan.separator`(뗀 맨 앞 경계), 꼬리는 `tail.separator`.
- `token.snapshot`: I5대로 잡는다. 진행 중 B 뒤의 `⏎⏎---`를 지우거나 이어 쳐도 B를 취소하지 않는다(P3).
- `complete`: `basis.input = current.input`. 지금도 첫 요청에서는 snapshot과 같은 값이다. segment는 `TranslationSegment(id:separator:source:text:)` 그대로다.
- `reuseEquivalentActiveRequest`: 비교 key를 `firstUnit(sourceText)` 기준으로 만들고, input·snapshot도 그 단위로 다시 묶는다. 구조 요청은 지금처럼 원문 전체다(P1-3).
- `restoreCachedResult`는 원문 전체 key만 본다(변경 없음). 잘린 첫 단위 key 조회는 후속(7절).

### 3.7 TranslationDocument

- `covering`(`:43`): `rest.allSatisfy(isBlank)` 대신 `Planner.isDelimiter(rest, after: prefix)`를 쓴다. `A⏎⏎-`, `A⏎⏎--`, `A⏎⏎---`, `A⏎⏎---⏎⏎`(⌘↩)가 모두 네트워크 없이 T(A)다. `trailing` 주석을 '공백 또는 남은 구분선'으로 고친다.
- `retainingSuffix`(`:58`): 앞 개행 대신 `Planner.leadingDelimiter(of: source)`를 쓴다. 빈 줄·구분선 줄(각각 NL로 끝남)이며, 구분선은 빈 줄이 함께 있을 때만이다. `---⏎⏎B`, `⏎⏎---⏎⏎B`가 T(B)를 유지한다.
- `join`(`:122`): 명시 경계면 `desired = 2`로, 앞 단위 끝 개행을 무시한다. `text(appending:separator:)`도 `(segments.last?.trailing ?? "") + separator`로 같은 판정을 한다(I4).
- `unitBreaks: [Int]`: 인덱스 1 이상에서 명시 경계인 단위를 붙이기 직전의 `result.utf16.count`다. `text`와 한 번에 계산한다(`rendered: (text, unitBreaks)`). 첫 단위 위에는 선이 없다.
- `replanned(for source:, accepting: (Tail) -> Bool) -> (TranslationDocument, Tail)?`(신규):
  - k = 단위 수에서 1까지 내려가며 앞 k개 단위를 남긴다. k < 단위 수이면 단위 k(남기지 않는 첫 단위)의 경계가 명시일 때만 자른다.
  - 각 k에서 마지막 단위의 trailing을 그대로 둔 경우와 비운 경우를 차례로 시도한다. `Planner.tail(after: head.input, in: source)`가 빈 꼬리가 아닌 첫 꼬리를 주면 그 꼬리가 결정한다. `accepting`을 통과하면 돌려주고, 거절되면 nil이다(리뷰 2차). store가 넘기는 `accepting`은 `isComposing || 언어 일치`다.
  - 거절에서 멈추는 이유: 자동 방향에서 덧붙인 글이 언어 판정에 걸렸을 때(`ok`·`LGTM`은 인식기가 영어로 보지 않는다, 한국어 문단, `---` 뒤 한국어 블록) k를 더 줄이면 고치지 않은 B를 버리고 `B⏎⏎덧붙인 글`을 한 단위로 다시 요청할 뿐이다. 요청 경로(`startRequest`)는 언어를 다시 보지 않으므로 거절한 글도 결국 같은 방향으로 번역된다. 멈추면 store는 전체 경로(흐린 fallback, 사례 h)로 가고 T(A)·T(B)는 함께 흐리게 남는다.
  - 완료된 B를 고칠 때 A를 남기고 B′만 요청한다. T(B)는 바로 사라지고 B′는 보통 꼬리로 보인다(D4).
  - B가 일반 텍스트가 아닐 때 `⏎⏎C`는 A를 남기고 `B⏎⏎C`를 한 단위로 요청한다. 요구 밖이지만 안전하다. T(B)는 바로 사라진다(D4와 같다).
  - 남은 trailing(`A⏎⏎-` 뒤 `⏎`, `A⏎⏎--` 뒤 `x`)에서 다시 계획한다. 일반 A 뒤 `--flag` 문단이 지금처럼 꼬리로 남는다.
  - 빈 줄 경계에서는 자르지 않는다. 빈 줄 단위의 완료 B 편집은 지금처럼 전체다. 단, 더 위에 명시 경계가 있으면 그 경계에서 자른다.
  - 가운데 블록 삭제(A---B---C → A---C)는 k=1에서 `[A]` + 명시 꼬리 C가 되고, C는 `restoreCachedTail`(`paragraph-v1`)로 붙는다.

### 3.8 TranslationStore

`reconcileInput`(P0-2). `retainingSuffix`(기존, token rebase 포함) 다음 순서를 바꾼다.

```text
current.input != sourceText이면
  1. covering 성공                                → document = covered
  2. tail(after: current.input) && accept         → 문서 유지
  3. token 유효 && (공백 확장 || tail(after: token.snapshot) && accept)
                                                  → 문서 그대로, .translating, return true
  4. replanned(for: sourceText, accepting:)       → document = head, cancelActiveWork(), return false
  5. invalidateResultAndWork(), return false
이어서 token 검사(기존 :868-880)
```

- accept = `tail.input.isEmpty || isComposing || tailMatchesLanguage(tail, basis:)`. token 유효 = 같은 세대, 증분, 4,000자 이내. 3은 조합 중이면 빈 꼬리를 받지 않는다(기존 조건).
- 2가 c2·c3를 받는다(리뷰 2차 정정): 초안은 "3이 없으면 빈 줄 꼬리 B 진행 중 ⌘↩ + 코드 C가 전체 재번역"이라 했지만, D1 자르기와 D8 범위 때문에 문서 기준 꼬리가 B에서 끊겨 이미 성공한다. c2·c3 테스트는 '문서 기준 판정이 진행 중 꼬리를 유지한다'를 확인한다.
- 3이 실제로 쓰이는 곳: 문서 기준 꼬리가 언어로 거절됐지만 진행 중 요청이 그 블록을 이미 보내고 있을 때다. 전체 경로(fallback)의 `startRequest`는 언어를 보지 않고 다음 블록을 보낸다. 자동 방향에서 영어 [A---B] 뒤 `---` + 한국어 블록 K가 fallback으로 요청 중일 때 K 뒤에 공백을 치면 2는 K를 거절하고 3이 K를 유지한다. 3이 없으면 키마다 A부터 fallback이 다시 시작된다(`explicitBoundaryLanguage`).
- 4 뒤 token 무조건 취소: 단위를 버리거나 trailing을 바꾸면 진행 중 token의 separator가 다른 문서를 기준으로 한다. 살려 두면 `[A] + C`처럼 원문과 맞지 않는 문서가 만들어지고 없는 원문 key로 캐시된다(사례 B). 4의 거절 멈춤(3.7) 뒤에는 초안의 사례 B 경로(언어 거절 → k=1)로는 닿지 않는다. 닿는 경로: 고정 방향 [A---B] 완료, 빈 줄 꼬리 C 진행 중 `⏎⏎`+코드를 덧붙이면 B·C·코드가 한 블록으로 다시 계획되어 C가 버려진다. 디바운스 안에 덧붙임을 지우면 원문이 다시 C의 snapshot과 같아지므로, 취소하지 않았다면 C가 `[A]` 위에 붙는다(`explicitBoundaryRaces`가 취소와 정렬을 고정).

언어(D5, P1-5):

- `tailMatchesLanguage(_ tail: Tail, language:)`. 고정 방향이면 참이다.
- 명시 꼬리: 펜스 코드 블록을 뺀 꼬리 전체를 한 번 판정한다. `languageHypotheses`에서 반대 지원 언어(ko↔en)가 1위이고 확률 0.8 이상일 때만 거절한다. nil·기타 언어·글자 없음은 받는다. 임계값은 구현 때 표본(아래 테스트)으로 확인해 이 문서에 적는다.
- 빈 줄 꼬리: 지금 규칙(문단마다 같은 언어) 그대로다.
- 쓰는 곳: `reconcileInput` 2·3·4, `continuesFirstRequest`(`:899`).
- 거절되면 전체 경로로 간다. 전체 경로도 D1로 잘리므로 A부터 다시 요청하고, 언어 쌍은 지금처럼 원문 전체로 정한다(`resolveLanguages` 변경 없음). 단위별 언어 쌍은 후속이다.

흐린 이전 번역과 '전체 다시 번역':

- `complete`(`:1170`): 흐린 이전 번역을 놓는 조건을 '새 문서가 원문 끝까지 덮을 때(`covering` 성공)'로 바꾼다. 다음 블록이 남아 있으면 마지막 블록을 게시할 때(`publishDocument`, 이미 놓음) 놓는다. '새 번역 완료 시 한 번 교체' 계약(incremental-translation.md §8)을 블록 단위 요청에서도 지킨다. 값싼 M0에서 B를 캐시로 붙이기 전 한 틱 동안 T(B)가 비는 깜빡임도 없다. 대체 요청 중에 덧붙인 문단도 같은 교체에 들어가 그 꼬리가 끝날 때 한 번에 바뀐다.
- `finishSegment`(`:1192-1193`): `bypassCache`·`retryNeedsWholeDocument`는 원문 전체를 게시할 때만 끈다. 그래야 '전체 다시 번역'의 두 번째 블록부터도 캐시를 우회한다. 사용자가 편집하면 `reconcileInput`이 지금처럼 끈다.
- '전체 다시 번역' 중 블록이 실패하면 '다시 시도'는 처음 블록부터 다시 한다(`retryNeedsWholeDocument`). 남은 블록부터 잇는 재시도는 후속이다.
- `hasPartialResult`: 흐린 이전 번역이 있는 동안은 거짓이다. 상태 문구가 '추가 내용 번역 중…' 대신 '번역 중…'이다.

빈 원문:

- `isBlankSource`를 `validateSourceForScheduling`·`validateSourceForExplicitInvocation`·`startRequest`의 빈 검사, `invalidateResultAndWork`의 `blank`, `markProviderChangePrepared`에 쓴다. `---`, `-`, `--`만 남은 원문은 요청하지 않는다(P3).

표시:

| 경우 | `TranslationDisplay.unitBreaks`(기본 `[]`) |
| --- | --- |
| 흐린 이전 번역 | `supersededBreaks` |
| 꼬리 미리보기 있음 | `document.unitBreaks` + 명시 꼬리면 `joined.tailStart` |
| 꼬리 미리보기 없음 | `document.unitBreaks`(꼬리 글이 생기기 전에는 T(A) 아래 선 없음) |
| 첫 요청 미리보기 | `[]` |
| 완료·부분 완료 | `document.unitBreaks` |

- `supersededBreaks`: `invalidateResultAndWork`에서 `superseded`와 함께 저장한다. `releaseSuperseded`와 `!keep` 분기에서 지운다.
- `sourceBoundaryLines: [NSRange]`(신규): 3.10.

바꾸는 곳과 바꾸지 않는 곳:

| 바꾼다 | 바꾸지 않는다(planner를 따른다) |
| --- | --- |
| `reconcileInput`, `continuesFirstRequest`(언어), `tailMatchesLanguage`, `startRequest`, `complete`, `finishSegment`, `reuseEquivalentActiveRequest`, `display`, `invalidateResultAndWork`, `hasPartialResult`, 빈 원문 검사 5곳 | `accepts`, `restoreCachedTail`, `restoreCachedResult`, `restoreCompletedDocument`, `documentMatchesSelection`, `cacheKey`, `retainingSuffix` rebase(`:843-850`) |

### 3.9 결과 창의 선

- 그리기 방식: 글자 밖 offset과 그리기만 쓴다. 문자·첨부(U+FFFC)·속성은 쓰지 않는다.
  - `TranslationResultContent.unitBreaks: [Int] = []`는 raw UTF-16 offset이고 tailStart와 같은 규약이다.
  - `update`에서 `TranslationMarkup.displayOffset`으로 화면 offset으로 바꾼다. tailStart와 같으면 이미 바꾼 값을 쓴다. tailStart 이전 break 값은 (그 앞 raw 문자열, inline)을 key로 캐시한다. 스트리밍 틱마다 prefix를 N번 다시 파싱하지 않는다(P2-11).
  - 바꾼 값을 `ResultTextView.unitBreaks`에 넣는다(`didSet`에서 `needsDisplay`).
- 위치: 위 단위의 마지막 보이는 글자 줄 `lineFragmentUsedRect.maxY`(코드 박스면 `+ CodeBlockStyle.bottom`)와 아래 단위의 첫 글자 줄 `minY`(코드면 `- CodeBlockStyle.top`)의 중간이다. 픽셀에 맞추고, 텍스트 컨테이너 폭 전체에 긋는다. 아래에 보이는 글이 없으면 그리지 않는다.
- 모양: 1pt, `NSColor.separatorColor`. 창 구분선(`TranslationView.swift:31`)과 같다. 시안의 '1px'는 디자인 도구의 pt다. `draw(_:)`에서 박스·칩과 함께 `super.draw` 전에 칠하므로 선택 강조 아래에 깔린다.
- 저장소 문자열·`displayText`·`latestResult.text`·캐시·삽입문에 아무것도 더하지 않는다. 그래서 ⌘C·드래그·Services·복사 버튼·삽입·손쉬운 사용·찾기는 바뀌지 않고, `ResultClipboard.swift`도 고치지 않는다. 하네스에서 전체 선택 복사가 `"윗 단위…\n\n아랫 단위…"`였다.
- 뷰는 `[Int]`만 받는다. `TranslationDocument`·planner를 참조하지 않는다(`test.sh:66-71` 컴파일 목록 유지).
- 다듬기(선택): '↓ 새 번역 보기'로 이동할 때 선이 보이게 간격의 절반만큼 덜 올린다. 코드 박스 바로 뒤의 선 간격(박스 아래 약 5pt)은 디자인을 확인한다.

### 3.10 원문 창 회색(D6)

> 2026-10-13 사용자 피드백으로 바뀌었다. 회색 대신 대시를 숨기고 텍스트 컨테이너 폭 전체에 선 하나를 긋는다. 판정(store)은 그대로다. 10절 '원문 창 가로줄·스크롤바 여백'을 본다. 아래는 착수 전 계획이다.

- 판정(store): 회색 = '번역에 보내지 않는 경계 구분선'이다. D1로 markup 없는 요청은 모두 잘리므로 원문만 보고 정할 수 있다. 진행 중 token(`@ObservationIgnored`)에 기대지 않는다(P2-11).
  - `activeMarkup != nil`(원문 전체를 구조와 함께 보냄)이면 `[]`.
  - 아니면 `Planner.boundaryLineRanges(in: sourceText, excludingUTF8: 보낸 범위)`. 보낸 범위는 구조를 실은 첫 단위의 글이다(`document?.basis.markup != nil`이면 첫 단위의 `[separator 끝, input 끝)`, 구조 첫 요청이 진행 중이면 `[token.separator 끝, snapshot 끝)`). 구조 복사 원문 안의 `---`는 모델로 갔으므로 회색이 아니다. separator의 구분선은 보내지 않았으므로 회색이다(리뷰 2차: 구조 복사 A를 지운 뒤 맨 앞에 남은 `---`, 사례 d).
  - 구조 단위가 지워져 다른 단위가 첫 단위가 되어도 그 단위의 글을 빼는 것은 무해하다. 구조 없는 단위는 첫 경계에서 잘려 글 안에 경계 줄이 없다. segment id로 구조 단위를 가리지 않는 이유: 캐시 복원(`restoreCachedResult`)은 basis에 새 id를 주고 segment는 저장된 id를 쓴다.
  - 포함: 내용 사이 GAP의 구분선 줄, 끝 GAP_END의 완성된 구분선 줄, 3.1 조건의 맨 앞 구분선, 내용이 없는 원문의 구분선. 제외: 펜스 안, 입력 중 `-`·`--`, 빈 줄 없는 맨 앞 머리말.
  - (sourceText, n)으로 메모한다. 스트리밍 갱신마다 다시 돌지 않는다.
- 적용: `SourceEditor`에 `boundaryLines: [NSRange] = []`를 더한다(기본값이라 IME 픽스처 호출도 컴파일된다). `updateNSView`에서 `replaceTextIfNeeded` 다음, `editor.string == text`일 때만 적용한다. `makeNSView`에서도 한다.
- TextKit 2를 유지한다. TextKit 1로 바꾸지 않는다.
  - `textLayoutManager.removeRenderingAttribute(.foregroundColor, for: 문서 전체)` 뒤 각 범위에 `addRenderingAttribute(.foregroundColor, value: .tertiaryLabelColor, for:)`. `.foregroundColor`만 다룬다(marked text·맞춤법 표시를 건드리지 않는다).
  - `NSRange` → `NSTextRange`는 `textContentManager`의 location offset으로 바꾼다.
  - 편집·재배치 뒤 사라지면 `renderingAttributesValidator`로 조각마다 다시 단다.
  - `editor.layoutManager`를 어디서도 읽지 않는다. 첫 접근에서 TextKit 1로 몰래 바뀐다. 테스트로 `textLayoutManager != nil`을 고정한다.
- 선택(같은 단계, 떼어낼 수 있음): 대시 오른쪽 8pt부터 컨테이너 오른쪽 끝까지 줄 가운데에 1px `separatorColor` 선. 위치는 text layout fragment의 `layoutFragmentFrame`·`textLineFragments`로 구한다. 조각이 별도 레이어로 그려져 선이 가려지거나 스크롤 때 남으면 선은 빼고 회색만 한다.
- TextKit 2로 회색이 안정적이지 않을 때만 TextKit 1 전환을 검토한다. 그때는 별도 단계로 나누고 보고서에 명시한다(P2-10).

### 3.11 ⌘↩ '끝에 구분선 넣기'(D7)

- 앱 어디에도 ⌘↩가 없다(2절). 메뉴 단축키는 숨은 메뉴 막대(`.accessory`)에서도 동작한다. 하네스에서 main menu 항목 `keyEquivalent "\r"` + `.command`가 실행됐다. NSTextView의 `keyDown`·`performKeyEquivalent`는 ⌘↩를 쓰지 않는다.
- 구성(기존 `ResultScrollProxy` 패턴):
  - `SourceEditor.swift`의 `@MainActor final class SourceEditorProxy: NSObject, NSMenuItemValidation`이 `weak var editor`와 `insertion: (String) -> String?`을 가진다.
  - `validateMenuItem`은 `editor?.window?.isKeyWindow == true && insertion(editor.string) != nil`이다. 설정 창이 key이면, 원문에 내용이 없으면, 열린 펜스 안이면 꺼진다(P1-6).
  - `AppModel.sourceEditor`가 proxy를 갖고 `insertion = IncrementalTranslationPlanner.boundaryInsertion(after:)`로 묶는다. `SourceEditor(proxy:)`가 editor를 연결한다.
  - `DeepKApp.swift` 편집 메뉴 끝에 구분선 항목과 '끝에 구분선 넣기'(`target = AppModel.shared.sourceEditor`)를 더한다.
  - AppModel을 `NSMenuItemValidation`으로 만들지 않는다. 그러면 다른 AppModel 메뉴 항목까지 검증하게 된다.
- 동작(`appendBoundary`):
  1. `makeFirstResponder(editor)`.
  2. 조합 중이면 `unmarkText()`와 `inputContext?.discardMarkedText()`로 확정한다. 재정의한 `unmarkText`가 `onEdit`을 한 번 보낸다.
  3. 확정한 글로 `insertion`을 다시 구한다. nil이면 beep하고 끝낸다.
  4. 빈 글이 아니면 끝에 `insertText(_:replacementRange:)`. `textDidChange`·`onEdit`이 한 번 일어난다. `allowsUndo`가 꺼져 있어 ⌘Z로 되돌릴 수 없다(7절).
  5. 커서를 끝에 두고 `scrollRangeToVisible`.
- 덧붙이기만 한다. 근거(P1-6 정정): 완료 문서만 있을 때는 covering이 trailing을 비교하지 않으므로 끝 공백을 지워도 통한다. 그러나 꼬리가 진행 중이면 token.snapshot의 prefix가 깨져 그 요청이 취소된다(약 5초 손실). 덧붙이면 어느 상태에서도 prefix가 유지된다.
- 넣는 글: 마지막 내용 줄이 구분선이면 끝 NL을 2개까지 채운다. 끝이 `NL -`·`NL --`이면 대시를 3개로 채운 뒤 NL 2개. 아니면 끝 공백이 NL로 끝나지 않을 때 `⏎`를 넣고, 끝 NL이 2개가 되도록 채운 뒤 `---⏎⏎`를 넣는다.

  | 원문 끝 | 덧붙임 | 결과 |
  | --- | --- | --- |
  | `A` | `⏎⏎---⏎⏎` | `A⏎⏎---⏎⏎` |
  | `A⏎` | `⏎---⏎⏎` | `A⏎⏎---⏎⏎` |
  | `A⏎⏎` | `---⏎⏎` | `A⏎⏎---⏎⏎` |
  | `A␠␠` | `⏎⏎---⏎⏎` | `A␠␠⏎⏎---⏎⏎` |
  | `A⏎⏎␠␠` | `⏎---⏎⏎` | `A⏎⏎␠␠⏎---⏎⏎` |
  | `A⏎⏎-` | `--⏎⏎` | `A⏎⏎---⏎⏎` |
  | `A⏎⏎--` | `-⏎⏎` | `A⏎⏎---⏎⏎` |
  | `A⏎-` | `--⏎⏎` | `A⏎---⏎⏎` |
  | `A⏎⏎---` | `⏎⏎` | `A⏎⏎---⏎⏎` |
  | `A⏎⏎---␠` | `⏎⏎` | `A⏎⏎---␠⏎⏎` |
  | `A⏎⏎---⏎` | `⏎` | `A⏎⏎---⏎⏎` |
  | `A⏎⏎---⏎⏎` | 없음(커서만 끝으로) | 변경 없음 |
  | 열린 펜스 안, 내용 없음(빈 원문·`---`·`-`만) | nil(메뉴 꺼짐) | — |

- store 쪽은 타이핑과 같다. covering이 바로 T(A)를 내고 요청하지 않는다.
- 발견성: 메뉴 막대가 보이지 않으므로 README 단축키 문단에 적는다. 화면 안내 UI는 후속이다.
- key 창 조건(리뷰 2차): ⌘C 두 번은 원래 앱의 포커스를 빼앗지 않으려고 번역 창을 앞에만 놓는다(`AppModel.showWindow(activate: false)` → `orderFrontRegardless`). 이때 deepK는 활성 앱이 아니어서 메뉴 단축키가 오지 않고, ⌘↩는 원래 앱이 받는다(메일 보내기·댓글 제출일 수 있다). 코드는 그대로 두고(key 창 검사가 맞다) README에 '번역 창을 클릭해 활성(key) 상태일 때'와 '⌘C 두 번 뒤에는 먼저 창을 클릭한다'를 적는다.

### 3.12 4,000자 한도: 원문 전체 기준을 유지한다(D3)

| 안 | 바뀌는 곳 | 판단 |
| --- | --- | --- |
| 원문 전체 4,000자 유지 | 없음 | 채택. A---B---C가 4,000자를 넘으면 지금처럼 유효한 앞 결과를 보이고 길이 오류를 낸다. 위 블록을 지우면 네트워크 없이 T(B)로 줄어들어 이어 쓸 수 있다 |
| 단위당 4,000 + 전체 약 20,000 | 검증 7곳(`:665`, `:684`, `:868`, `:889`, `:920`, `:1041`, `:1251`), `startRequest`의 단위 길이 검사, 새 오류 문구 2종, 테스트 2개(`IncrementalTranslationTests.swift:762-766`, `TranslationStoreTests.swift:624`), `requestTimeout` 30초(`:198`)가 큰 요청에 부족, `RichSourceImporter`의 `inputLimit`, 키마다 covering이 단위 수 × 원문 길이 문자열을 만듦, 20,000자 결과의 결과 뷰 재배치와 `displayOffset` 재파싱, 캐시 2,000,000바이트에 큰 문서 약 8개 | 보류. 후속 |

### 3.13 캐시 정책 버전: 올리지 않는다(D3)

- 키의 뜻이 바뀌지 않는다.
  - `paragraph-v1`: '이 입력만 따로 번역한 결과'다. 명시 꼬리와 빈 줄 꼬리의 요청 payload가 같으므로 공유가 맞다. 비일반 B는 `normalizedCacheInput`이 원문 그대로 비교한다.
  - `document-v1`·`document-inline-v1`: '이 원문을 정확히 덮는 문서'다. 항목은 단위 separator 바이트를 담는다. 복원은 covering을 거치고 명시 여부·선이 함께 돌아온다.
  - 잘린 첫 단위가 복사본과 같아 구조를 실으면(3.6) 그 key는 구조 복사로 그 단위만 번역한 key와 같은 뜻이다.
- 바뀌는 것은 값이다. 같은 원문에 대해 `---`가 섞인 전체 번역 대신 블록으로 조립한 문서가 저장된다. 캐시는 프로세스 메모리(300초)뿐이고 한 프로세스 안에서 규칙은 하나이므로 두 종류가 섞이지 않는다. 앱 업데이트 뒤에는 새 프로세스다.
- 끝 공백을 요청에서 떼므로 구조 원문(코드)의 문서 key가 끝 공백 없는 원문으로 저장될 수 있다. 공백만 다른 원문의 적중률이 조금 달라질 뿐 뜻은 같다.
- 초안의 '같은 원문 키에 전체 번역과 조립 문서가 번갈아 저장' 문제는 D1로 없어진다('전체 다시 번역'도 블록 단위).

### 3.14 버린 대안

| 대안 | 이유 |
| --- | --- |
| 세그먼트에 `isExplicit` 필드 저장 | 생성 지점 5곳을 모두 고쳐야 하고, 경계 바이트가 trailing에 있을 때 놓친다 |
| 구분선 판정을 TranslationMarkup에 두고 원문 창이 텍스트만 보고 회색 처리 | 구조 복사 원문 안의 `---`까지 회색이 되어 사용자를 속인다 |
| `TranslationMarkup.openFence` 재사용 | private이고, 닫히지 않은 bare ```` ``` ````를 stray로 보아 펜스 안의 `---`를 받아들인다 |
| 결과에 U+FFFC 첨부·자리표시 문자·`NSTextBlock` 테두리 | 복사·Services·VoiceOver로 새어 나가고, 저장소 == `displayText` 불변식(선택·copyableLength·displayOffset)을 깬다 |
| 결과 속성(`.deepKUnitBreak`)으로 선 표시 | `restyle`이 산문 편집에서 지운다. 별도 추적이 필요하다 |
| Markdown 수평선을 결과에서 숨긴 선으로 렌더 | 기존 결과의 hr·setext 표시와 복사가 바뀌고, 스트리밍 중 `-`·`--`가 보였다 사라져 '뒤에만 붙는다' 불변식을 깬다 |
| 요청 종류마다 다른 경계 규칙(초안: B 안의 `---`·첫 요청·전체 다시 번역은 나누지 않음) | 같은 원문이 입력 속도에 따라 다른 단위·선·결과가 되고 `---`가 찍힌다(P1-3, P1-4, P2-7) |
| '전체 다시 번역'을 명시 경계가 있으면 숨김 | 블록마다 다시 번역하면 `---` 없이 같은 동작을 줄 수 있다 |
| M0 완전판(이전 문서 뒤 단위를 별도 재사용 풀로) | D1의 값싼 경로로 충분하다. 캐시가 없을 때만 B를 다시 요청한다(후속) |
| 원문 창을 TextKit 1로 전환 | 표시 기능 하나 때문에 IME·렌더링 위험을 진다. TextKit 2 rendering attribute로 먼저 한다(D6) |
| ⌘↩가 끝 공백을 지우고 정확히 `⏎⏎---⏎⏎`로 맞춤 | 진행 중 꼬리의 snapshot prefix가 깨져 그 요청이 취소된다 |

## 4. 시나리오

'원문 창' 열의 '회색'은 2026-10-13부터 '대시를 숨긴 가로줄'이다(10절).

| 사례 | 원문 변화 | 지금 | U1 요청 | 결과 창 | 원문 창 |
| --- | --- | --- | --- | --- | --- |
| a | 코드 기호·링크가 있는 A 완료 → 한 키씩 `⏎⏎---⏎⏎` → B 붙여넣기 | `A⏎⏎-`에서 흐림, 전체 재번역, 링크 소실, `---` 찍힘 | 구분선 동안 0회. B만 1회(구조 없음) | T(A)(링크·칩 유지) + 선 + T(B) | `---` 회색 |
| b | A 번역 중 a와 같은 입력 | 일반 A는 유지 후 `---⏎⏎B` 요청. 코드 A는 A 취소 후 전체 | A 유지, 완료 뒤 B만 | B 미리보기가 생기면 선 | 회색 |
| b2 | A 번역 중 `⌘↩ ⌘V B ⌘↩ ⌘V C` | B---C가 한 꼬리 | A, B, C 차례로 3회 | T(A) + 선 + T(B) + 선 + T(C) | 회색 2줄 |
| c | A---B 완료 후 `⏎⏎C` | A가 일반이 아니면 전체 | B·C 일반이면 C만. B가 비일반이면 A 유지, `B⏎⏎C` 한 단위(T(B)는 바로 사라짐). 자동 방향에서 C가 언어로 거절되면(`ok`·`LGTM`·다른 언어) h와 같다 | T(A)+선+T(B)+T(C) / T(A)+선+T(B+C) | 회색 |
| c2 | 일반 [A] 완료, 빈 줄 꼬리 B 진행 중 → ⌘↩ + 코드 C | 전체 재번역, B 취소 | B 유지, 완료 뒤 C만 | T(A)+T(B)+선+T(C) | 회색 |
| c3 | [A---B] 완료, 빈 줄 꼬리 C 진행 중 → ⌘↩ + 코드 D | — | C 유지, 완료 뒤 D만. 문서는 언제나 원문 prefix | T(A)+선+T(B)+T(C)+선+T(D) | 회색 |
| d | 위 블록 삭제: `B`, `---⏎⏎B`, `⏎⏎---⏎⏎B` | 일반 A: 뒤 둘은 유지, `B`만 전체. 코드 A: 모두 전체 | 0회 | T(B), 선 없음 | 남은 `---` 회색 |
| d2 | 가운데 블록 삭제: A---B---C → A---C | 전체 | 0회(C는 `paragraph-v1`). 캐시 용량 0·만료면 C만 | T(A)+선+T(C) | 회색 |
| e | 아래 블록 삭제: `A`, `A⏎⏎---`, `A⏎⏎---⏎⏎`, `A⏎⏎--`, `A⏎⏎-` | `A`만 0회. 일반 A의 `A⏎⏎---`는 `---` 요청 | 0회. 연결이 끊겨도 같다 | T(A), 선 없음 | `---` 회색 |
| f | B 편집(진행 중 / 완료) | 진행 중은 B′만, 완료는 전체 | 둘 다 B′만. 되돌리면 꼬리 캐시 | T(A) 유지. 완료 B는 T(B)가 바로 사라지고 B′가 보통 꼬리로 붙는다(D4) | 회색 |
| g | 열린 ```` ``` ```` 안에서 `---` | 지금 규칙 | 지금 규칙(전체) | `---`가 코드 안 | 보통 색 |
| g2 | `~~~` 안의 `---` | 지금 규칙 | 경계(결정대로 `~~~`는 펜스 아님) | 선 | 회색 |
| h | 자동 방향, 영어 A 뒤 한국어 산문 B. [A---B] 뒤 언어로 거절된 덧붙임·편집도 같다 | 전체 재번역 | 거절 → 전체 경로. D1로 A부터 차례로, 언어 쌍은 원문 전체 기준(v1 한계). 고치지 않은 위 블록을 따로 버리지 않는다(3.7) | 흐린 이전 번역(위 블록 전부) 유지 후 한 번에 교체. `---` 없음, 선 있음. B 번역 방향은 한계 | 회색 |
| h2 | 자동 방향, 코드 위주 B(펜스·명령) | 전체 재번역 | B만(D5) | T(A)+선+T(B) | 회색 |
| i | B는 그대로 두고 A만 편집 | 전체 | A′만. 이어서 B는 캐시(0회) 또는 재요청 | 흐린 이전 번역 유지 후 한 번에 교체 | 회색 |
| j | ⌘↩ | 없음 | 0회 | T(A) | 커서 아래, 회색 |
| j2 | `A⏎⏎-`·`A⏎⏎--`에서 ⌘↩ / 열린 펜스 안 ⌘↩ | — | 0회(`---`로 채움) / 메뉴 꺼짐 | T(A) | 회색 / — |
| k | 구분선 줄 자체를 지움(병합) | — | 지금 규칙(빈 줄 꼬리, `replanned`, 또는 전체) | 규칙대로 | — |
| l | `A⏎---⏎B` | 일반 A도 `A⏎-`에서 전체 | B만 | 선 | 회색 |
| m | `A---`, `--- x`, `⏎⏎- 목록`, `⏎⏎␠␠---` | 지금 규칙 | 지금 규칙 | — | 보통 색 |
| n | 붙여넣은 B 안의 `---`(B1---B2) | B 입력에 포함 | B1, B2 차례로 | T(B1)+선+T(B2) | 회색 |
| o | 한 디바운스 안에 `B⏎⏎---⏎⏎C` | — | B, C 차례로 | 선 | 회색 |
| p | 원문 전체가 4,000자 초과 | 앞 결과 유지 + 길이 오류 | 같다 | 같다 | 회색 유지 |
| q | '전체 다시 번역', 제공자·방향 변경 뒤 '다시 번역' | 전체, `---` 찍힘, 링크 소실(§14) | 블록마다 차례로('전체 다시 번역'은 캐시 우회) | 흐린 이전 번역 유지 후 한 번에 교체, 선 유지. 첫 블록이 복사본과 같으면 링크 유지 | 회색 |
| r | 구분선만 남은 원문(`---`, `-`, `--`) | `---` 번역 | 0회, 빈 원문 | 비움 | `---` 회색 |
| s | 일반 A 뒤 한 키씩 `⏎⏎--x` | `--x` 꼬리 | `--x` 꼬리(회귀 방지) | — | — |
| t | 빈 원문에 ⌘V A + 디바운스 안 ⌘↩(+ ⌘V B) | 첫 요청 `A⏎⏎---⏎⏎(B)` | A, 그다음 B | T(A)(+선+T(B)) | 회색 |
| u | 구조 복사(markup) 원문 안의 `---` | 전체(구조) | 전체(구조, 자르지 않음) | 지금과 같다 | 보통 색 |
| v | YAML 머리말 `---⏎title: x⏎---⏎⏎본문` | 전체 | 머리말 `---⏎title: x`와 본문 차례로(닫는 `---`는 경계) | 선 | 닫는 줄만 회색 |
| w | CRLF(`A\r\n\r\n---\r\n\r\nB`), NBSP로 끝나는 A | 전체 | B만 | 선 | 회색(`---`만) |

## 5. 구현 순서

공통 규칙(D9):

- 구현 당시의 지정된 작업용 checkout에서만 작업한다. 커밋·푸시·stash·브랜치 생성·스테이징을 하지 않는다. 스테이징은 리드가 끝에 하고 사용자가 확인한다.
- 각 단계는 테스트를 먼저 쓰고 실패를 본 뒤 고친다. 변경은 최소로, 기존 스타일(짧은 주석, 한국어 문서)로 한다.
- 작업 중에는 해당 스위트를, 단계 끝에는 `./scripts/test.sh`(약 2분)를 돌린다. 알려진 불안정 테스트(`plans/remaining-work.md` '알려진 테스트 불안정')는 회귀로 단정하기 전에 한 번 다시 돌린다. DeepKApp.swift는 `./scripts/build.sh`로만 컴파일된다.
- 실행 중인 deepK 앱을 실행·설치·종료하지 않는다. GUI 테스트(`DEEPK_RUN_GUI_TESTS`)를 돌리지 않는다. 창을 연다.
- 새 테스트 파일은 `scripts/test.sh` 컴파일 블록에 넣는다. 새 테스트 함수는 `runAll`에 등록한다.

단계:

0. **기준선.** `./scripts/test.sh` 통과를 확인한다.
1. **planner(순수, 약 150줄).**
   - 테스트: `plannerBoundaries` 확장, 새 `explicitBoundaryPlanner`, I1·I2 성질 테스트(6절).
   - 변경: `Tail.explicit`, 3.3의 함수들, 3.5의 순서.
   - 기존 planner 기대값은 바꾸지 않는다. 바뀌는 것은 `⏎⏎-`, `⏎-` 같은 입력 중 상태와 경계 구분선이 든 꼬리뿐이다.
2. **TranslationDocument(순수, 약 70줄).**
   - 테스트: 새 `explicitBoundaryDocument`.
   - 변경: covering, retainingSuffix, join, `rendered`·`unitBreaks`, `replanned`.
3. **Store 핵심(약 110줄).** 세 묶음으로 나눠 각각 테스트 → 구현한다.
   - 3a 요청 단위(3.6): 첫 요청 자르기, snapshot·separator·markup, `complete`의 `basis.input`, `reuseEquivalentActiveRequest`, `isBlankSource`.
   - 3b 대응 순서(3.8): `reconcileInput` 순서와 `replanned`·token 취소, D5 언어 규칙(`continuesFirstRequest` 포함).
   - 3c 표시·재번역: `TranslationDisplay.unitBreaks`, `supersededBreaks`, `complete`의 흐림 해제 조건, `finishSegment` 플래그, `hasPartialResult`.
   - 테스트: 새 `explicitBoundary`·`explicitBoundaryRaces`·`explicitBoundaryLanguage`·`explicitBoundarySimulation`, 기존 스위트 확장(6절).
4. **결과 창 선(약 60줄).**
   - 테스트: `TranslationResultTextViewTests.unitBreaks` 신규와 `apply(breaks:)` 인자, 복사 깨끗함, 스트리밍, offset 변환·캐시, 삭제·흐림. `StableAppendIntegrationTests`의 명시 경계 시나리오.
   - 변경: `TranslationResultContent.unitBreaks`, `ResultTextView.unitBreaks`·선 위치 계산·`draw`, `ResultPane`이 `display.unitBreaks`를 전달.
5. **원문 창 회색(약 60줄, 선택 선 약 30줄).**
   - 테스트: 새 `DeepKTests/SourceEditorTests.swift`(창 없음)와 `test.sh` 블록 추가. store의 `sourceBoundaryLines` 테스트.
   - 변경: `TranslationStore.sourceBoundaryLines`(메모), `SourceEditor.boundaryLines`와 TextKit 2 rendering attribute, `TranslationView`가 전달.
   - TextKit 1로 바꾸지 않는다. 바꿔야만 하면 멈추고 리드에게 알린다.
6. **⌘↩(약 60줄).**
   - 테스트: planner의 `boundaryInsertion` 표·왕복(1단계에 함께), `SourceEditorTests`의 삽입·멱등·`onEdit`·조합 확정·`validateMenuItem`.
   - 변경: `SourceEditorProxy`, editor의 덧붙이기, `AppModel.sourceEditor`, `DeepKApp` 메뉴, `TranslationView` 전달.
7. **문서.**
   - `plans/incremental-translation.md`: §3 표에 명시 경계 행, §7 자동 방향 명시 꼬리, §8 표의 '전체 다시 번역'(블록마다), §12 판정 목록, 새 절 '명시 경계'(규칙·한계, 이 문서 링크).
   - `plans/result-structure.md` §4 첫 행: 명시 경계 뒤 꼬리와 블록 재번역은 링크를 유지한다(첫 블록이 복사본과 같을 때). 남은 경로(빈 줄 꼬리로 넘어가지 못하는 전체 번역)를 적는다.
   - `README.md:44` 단축키 문단에 ⌘↩와 `---` 경계, README 계획 문서 표에 이 문서.
   - `plans/mac-integration-checks.md`에 8절 수동 확인 항목.
   - 이 문서 끝에 '구현 결과' 절(실제 변경, 언어 임계값 측정, 남은 한계).
8. **검증.** 8절 명령. 수동 확인은 사용자에게 넘긴다.

## 6. 테스트 행렬

planner·문서(순수, `IncrementalTranslationTests`):

| 함수 | 검증 |
| --- | --- |
| `plannerBoundaries` 확장 | 기존 기대값 그대로. `tail(after: "x = 1 \| y", in: …+"⏎⏎---⏎⏎B") == Tail("⏎⏎---⏎⏎", "B", explicit: true)`. 비일반 B도 받는다. `A---B`, `⏎⏎- item`, `⏎⏎␠␠---⏎⏎B`, `⏎⏎--- x`, `⏎⏎- - -⏎⏎B`, `⏎⏎***⏎⏎B`, `⏎⏎—⏎⏎B`는 명시가 아니다(코드 A면 nil) |
| `explicitBoundaryPlanner` 신규 | 입력 중 `⏎⏎-`, `⏎⏎--`, `⏎⏎---`, `⏎⏎---⏎`, `⏎⏎---␠`, `⏎-`, `⏎---`는 빈 꼬리(코드 A 뒤에도). 구분선 여러 줄은 경계 하나. CRLF. NBSP: A가 NBSP로 끝남, GAP에 NBSP만 있는 줄. 펜스: `Run:⏎```bash⏎ls`·bare `⏎```⏎ls` 뒤는 nil, 닫힌 펜스 뒤는 명시, 열린 펜스 안의 ```` ```swift ````는 닫지 않음, 한 줄 ```` ```code``` ````는 펜스가 아님, `~~~` 안은 명시. prefix 끝 경계: `A⏎⏎---`+`⏎⏎B` → separator `⏎⏎`, `A⏎⏎-`+`--⏎⏎B` → separator `--⏎⏎`·명시 |
| 같은 함수: P0-1 | prefix `A⏎⏎-`, 원문 `A⏎⏎-⏎` → nil(빈 꼬리 아님). prefix `A⏎⏎--`, 원문 `A⏎⏎--⏎⏎B` → nil. prefix `A⏎⏎---`, 원문 `A⏎⏎---x` → nil. prefix `A⏎⏎---`, 원문 `A⏎⏎----` → 빈 명시 꼬리 |
| 같은 함수: D1 자르기 | `A` 뒤 `⏎⏎---⏎⏎B⏎⏎---⏎⏎C` → `B`. `A` 뒤 `⏎⏎B⏎⏎---⏎⏎C` → `B`(빈 줄 꼬리). `B1⏎⏎---⏎⏎B2` 붙여넣기 → `B1`. 끝 떼기: `…B⏎⏎---`, `…B⏎⏎--`, `…B⏎⏎` → `B`. `firstUnit`: `A⏎⏎---⏎⏎B` → ("", "A"), `---⏎⏎B` → ("---⏎⏎", "B"), `⏎⏎---⏎⏎B` → ("⏎⏎---⏎⏎", "B"), `---⏎title: x⏎---⏎⏎본문` → ("", "---⏎title: x"), `A⏎⏎` → ("", "A"), 열린 펜스 안 `---`는 자르지 않음 |
| 같은 함수: D8 범위 | [A---B] 뒤 `⏎⏎C⏎⏎---⏎⏎D` → `C`이고 검사 범위가 `B⏎⏎C`(코드 C면 nil). 코드 A---일반 B 뒤 `⏎⏎C` → `C`. 비일반 B면 nil |
| 같은 함수: 보조 함수 | `isBlankSource`: `""`, `⏎`, `---`, `-`, `--`, `⏎⏎---⏎⏎`는 참. `-5`, `--x`, `---⏎title`은 거짓. `leadingDelimiter`: `---⏎⏎B` → `---⏎⏎`, `---⏎B` → `""`, `⏎⏎B` → `⏎⏎`, `␠␠⏎B` → `␠␠⏎`. `boundaryLineRanges`: 이모지·한글 뒤 UTF-16, CRLF는 `\r\n` 제외, 건너뛸 prefix, 펜스 안·입력 중·빈 줄 없는 맨 앞 제외 |
| 같은 함수: ⌘↩ 표 | 3.11 표의 각 행이 `boundaryInsertion`과 같다. 각 결과 s에 대해 `tail(after: 원문, in: s)`가 빈 꼬리이고 covering이 성공한다. 열린 펜스·내용 없음은 nil |
| 같은 함수: 성질(I1·I2) | prefix {일반 A, 코드 A} × trailing {"", `⏎`, `⏎⏎`, `⏎⏎-`, `⏎⏎--`, `⏎⏎---`, `⏎⏎---⏎⏎`} × suffix {"", `⏎`, `⏎⏎B`, `-`, `--`, `x`, `⏎⏎---⏎⏎`, `⏎⏎---⏎⏎B`, `⏎⏎```⏎`}. ① 빈 꼬리면 covering 성공. ② 꼬리가 있으면 I2. ③ input에 경계 구분선 없음 |
| `explicitBoundaryDocument` 신규 | `[("",A,""),("⏎⏎---⏎⏎",B,"")]`, `[("",A,"⏎⏎---⏎⏎"),("",B,"")]`, `[("",A,"⏎⏎-"),("--⏎⏎",B,"")]` 모두 `text == "T(A)⏎⏎T(B)"`, `unitBreaks == [T(A).utf16.count]`. 비명시 `⏎⏎⏎`의 개행 규칙은 그대로. `text(appending:separator:"⏎⏎---⏎⏎")`는 최종의 prefix. covering: `A⏎⏎-`, `A⏎⏎--`, `A⏎⏎---`, `A⏎⏎---⏎⏎` 성공, 열린 펜스 뒤 `⏎⏎---` 실패. retainingSuffix: `---⏎⏎B`, `⏎⏎---⏎⏎B` 성공, unitBreaks `[]`. `replanned`: 명시 경계에서만 자름, 빈 줄 경계의 완료 B 편집은 nil, trailing을 비운 재계획(`A⏎⏎--x`, `A⏎⏎-⏎`), 가운데 삭제(A---B---C → A---C)는 `[A]` + `C`. 리뷰 2차 추가: 첫 꼬리가 거절되면(`[A---B]` 뒤 `⏎⏎ok`) nil이고 `[A]` + `B⏎⏎ok`로 내려가지 않는다 |

Store(비동기, `TranslationProbe`로 순서 제어. 따로 적지 않으면 `IncrementalTranslationTests`):

| 함수 | 검증 |
| --- | --- |
| `explicitBoundary` 신규 | 코드 기호 A를 seed하고 `editSource`로 `⏎`,`⏎`,`-`,`-`,`-`,`⏎`,`⏎`를 한 키씩 입력한다. 키마다 요청 0회, `display.isStale == false`, T(A) 유지, `canCopy`. B를 붙이면 `request.input == B`, `markup == nil`. 완료 뒤 `resultText == "T(A)⏎⏎T(B)"`, `display.unitBreaks == [T(A).utf16.count]`, A의 segment id 유지. `resultCopy`·`resultInsertionText`에 `---` 없음. `sourceBoundaryLines`가 `---` 범위. CRLF·NBSP 원문도 같다 |
| 같은 함수: P0-1 | 일반 A·코드 A에서 `A⏎⏎-` 뒤 `⏎`: 트랩 없음, 요청 input이 원문을 빠짐없이 덮음(`-`가 내용으로 요청됨). `A⏎⏎--` + ⌘↩ 결과: 0회. 일반 A `A⏎⏎--` 뒤 `⏎⏎B`: `--⏎⏎B` 요청(누락 없음). `…B⏎⏎--`에서 B 요청 중 `-`: B 취소 없음. I5(리뷰 2차 추가): `A⏎⏎B⏎⏎---`에서 B 요청 중 `---`·`⏎⏎---`를 지움 → B 취소 없음, 요청 2회(snapshot을 원문으로 잡으면 실패) |
| `explicitBoundaryRaces` 신규 | c2·c3: 문서 기준 꼬리(3.8 2단계)가 진행 중 꼬리를 유지한다. c2는 B 유지, C는 B 완료 뒤. c3는 C 유지, D는 C 완료 뒤, 진행 내내 `displaySegments`를 이은 문서 input이 원문 prefix, 상태와 화면이 일치, 캐시 항목 수가 문서 수와 맞음(`testCacheIsConsistent`). 3단계는 지나지 않는다(리뷰 2차 계측). `replanned` 뒤 token 취소(P0-2, 리뷰 2차 추가): [A---B] 완료, 빈 줄 꼬리 C 진행 중 `⏎⏎`+코드 덧붙임 → C 취소, 디바운스 안에 덧붙임을 지우고 C의 늦은 응답 → 무시, 문서는 원문 prefix, 이어 `B⏎⏎C` 한 블록. t: 빈 원문 ⌘V A + 디바운스 안 ⌘↩(+ ⌘V B) → 요청 [A](, B). b2: A 진행 중 `⌘↩ ⌘V B ⌘↩ ⌘V C` → 요청 A, B, C 차례로 총 3회, 선 2개. n: B1---B2 붙여넣기 → 2회. retainingSuffix + token rebase: [A,B] 완료, C 진행 중 `A⏎⏎---⏎⏎` 삭제 → C 취소 없음, 완료 뒤 T(B)+선+T(C), id 유지 |
| `explicitBoundaryLanguage` 신규(자동 방향) | 영어 A + 펜스 코드 B, 영어 A + `x = 1 \| y`, 한국어 A + 펜스 `kubectl get pods` → B만. 한국어 A + 펜스 없는 명령 한 줄은 임계값 측정 결과를 고정. 영어 A + 한국어 산문 B(h) → 거절, 첫 fallback 요청이 A 하나이고 어떤 요청에도 `---` 없음. A 진행 중(`continuesFirstRequest`)에도 같은 규칙. 리뷰 2차 추가: 영어 [A---B] 완료 뒤 `⏎⏎ok`, `⏎⏎한국어 문단`, `⏎⏎---⏎⏎한국어 블록` → T(A)+선+T(B)가 함께 흐려지고(B만 사라지는 순간 없음) fallback은 A부터, 한 번에 교체. fallback이 보낸 한국어 블록 뒤 공백 → 그 요청 유지(3.8 3단계). 이어 그 블록을 고치면 다시 전체가 흐려지고 A부터 |
| `explicitBoundarySimulation` 신규 | 고정 seed 무작위 키 시뮬레이션(알파벳 {`A`, `x=1`, `⏎`, `␠`, `-`, ```` ``` ````, `B`}, 지우기, ⌘↩, 요청 완료·실패를 섞어 수백 단계). 단계마다 트랩 없음, `.waiting`·`.translating` 정체 없음(대기 요청이 있거나 상태가 맞음), 문서 input이 원문 prefix, 요청 input에 경계 구분선 없음 |
| `firstRequestContinuity` 확장 | b: 코드 기호 A를 스트리밍하는 중에 구분선과 B를 입력한다. 첫 요청을 취소하지 않고, 두 번째 요청이 B이며, 총 2회. 문서가 생기기 전에도 `sourceBoundaryLines`가 채워진다. B를 고쳐도 A는 취소되지 않는다(snapshot = A) |
| `appendAndQueue` 확장 | c: 코드 A---일반 B 뒤 `⏎⏎C` → C만. 비일반 B면 `B⏎⏎C`를 요청하고 A의 segment는 유지, 흐린 표시 없음 |
| `removeLeadingUnits` 확장 | d: `B`, `---⏎⏎B`, `⏎⏎---⏎⏎B`(cacheCapacity 0)에서 `resultText == T(B)`, B의 id 유지, 요청 0회. 경계 바이트가 A.trailing에 있는 경우도 반복. d2: A---B---C → A---C 0회(`paragraph-v1`), cacheCapacity 0이면 C만 요청 |
| `coverageEdgeCases` 확장 | e: `A`, `A⏎⏎-`, `A⏎⏎--`, `A⏎⏎---`, `A⏎⏎---⏎⏎` 요청 0회, 연결이 끊겨도 같다. g: 열린 펜스 prefix + `⏎⏎---⏎⏎B` → 원문 전체 요청. r: `---`·`-`·`--`만 남은 원문 → 0회, 명시 호출은 `.emptyInput` |
| `editAndRetry` 확장 | f: 완료 B를 줄이기·가운데 편집·한 줄 개행으로 늘리기 → `request.input == B′`, A id 유지, T(B)는 바로 사라짐. 되돌리면 `paragraph-v1`에서 0회. 빈 줄 경계의 완료 B 편집은 지금처럼 전체 |
| `supersededDisplay` 확장 | i: [A---B]에서 A만 편집 → 흐린 이전 번역(선 포함, `supersededBreaks`), 요청 A′ 하나, A′ 완료 뒤 B는 캐시로 0회, 흐림은 원문 전체를 덮을 때 한 번 교체(중간에 T(A′)만 보이는 순간 없음). cacheCapacity 0이면 B 재요청 동안 흐림 유지 |
| `wholeRetranslation` 확장 | q: [A---B] '전체 다시 번역' → A, B 차례로(B도 캐시 우회), `---` 없음, 흐림 유지 후 한 번 교체, 선 유지. B 실패 뒤 '다시 시도'는 A부터. 제공자 변경 뒤 '다시 번역'·방향 변경도 블록마다. 경계 없는 원문은 지금처럼 원문 전체 한 요청(`whole.input == ab` 유지) |
| `cacheAlignment` 확장 | [A---B] 완료 → 무관한 원문 → 원래 원문: 0회, `display.unitBreaks` 유지(캐시 복원) |
| `streamingPrefixInvariant` 확장 | 원문 `a⏎⏎---⏎⏎b`, `a⏎---⏎b`, `a⏎⏎⏎---⏎⏎⏎b`: `tail.input == b`, 모든 스냅샷이 최종의 prefix, 결합 개행은 정확히 2 |
| `compositionAndLimits` 확장 | 경계 뒤 B를 IME로 조합하는 중에는 T(A) 유지·요청 0회, 확정 뒤 B만. 4,000자 전체 한도 단언(`:762-763`)은 그대로 |
| `proseWithPunctuationAppends` 확장 | s: 일반 A 뒤 한 키씩 `⏎⏎--x` → 요청 input `--x` |
| `TranslationStoreTests.copiedStructureTravelsWithTheSource` 확장 | `\|`·`=`가 든 구조 복사 A에 구분선을 치고 B를 붙인다. B 요청은 `markup == nil`. `display.inline`이 A의 링크·칩을 유지한다. `resultCopy.plain`에 `---`가 없다. 이어서 '전체 다시 번역': 첫 요청이 A와 복사 구조(`markup(for: A)`), 다음이 B(구조 없음), 링크 유지, 같은 A를 되풀이 요청하지 않음. u: `---`가 든 구조 복사는 원문 전체를 구조와 함께 요청, `sourceBoundaryLines == []`. 리뷰 2차 추가: 완료 뒤·진행 중·캐시 복원 뒤에 `⏎⏎---⏎⏎B`를 치면 회색은 친 줄 하나. 구조 복사 A 뒤 [A---B]에서 위 블록을 지우면(`---⏎⏎B`) 0회, 맨 앞 `---` 회색(d) |
| `TranslationStoreTests.cosmeticWhitespaceReusesActiveRequest` 등 기존 | 그대로 통과(끝 공백을 떼도 `result.input == sourceText`) |

결과 창·원문 창:

| 파일 · 함수 | 검증 |
| --- | --- |
| `TranslationResultTextViewTests.unitBreaks` 신규 | 선이 없으면 두 단위 사이 띠에 잉크가 없다. breaks를 주면 잉크가 있다(2 device row 이하). breaks만 바뀐 갱신은 저장소를 고치지 않고(EditSpy), 선택·스크롤을 유지한다. `view.string`에 `-`·U+FFFC가 없다. lineSpacing 6, 폭 220↔320에서도 사이에 있다 |
| 같은 파일 복사·스트리밍·변환·삭제 | 경계를 걸친 선택의 ⌘C·`writeSelection`은 `"T(A)⏎⏎T(B)"`. 서식 포함·마크다운 복사에 `---`·`<hr>`가 없고 `<p>`가 둘. 스트리밍 중 선을 그리고, T(A)는 복사할 수 있고 초안은 못 한다. 아래가 비면 그리지 않는다. ```` ```py ```` 박스·`<a1>`·`` `read` ``가 있는 위 단위에서도 위치가 맞다(박스 아래, 다음 글 위). 위 단위를 지우면 선이 글과 함께 움직이고, breaks `[]`면 사라진다. 흐린 글도 선을 유지하고 복사되지 않는다. 스트리밍 틱에 완료 부분 offset 변환을 다시 하지 않는다(캐시). 리뷰 2차 추가: 끝이나 앞에 빈 코드 줄이 있는 코드 박스(```` ```py⏎print(1)⏎⏎⏎``` ````, ```` ```⏎⏎⏎ls⏎``` ````)에서도 선은 박스 밖이다 |
| `StableAppendIntegrationTests` 확장 | `apply()`가 `unitBreaks: display.unitBreaks`를 전달한다. 코드 기호 A에 `⏎⏎---⏎⏎`+B를 붙이고 B를 완료한다. 읽던 위치·선택 불변, `view.string == T(A)+"⏎⏎"+T(B)`, `unitBreaks`는 스트리밍 중과 완료 뒤 모두 `[T(A).utf16.count]` |
| `DeepKTests/SourceEditorTests.swift` 신규(창 없음, `test.sh`에 블록 추가) | TextKit 2 유지(`textLayoutManager != nil`, 적용·그리기 뒤에도). `boundaryLines` 적용 뒤 `.foregroundColor` rendering attribute가 정확히 `---`에 있다(`enumerateRenderingAttributes`). `string =` 뒤에도 다시 붙는다. `[]`면 사라진다. 조합 중(`setMarkedText`) 적용해도 marked range가 유지된다. 선택 선을 구현하면 픽셀(대시 오른쪽에만 알파 > 0). proxy: 덧붙이기 뒤 커서 끝, 조합 없을 때 `onEdit` 1회, 빈 덧붙임은 `onEdit` 0회(멱등), 조합 중에는 확정 뒤 덧붙임(`onEdit` 2회). `validateMenuItem`은 창 없음·key 아님·`insertion == nil`에서 거짓. 리뷰 2차 추가: 대시 하나·`⏎⏎---⏎` 구간·전체를 같은 글로 바꿔 쳐도 갱신 없이 회색과 가는 선이 그대로다 |
| `Fixtures/SourceEditorIMESmoke.swift`(GUI) | 사용자 수동. 구현자는 컴파일만 확인한다. `---⏎⏎` 바로 뒤 한글 조합이 유지되고 회색이 남는다. 조합 중 ⌘↩는 '한'을 확정한 뒤 구분선을 붙인다 |

## 7. 범위 밖과 후속

| 항목 | 내용 | 규모 |
| --- | --- | --- |
| M0 완전판 | 이전 문서의 뒤 단위를 정확한 입력 + 경계로 묶은 재사용 풀에서 꺼낸다. 캐시 만료(300초)·용량·`cacheCapacity 0`에서도 B를 다시 요청하지 않는다 | 약 1일 |
| 첫 단위 캐시 조회 | 잘린 첫 요청이 원문 전체 key를 놓치면 첫 단위 key(`document-v1`)로 한 번 더 찾는다. fallback·되돌리기에서 A 재요청을 줄인다 | 작음 |
| '전체 다시 번역' 남은 블록부터 재시도 | 지금은 실패하면 첫 블록부터 다시 한다 | 작음 |
| M1 가운데에 진행 단위 허용 | 삽입 위치 token, 범위 단위 흐림·복사 차단, 가운데 초안 보류, 힌트·스크롤 변경. `endsInDraft`·스트리밍 보류·`accepts`·covering의 '끝에만 진행' 가정을 모두 깬다 | 2–3일, 위험 높음. 권하지 않는다 |
| 자동 방향에서 다른 언어 B | 단위별 언어 쌍을 저장하고 B의 언어 쌍을 따로 판정한다. §7 '한 문서 안에서 목표 언어를 섞지 않는다'를 고친다. 지금은 거절 → A부터 다시(h) | 약 0.5일 |
| 단위당 4,000 + 전체 약 20,000 | 3.12. 영향 범위가 넓다 | M0 완전판 이후 |
| ⌘Z(원문 창 `allowsUndo`) | 외부 교체(두 번 복사, 지우기) 때 실행 취소 스택을 비워야 한다 | 작음 |
| ⌘V로 붙인 B의 링크 복원 | 원문 창은 일반 텍스트다(결과 구조 유지 2절 결정) | 범위 밖 |
| A 문맥을 B 요청에 참고로 싣기 | 증분 번역 §7 후속과 같다 | 범위 밖 |
| ⌘↩ 화면 안내 | 하단 막대(2026-10-13 상태 행을 합침)나 원문 자리표시에 안내 | 디자인 확인 |
| 구조 A 뒤 B의 백틱 | A의 코드 집합(`.only(...)`)이 T(B)의 백틱을 숨긴다(§14 기존 동작). 붙여넣은 B에 코드가 있으면 더 잘 보인다 | 후속 |
| 공백만 다른 원문의 캐시 복원 | plain 정규화로 key가 같아도 바이트가 달라 covering이 실패하면 한 단위로 복원되어 선이 없다(기존 동작) | 후속 |
| 열린 펜스 안에서 끝나는 A의 `---` | 펜스 안이므로 내용이다. T(A)에 `---`가 찍힐 수 있고 선·회색이 없다 | 유지 |
| 원문 창 회색 TextKit 1 전환 | TextKit 2로 안정적이지 않을 때만, 별도 단계로 | 필요 시 |

유지하는 한계(사양 7): ⌘V는 일반 텍스트라 B의 링크는 돌아오지 않는다. B는 A의 문맥 없이 번역한다. 블록이 많을수록 요청이 차례로 늘어난다(D2). 4,000자는 원문 전체 기준이다. 완료된 B를 고치는 동안 T(B)는 비어 있다(D4).

## 8. 검증 명령

```bash
cd /path/to/deepK
./scripts/test.sh          # 전체 headless 스위트(약 2분). 알려진 불안정 테스트는 한 번 다시 실행
./scripts/build.sh         # Debug 빌드 + 서명(앱을 실행하지 않음). DeepKApp.swift(⌘↩ 메뉴)는 여기서만 컴파일된다
git diff --check
```

개발 중 빠른 실행(TranslationStore·증분 스위트):

```bash
T=$(mktemp -d /private/tmp/deepk-unit-test.XXXXXX); swiftc -swift-version 6 -warnings-as-errors -module-cache-path $T/cache -DTRANSLATION_STORE_STANDALONE DeepK/Translation/TranslationStore.swift DeepK/Translation/TranslationDocument.swift DeepK/Translation/IncrementalTranslationPlanner.swift DeepK/Translation/TranslationMarkup.swift DeepKTests/IncrementalTranslationTests.swift DeepKTests/TranslationStoreTests.swift -o $T/s && $T/s
```

IME 픽스처는 컴파일만 한다(실행하면 창이 열린다):

```bash
T=$(mktemp -d /private/tmp/deepk-ime-compile.XXXXXX); swiftc -swift-version 6 -warnings-as-errors -module-cache-path $T/cache DeepK/Translation/SourceEditor.swift DeepKTests/Fixtures/SourceEditorIMESmoke.swift -o $T/ime
```

`test.sh`에 더할 블록(`TranslationResultTextView` 블록 뒤):

```bash
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/SourceEditor.swift" \
  "$PROJECT_ROOT/DeepKTests/SourceEditorTests.swift" -o "$TEST_DIR/SourceEditor"
"$TEST_DIR/SourceEditor"
```

사용자 수동 확인(구현자는 하지 않는다. `plans/mac-integration-checks.md`에 남긴다):

- [ ] `DEEPK_RUN_GUI_TESTS=1 ./scripts/test-input.sh`(창을 연다). `---` 뒤 한글 조합과 가로줄.
- [ ] 코드 기호와 링크가 있는 Chrome 문단을 ⌘C 두 번 → 원문 끝에서 ⌘↩ → 다른 메시지 ⌘V. 요청 1회, T(A) 링크 클릭, 선 표시, 복사·삽입에 `---` 없음.
- [ ] A 번역 중 `⌘↩ ⌘V B ⌘↩ ⌘V C`. 요청 3회가 차례로, 선 2개.
- [ ] 결과 창을 클릭한 상태와 설정 창이 key인 상태에서 ⌘↩. 앞은 동작하고 뒤는 무시된다. 열린 펜스 안에서는 메뉴가 꺼진다.
- [ ] 한글 조합 중 ⌘↩, 가로줄 바로 아래 줄에서 한글 입력. 가로줄과 조합 유지(같은 줄 뒤에는 커서가 가지 않는다, 2026-10-14).
- [ ] 흰 배경에서 결과 선과 원문 가로줄(둘 다 `separatorColor` 1pt)의 대비. 작게·크게 창. 패널이 라이트로 고정이라 다크 모드는 확인하지 않는다.
- [ ] 위·아래·가운데 블록 삭제에서 네트워크 없이 즉시 복원(연결을 끊고 확인).
- [ ] 완료된 B를 고칠 때 T(B)가 비는 동안의 느낌(D4), '전체 다시 번역'이 블록마다 도는 시간.

## 9. 결정 기록

| 결정 | 내용 |
| --- | --- |
| D1 | 명시 경계는 어디서나 단위를 끊는다. markup 없는 모든 요청(첫·전체 요청, 증분 꼬리, '전체 다시 번역', 제공자·방향 재번역)을 펜스 밖 첫 경계에서 자르고, 끝 GAP_END는 요청에 넣지 않는다. 구조 복사 요청은 자르지 않는다. 맨 앞 경계는 빈 줄이 함께 있을 때만 뗀다(3.2) |
| D2 | 진행 요청은 하나다. 블록이 많으면 요청이 차례로 늘어난다 |
| D3 | 4,000자는 원문 전체 기준. 캐시 정책 버전은 키의 뜻이 그대로이므로 올리지 않는다(3.12, 3.13) |
| D4 | 완료된 아래 블록 B를 고치면 T(B)는 바로 사라지고 B′는 흐림 없는 보통 꼬리다. 위 블록을 고치면 지금처럼 흐린 fallback이다 |
| D5 | 자동 방향의 명시 꼬리는 반대 지원 언어로 확신할 때만 거절한다(3.8) |
| D6 | 원문 창 회색은 TextKit 2 rendering attribute로 한다. 선은 선택이다. TextKit 1 전환은 불가피할 때만, 보고서에 명시한다(3.10). 2026-10-13: 회색 대신 대시를 투명 rendering attribute로 숨기고 컨테이너 폭 전체에 선 하나를 긋는다(10절) |
| D7 | ⌘↩는 덧붙이기만 하고, 끝 `-`·`--`를 채우고, 열린 펜스 안에서 꺼진다. `onEdit` 1회 단언은 조합하지 않을 때만이다(3.11) |
| D8 | 빈 줄 경로의 `isPlainText` 범위는 prefix에서 구한 UTF-8 offset 하나를 prefix와 원문에 함께 쓴다. 경계 문법의 공백은 `isBlank`와 같은 집합이다(3.1, 3.5) |
| D9 | 작업 규칙(5절) |

독립 검토 반영:

| 지적 | 반영 |
| --- | --- |
| P0-1 trailing의 입력 중 대시를 번역된 prefix로 봄(크래시·누락·불필요한 취소) | 3.5 2·4단계, `replanned`의 trailing 비우기, I1·I2 성질 테스트, 무작위 시뮬레이션 |
| P0-2 문서 기준 관문과 `replanned`·token 경쟁 | 3.8 `reconcileInput` 순서, `replanned` 뒤 token 취소. 취소는 `explicitBoundaryRaces`의 'a tail planned against a dropped unit is cancelled'(리뷰 2차 추가)가, 3단계는 `explicitBoundaryLanguage`의 'whitespace after the pending block keeps it'이 고정한다. c2·c3는 문서 기준 판정을 확인한다 |
| P1-3 첫 요청에 `---` 섞임 | D1 첫 단위 자르기, I5 snapshot, `reuseEquivalentActiveRequest` 기준 변경 |
| P1-4 한 꼬리 안의 여러 경계 | D1 첫 경계 자르기(사용자 규칙 '`---`가 나눈다') |
| P1-5 자동 방향 코드 B | D5, `explicitBoundaryLanguage` |
| P1-6 ⌘↩ 구멍 | 3.11 표(`-`·`--` 채움), 펜스 안 메뉴 꺼짐, 근거 정정, `onEdit` 단언 범위 |
| P2-7 '전체 다시 번역' `---` 되풀이 | D1 블록 단위 + 캐시 우회 유지(`finishSegment`) |
| P2-8 T(B)가 흐림 없이 사라짐 | D4로 받아들이고 시나리오 c·f와 수동 확인에 적음 |
| P2-9 공백 집합 불일치 | 3.1 SP·NL 정의, NBSP 테스트 |
| P2-10 TextKit 1 전환 위험 | D6 TextKit 2 유지 |
| P2-11 관찰·성능 | 3.10 회색은 원문 기준 메모, 3.9 offset 변환 캐시 |
| P2-12 검사 범위 모호 | 3.5 6단계(offset 하나, 꼬리 끝까지) |
| P3 사실 정정 | `test.sh:86-92` 설명, 시나리오 d '지금' 열, 라이트·다크 수동 확인 삭제, 펜스 정보 문자열의 백틱, token.snapshot, `isBlankSource` 범위, 3.8 '바꾸지 않는 곳', `~~~`(g2), `invalidateResultAndWork` 줄 범위 `:697-725` |

## 10. 구현 결과 — 2026-10-13

단계별로 테스트를 먼저 쓰고 실패를 본 뒤 고쳤다. `./scripts/test.sh` 전체(18개 스위트)와 `./scripts/build.sh`(DeepKApp.swift 포함)를 통과했다. GUI 테스트와 실제 앱 실행은 하지 않았다.

| 단계 | 바뀐 파일 |
| --- | --- |
| planner·문서 | `IncrementalTranslationPlanner.swift`(줄 단위 경계 문법 `Layout`, `tail`·`firstUnit`·`unitEnd`·`isBlankSource`·`leadingDelimiter`·`isExplicitGap`·`boundaryLineRanges`·`boundaryInsertion`·`proseOutsideFences`), `TranslationDocument.swift`(`covering`·`retainingSuffix`·결합·`rendered`·`appendsExplicitly`·`replanned`) |
| Store | `TranslationStore.swift`(요청 자르기, `reconcileInput` 순서, D5, 흐림·재번역 플래그, `TranslationDisplay.unitBreaks`, `sourceBoundaryLines`) |
| 결과 창 | `TranslationResultTextView.swift`(`unitBreaks`, offset 변환 캐시, 선 그리기), `TranslationView.swift`(전달) |
| 원문 창·⌘↩ | `SourceEditor.swift`(`makeScrollView`, 회색·가는 선, `appendBoundary`, `SourceEditorProxy`), `AppModel.swift`(`sourceEditor`), `DeepKApp.swift`(편집 메뉴), `TranslationView.swift`(전달) |
| 테스트 | `IncrementalTranslationTests`·`TranslationStoreTests`·`TranslationResultTextViewTests`·`StableAppendIntegrationTests` 확장, 새 `SourceEditorTests`(`scripts/test.sh` 블록 추가), `Fixtures/SourceEditorIMESmoke.swift`(GUI, 컴파일만) |

계획과 다른 점:

- `isDelimiter`는 만들지 않았다. covering은 '원문의 내용 끝(`unitEnd`)이 남기는 단위의 끝을 넘지 않는다'로 판정한다. planner가 빈 꼬리를 주는 조건과 같은 식이라 I1이 구조상 성립한다. `endsInsideFence`·`plainScopeStart`는 `Layout` 안의 비공개 함수다.
- 마지막 줄이 내용으로 쓰인 `-`·`--`인 단위(`X⏎-⏎-`)는 요청 input에 줄바꿈을 남긴다. 떼면 token snapshot이 '대시를 치는 중'으로 읽혀 응답을 받지 못하고 `.translating`에 멈춘다(무작위 시뮬레이션이 찾음).
- D5는 진행 중인 첫 요청에는 사실상 쓰이지 않는다. `reuseEquivalentActiveRequest`가 첫 단위로 비교하므로 `---` 뒤 블록은 언어와 관계없이 A 완료를 기다렸다가 요청된다.
- 자동 방향에서 구분선만 남은 원문은 이전 번역을 흐리게 두지 않는다(계획 밖, 테스트 추가).
- 결과 창: break가 바뀌면 `needsDisplay` 대신 이전·새 선 자리만 다시 그린다. offset 변환 캐시는 이전 원문과 겹치는 앞부분 길이로 무효화한다. '↓ 새 번역 보기'의 선 다듬기는 하지 않았다. 흐린 이전 번역의 선은 같은 색이다.
- 원문 창(D6): TextKit 2를 유지했다. 회색은 `.foregroundColor`(tertiary) rendering attribute와 비공개 표시 키(`deepKBoundaryLine`)를 같은 범위에 달고, 다시 칠할 때 표시 키가 있는 구간만 지운다. 문서 전체의 `.foregroundColor`를 지우지 않으므로 시스템이 쓰는 rendering attribute를 건드리지 않는다. 조합 중인 글(marked text)은 rendering attribute가 아니어서 영향이 없다(테스트로 고정).
- 가는 선은 구현했다. 편집기 자체의 `drawBackground(in:)`에서 그린다. TextKit 2의 글자 조각 뷰 아래 층이라 글자·선택을 가리지 않는다. 위치는 `enumerateTextSegments`의 대시 frame에서 구하고, 글·범위·폭(`setFrameSize`)·글꼴이 바뀔 때 다시 구해 이전·새 자리만 다시 그린다. 앞 글의 추정 배치를 피하려고 마지막 선까지 `ensureLayout`한다. 다시 그리기(invalidation)는 창 없는 테스트로 관찰할 수 없어 수동 항목으로 남겼다.
- ⌘↩: `insertText` 대신 `shouldChangeText` → `textStorage.replaceCharacters` → `didChangeText`로 덧붙인다. 타이핑 경로는 자동 맞춤법 교정이 앞 단어를 고칠 수 있어 번역한 앞부분 바이트를 바꿀 수 있다. 덧붙일 것이 없을 때 beep하지 않는다(메뉴 항목이 꺼지면 AppKit 메뉴가 키를 먹어 줄바꿈도 beep도 없다). 메뉴 항목은 `SourceEditorProxy.makeMenuItem()`이 만들고 `DeepKApp`이 편집 메뉴 끝에 구분선과 함께 넣는다. 테스트가 같은 항목(제목·키·target)을 쓴다. 조합 중 ⌘↩는 `onEdit`을 2–3회 보낸다(NSTextView의 확정 알림, 재정의한 `unmarkText`, 덧붙임). 모두 조합 아님이다.
- `SourceEditorTests` 블록은 실제 `boundaryInsertion`·`boundaryLineRanges`로 확인하려고 planner와 그 의존 파일(`TranslationDocument`·`TranslationStore`·`TranslationMarkup`)을 함께 컴파일한다. `SourceEditor.swift` 자체에는 새 의존성이 없어 `test-input.sh`의 단독 컴파일이 유지된다.

D5 측정(macOS `NLLanguageRecognizer`, 펜스 밖 글 기준, 임계값 0.8):

| A의 언어 | 블록 | 1위 언어·확률 | 처리 |
| --- | --- | --- | --- |
| 한국어 | `kubectl get pods -n prod` | en 0.585 | 받음(B만) |
| 한국어 | `kubectl get pods` | en 0.773 | 받음 |
| 한국어 | `make test` | en 0.810 | 거절(A부터 다시) |
| 한국어 | `cargo build --release` | en 0.866 | 거절 |
| 한국어 | `SELECT …` | en 0.897 | 거절 |
| 한국어 | `docker compose up -d` | en 0.946 | 거절 |
| 영어 | 한국어 산문 | ko 1.000 | 거절 |
| 아무 언어 | ```` ``` ```` 펜스 안 코드만 | 판정할 글 없음 | 받음 |

테스트는 받는 kubectl 사례만 고정한다(인식기 버전에 따라 값이 바뀔 수 있다).

검증:

- `./scripts/test.sh` 전체 통과(약 2분). 첫 실행에서 PermissionPresentation 컴파일 중 `Internal Error: DecodingError.dataCorrupted`(빈 JSON) 한 줄이 출력됐지만 스위트는 통과했고, 같은 블록을 따로 다시 컴파일·실행하면 나오지 않았다. 컴파일러 쪽 일시 출력으로 본다.
- 무작위 시뮬레이션(고정 seed 1–3 × 200단계)은 정규 스위트에 있다. 구현 중 저장소 밖 사본으로 40 seed × 400단계(고정 방향), 31 seed × 300단계(자동 방향·한글·조합)를 더 돌렸다.
- 저장소 밖 사본에 결함을 하나씩 넣어(mutation) 새 테스트가 잡는지 확인했다. 원문 창: 회색 빼기·지우기 빠뜨림·폭/글꼴 변경 무시·선 그리기 빼기·선 간격 0·key 창 검사 빼기·포커스 이동 빼기·커서 이동 빼기·조합 확정 빼기·스크롤 빼기·글 기준 메모 빼기는 모두 잡혔다. 다시 그리기 범위 빼기는 창 없이 관찰할 수 없어 살아남았다.
- `./scripts/build.sh`(Debug, 서명)를 통과했다. 앱은 실행하지 않았다.

남은 한계와 후속(7절에 더해):

- 한국어 A 뒤 펜스 없는 짧은 명령은 영어로 확신해 A부터 다시 번역한다(위 표). 펜스로 감싸면 피한다. 임계값이나 코드 줄 제외는 사용해 보고 정한다.
- 자동 방향에서 영어 A 뒤 한국어 블록은 고칠 때마다 A부터 다시 번역하고, 블록의 언어 쌍은 원문 전체로 정한다(사례 h).
- 잘린 첫 단위는 원문 전체 캐시 키만 찾으므로 fallback에서 A를 다시 요청한다(7절 '첫 단위 캐시 조회').
- 드문 경우: 앞 trailing에 공백이 있고 다음 줄이 `␠-`이면 블록이 `-`로 요청된다. 내용이므로 동작은 맞다.
- 원문 창 ⌘Z는 여전히 없다(7절).
- 자동 방향에서 인식기가 영어로 보지 않는 짧은 덧붙임(`ok`, `LGTM`)은 전체 fallback이다(A부터, 블록마다 요청). 고정 방향에서는 그 문단만 요청한다(리뷰 2차).

### 리뷰 2차 반영 — 2026-10-13

독립 리뷰(state·ui·tests-docs) 지적마다 코드로 재현하거나 저장소 밖 사본에 결함을 넣어(mutation) 확인했다. 실제 결함은 테스트를 먼저 써서 실패를 본 뒤 고쳤다.

| 지적 | 확인 | 처리 |
| --- | --- | --- |
| state P2: 자동 방향 언어 거절이 `replanned`로 가서 고치지 않은 T(B)가 흐림 없이 사라지고 `B⏎⏎덧붙임`이 한 단위가 됨 | 재현(`ok`·`LGTM`·한국어 문단·`---`+한국어 블록, 캐시 0·32). 고정 방향은 `ok`만 요청 | `replanned`가 빈 꼬리가 아닌 첫 꼬리에서 결정하고, 거절이면 nil(3.7). store는 전체 경로(흐린 fallback, 사례 h)로 간다. T(A)+선+T(B)가 함께 흐리게 남고 한 번에 바뀐다. 한국어 블록을 고칠 때 B만 버리던 반복도 없어졌다 |
| state P3: 구조 복사 A를 지운 뒤 맨 앞 `---`가 회색이 아님 | 재현 | 회색에서 빼는 범위를 구조 단위의 `[separator 끝, input 끝)`으로(3.10) |
| ui P2: README의 ⌘↩ 조건('앞에 있으면')이 코드(key 창)와 다르고, ⌘C 두 번 뒤 ⌘↩가 원래 앱으로 감 | 확인(`showWindow(activate: false)` → `orderFrontRegardless`) | 코드 유지. README·3.11·[증분 번역](incremental-translation.md) §15·수동 확인 항목에 '번역 창을 클릭해 활성(key) 상태일 때'를 적음 |
| ui P3: 끝·앞에 빈 코드 줄이 있는 코드 박스 안에 선이 그려짐 | 재현(선 y=105.5, 박스 29–119) | 선 위치가 `codeBoxes()`와 같은 박스 계산(`codeBox`)을 쓴다 |
| ui P3: 대시를 같은 글로 바꿔 치면 회색이 사라지고 가는 선만 남음 | 재현(창 없는 테스트) | `Editor.didChangeText`에서 글이 칠한 글과 같으면 같은 범위를 다시 칠한다 |
| tests P1: `replanned` 뒤 token 취소를 잡는 테스트 없음 | 확인. 위 거절 멈춤 뒤에는 리뷰 시나리오(언어 거절 → k=1)로 닿지 않는다 | 닿는 경로(고정 방향, 빈 줄 꼬리 C 진행 중 코드 덧붙임 → 디바운스 안에 되돌림)로 고정. 취소를 빼면 C가 `[A]` 위에 붙어 문서가 원문 prefix가 아니다 |
| tests P2: 3단계 근거가 틀리고 실행되지 않음 | 확인(c2·c3는 2단계가 받는다) | 3.8 정정. 3단계가 쓰이는 실제 경로(자동 방향 fallback이 보낸 블록 뒤 공백)를 테스트로 고정하고 가지는 남겼다 |
| tests P2: I5 snapshot을 잡는 테스트 없음 | 확인 | B 진행 중 뒤 `---`·`⏎⏎---` 지우기 → 취소 없음 |
| tests P2: 회색 skip을 잡는 테스트 없음 | 확인 | 사례 u 확장(완료 뒤·진행 중·캐시 복원 뒤) |
| tests P3: [증분 번역](incremental-translation.md) §14가 U1과 어긋남 | 확인 | §14 한계 문단을 '일부 해소'로 갱신 |

리뷰 제안과 다르게 한 점:

- state P2의 '`replanned`는 원문이 문서로 시작하지 않을 때만'은 따르지 않았다. 순수 덧붙이기여도 trailing에 든 대시가 내용이 되거나(P0-1) 비일반 B 뒤 `⏎⏎C`(사례 c)는 `replanned`가 처리해야 한다. 대신 '거절된 첫 꼬리에서 멈춤'으로 같은 결과를 얻는다.
- state P2의 'B id 유지, B를 다시 요청하지 않음'은 전체 경로에서는 지킬 수 없다. 문서가 비고, fallback은 A부터 다시 요청하고(첫 단위 캐시 조회는 7절 후속), `B⏎⏎ok`는 한 블록이라 B가 다시 간다. `---` 뒤 블록이면 B는 `paragraph-v1` 캐시로 붙는다. 테스트는 'T(B)가 흐림 없이 사라지는 순간이 없고 한 번에 교체'를 고정한다. B를 남기고 덧붙임만 요청하려면 거절한 글을 문서 언어로 보내는 셈이라 §7 언어 규칙을 바꿔야 한다(후속 '자동 방향에서 다른 언어 B').
- state P3의 'segment id == basis id일 때만'은 쓰지 않았다. 캐시 복원은 basis에 새 id를 주므로 복원된 구조 문서 안의 `---`가 회색이 된다(테스트로 고정). 구조 단위가 아닌 첫 단위는 경계 줄을 품지 않으므로 그 글을 빼도 무해하다.

결함 주입 확인(저장소 밖 사본, 모두 새 테스트가 잡음): `replanned` 뒤 취소 빼기, snapshot을 원문으로, 회색 제외 범위 비우기(완료·진행 중 각각), 3단계 빼기, segment id 조건, separator까지 빼기, 거절 멈춤 빼기, 코드 박스 대신 글자 줄 기준, `didChangeText` 다시 칠하기 빼기.

### 원문 창 가로줄·스크롤바 여백 — 2026-10-13(사용자 피드백)

사용자 피드백: "`---`를 치면 마크다운 파일처럼 선 하나가 그어졌으면 한다", 화면 녹화 뒤 "`---` 글자가 보이는 것 자체가 어색하다, 선만 있으면 좋겠다". 회색 대시와 대시 오른쪽 8pt부터 시작하는 가는 선을 함께 보이던 모양을 없앴다. 또 "스크롤하면 스크롤바가 글을 가린다. 번역 창은 예전에 막았는데 원문 창은 아니다".

- 판정은 그대로다(`TranslationStore.sourceBoundaryLines`). 바뀐 것은 원문 창의 그리기뿐이다.
- 대시: `.foregroundColor`를 `NSColor.clear`로 단 TextKit 2 rendering attribute로 늘 숨긴다. 커서·선택이 그 줄에 있어도 드러내지 않는다(Obsidian식 드러내기 없음). 복사하면 `---`가 나온다. 커서는 숨은 대시 사이를 지나가지 않는다(아래 '선은 한 덩어리'). `--`·`---x`처럼 경계가 아니게 되면 다음 갱신에서 보통 글로 돌아온다. TextKit 2는 새로 친 글자에 rendering attribute를 붙이지 않으므로(하네스 확인) 숨은 대시 곁에 끼어든 글자(갱신 전의 옛 선 등)는 store 갱신 전에도 바로 보인다. 같은 글자로 바꿔 친 경우의 다시 숨기기(`didChangeText`)는 그대로다.
- 선: 1pt `separatorColor`, 텍스트 컨테이너 폭 전체(글의 왼쪽 끝 x = 0부터 스크롤바 여백 앞까지), 대시가 있는 줄 조각의 세로 가운데. 번역 창의 단위 사이 선과 같은 모양이다. 여전히 `drawBackground(in:)`에서 그리고, 글·범위·폭·글꼴이 바뀌면 다시 구한다.
- 스크롤바 여백: 번역 창(`ResultTextView.setFrameSize`, c5ab85f)과 같이 원문 창도 텍스트 컨테이너 폭을 `프레임 폭 − 18pt`로 둔다(`widthTracksTextView = false`, `Editor.setFrameSize`). overlay 스크롤바가 마우스를 올려 굵어져도(약 17pt) 글자를 가리지 않고, 숨어 있을 때도 비워 두어 줄바꿈이 바뀌지 않는다. 두 창이 같은 상수 `TextPaneMetrics.scrollerGutter`(`SourceEditor.swift`)를 쓴다. `SourceEditor.swift`는 의존성이 없어 `test-input.sh` 단독 컴파일이 유지되고, 대신 `test.sh`의 결과 창 공용 목록 `RESULT_VIEW_SOURCES`(PR #57에서 생김)에 `SourceEditor.swift`를 더했다. 여백은 overlay 스크롤바일 때만 둔다(`TextPaneMetrics.gutter(in:)`, 독립 리뷰 반영). 마우스를 연결했거나 '스크롤 막대 항상 보기'인 legacy 스크롤바는 clip view 옆에 자기 자리를 따로 차지하므로, 여백을 더하면 오른쪽에 약 33pt 빈 띠가 생기고 가로줄도 스크롤바보다 18pt 앞에서 끊긴다. 두 창 모두 legacy 스크롤바 옆에서는 글과 선이 스크롤바까지 온다. 스크롤바 방식이 바뀌면 clip view 폭이 바뀌어 `setFrameSize`가 다시 정한다.
- 테스트(`SourceEditorTests`, 창 없음, 픽셀): 대시 자리에 글자 잉크가 없고(어둡기 < 0.3, 선만) 선이 그 아래를 지난다. 선이 x = 0과 컨테이너 끝 바로 앞에 있고 여백 안에는 없다(1pt). 선택이 줄에 걸쳐도 숨김 유지. 숨은 대시와 같은 글자로 바꿔 친 입력은 갱신 없이 다시 숨는다. 폭·글꼴 변경 뒤에도 숨김과 선 폭이 맞다. 컨테이너 폭 = 프레임 − 18, 줄 끝이 여백 바로 앞까지 오고 여백 안에는 잉크가 없으며, 스크롤바를 숨기거나 보여도 줄바꿈이 같다. legacy 스크롤바로 바꾸면 여백 없이 clip view 폭 그대로이고 선도 그 끝까지, overlay로 돌아오면 여백이 다시 생긴다(번역 창도 같은 검사). 복사는 테스트 전용 이름의 pasteboard에 `writeSelection`으로만 확인한다(일반 클립보드를 쓰지 않는다).
- 결함 주입(저장소 밖 사본): 회색으로 되돌리기, 여백 빼기, 폭 변경 뒤 선 다시 구하기 빼기, 선을 대시 오른쪽부터, 같은 글 다시 숨기기 빼기는 모두 잡혔다. `widthTracksTextView = true`로 되돌리기는 살아남았다(`setFrameSize`가 매번 폭을 다시 정해 창 없는 경로에서는 결과가 같다). 번역 창과 같게 `false`로 둔다.
- 남은 수동 확인([Mac 통합 확인](mac-integration-checks.md) '명시 경계(U1)'): 실제 창에서 선의 다시 그리기, 한글 조합, 스크롤바 위 마우스 올림.

### 선은 한 덩어리 — 2026-10-14(사용자 피드백)

사용자 피드백(선 위에 커서가 떠 있는 화면): "이 위에 뜨는 것도 어색하다, 원하던 그림이 아니다". 대시를 숨겨도 글자는 남아 있어 커서가 숨은 대시 뒤(선 위)에 섰다. 마크다운 편집기(노션·Typora)의 가로줄처럼 선을 글자가 아닌 한 덩어리로 다룬다. 판정(`sourceBoundaryLines`)과 원문 글은 그대로다.

- `---`를 친 순간: 경계가 될 줄을 다 쳐서(또는 붙여 넣어) 커서가 대시 뒤에 있고 그 뒤로 줄 끝까지 공백뿐이면 줄 끝에서 ↩를 대신 누른다(`Editor.breakAfterTypedBoundary`, `insertText`와 붙여 넣기의 `readSelection(from:type:)` 뒤, 끌어다 놓기는 빼고). 문서 전체를 읽는 경계 판정은 줄이 `---` 모양일 때만 부른다(목록 `- 항목`을 칠 때마다 부르지 않는다, 재검토 반영). 선이 그어지고 커서는 그 아래 새 줄에 있다. 노션처럼 세 번째 대시에서 바로 바꾸므로 `----`·`---x`를 한 글자씩 이어 치면 네 번째 글자부터 다음 줄에 쓰인다(붙여 넣은 `----`·`---x`는 그대로). store 갱신은 다음 SwiftUI 갱신에 오므로, 경계 여부는 편집기에 넘긴 `findBoundaryLines`(`IncrementalTranslationPlanner.boundaryLineRanges(in:)`)로 바로 정한다. store는 구조 단위 안의 줄을 더 빼므로 store가 그리는 줄은 늘 여기에 들지만, 거꾸로 store가 뺀 줄(통째로 보낸 구조 단위 안)에서 친 `---`도 줄은 바뀐다(선은 그려지지 않는다). 펜스 안, 줄 가운데에서 친 대시, 조합 중인 글에는 하지 않는다.
- 커서는 선 줄(숨긴 대시부터 그 줄 끝까지)에 놓이지 않는다(`setSelectedRanges` 재정의). 키보드는 이전 선택과 비교한 방향으로, 아래로(→·↓) 가던 커서는 선 아래 줄 첫머리로, 위로(←·↑, 선택을 ←로 접기) 가던 커서는 선 위 줄 끝으로 간다. 마우스는 누른(끄는·뗀) 자리가 선 가운데보다 위면 위, 아래면 아래다(NSTextView는 누르는 동안 여러 번 선택을 바꾸므로 방향으로 정하면 손을 뗄 때 반대쪽으로 뛴다, 독립 리뷰 반영). 그쪽에 줄이 없으면 반대쪽이다. 연달은 선은 한꺼번에 건넌다. 마지막 줄의 선 아래로 가려 하면(↓·→·선 아래 클릭) 원문 끝에 줄바꿈 하나를 덧붙이고 그 줄에 커서를 둔다(번역에는 영향이 없다). 원문 맨 위의 선 위에는 줄이 없으므로 커서가 갈 수 없다. 밖에서 바뀐 글이나 늦게 인정된 줄에 커서가 있으면 `showBoundaryLines`가 옮기되 갱신 중에는 글을 바꾸지 않는다. 선택은 숨은 대시 하나만 바뀌지 않게 다룬다(재검토 반영): 선 줄 안에만 든 선택(선 위 더블클릭·오른쪽 클릭이 고르는 숨은 대시)은 커서로 보고 위 규칙으로 옮긴다. 끝이 선 줄 가운데에 걸친 선택(끌기, ⇧→)은 선 줄 전체로 넓혀 ⌫가 선을 통째로 지운다. 끌어다 놓을 자리가 선 줄이면 `characterIndexForInsertion(at:)`이 마우스처럼 높이로 선 위 줄 끝이나 아래 줄 첫머리를 돌려주고, 놓는 동안에는 커서를 따로 옮기지 않는다(옮기면 NSTextView가 셈해 둔 자리와 넣은 자리가 어긋나 숨은 대시가 선택됐다).
- 지우기: 선 바로 아래 줄 첫머리의 ⌫(⌥⌫·⌘⌫ 포함)와 바로 위 줄 끝의 ⌦(⌥⌦ 포함)는 선 줄과 그 줄바꿈을 통째로 지운다. 마지막 줄의 선은 앞 줄바꿈과 함께 지운다. 대시를 하나씩 지워 `--`로 만드는 길은 없어졌다(선택해 지우면 된다).
- 그려진 선만 다룬다. 글이 바뀐 뒤 store 갱신 전에는 옛 선을 쓰지 않는다. 지금 글인지는 글자 편집마다 느는 판(`NSTextStorage.didProcessEditingNotification`)으로 안다(커서가 움직일 때마다 글 전체를 비교하면 340KB에서 16ms가 걸렸다, 독립 리뷰). U+000B·U+000C처럼 플래너와 NSString이 줄을 달리 보는 글에서는 줄이 대시로 시작해 공백으로 끝나는 선만 덩어리로 다룬다(아니면 ⌫가 줄 전체를 지울 수 있었다).
- 판정 한 가지 변경: 원문에 내용이 없으면 `---` 줄은 경계가 아니다(`boundaryLineRanges`가 빈 배열). 나눌 것이 없고, 빈 원문에서 친 `---`를 선으로 바꾸면 그 아래에 글을 치는 순간 front matter(`---⏎title:`)가 되어 다시 대시로 돌아온다. 내용이 있는 원문의 맨 위 `---⏎⏎` 경계는 그대로 선이다.
- 테스트(`SourceEditorTests`): 위·아래에서 선 줄의 세 자리로 보낸 커서가 아래 줄 첫머리·위 줄 끝으로 가고, →·←·↓·↑와 선택 접기가 선을 건너며, 연달은 선·맨 위의 선·U+000C 줄·밖에서 바뀐 글을 확인한다. 마지막 줄의 선 아래로 ↓하면 줄바꿈 하나가 붙고, 누르는 중(`stillSelecting`)에는 붙지 않는다. 마우스는 NSTextView 추적 루프 대신 그 콜백(누르는 동안 여러 번, 뗄 때 한 번)을 `trackMouse(from:)` 안에서 불러, 위·아래 절반 × 이전 커서 × 끌기 횟수 × 선 줄의 세 자리에서 쪽이 늘 같고, 마지막 줄의 선 아래 클릭은 뗀 뒤에 줄을 만든다(합성 마우스 이벤트는 손을 뗀 자리를 실제 커서 위치로 읽어 쓰지 않았다). 세 번째 대시, 문단 사이, 붙여 넣기(테스트 전용 pasteboard), 대시 뒤 공백을 붙여 넣은 경우 줄이 바뀌고, 네 번째 대시는 다음 줄에 쓰이며, 빈 원문·펜스·`---x`·첫 대시·`- - -`·조합 중에는 바뀌지 않는다. ⌫·⌥⌫·⌘⌫·⌦·⌥⌦가 선 줄을 통째로 지우고, 다른 자리와 갱신 전의 옛 선에서는 한 글자만 지운다. 선 줄 안의 선택(대시 셋·하나)은 커서가 되어 친 글이 선 아래로 가고, 선에 걸친 선택은 선 줄 전체로 넓어지며 ⇧→⇧→ 뒤 ⌫는 선을 통째로 지운다. 끌어다 놓기는 대신 만든 `NSDraggingInfo`와 테스트 전용 pasteboard로 NSTextView의 놓기 메서드를 차례로 불러, 선의 위·아래 절반에 놓은 글이 선 위·아래 줄에 들어가 그대로 선택되고 줄바꿈이 붙지 않음을 확인한다.
- 남은 수동 확인: 실제 키 입력(한글 입력기 켠 채 `-` 세 번), 마우스로 선의 위·아래 절반 클릭·더블클릭·오른쪽 클릭과 맨 아래 선 밑 클릭, ↑·↓의 가로 위치, 다른 앱에서 끌어다 놓기.

### 하단 막대 — 2026-10-13(사용자 피드백)

같은 피드백의 세 번째 항목("하단이 잡다하다")은 원문·결과 창 밖의 일이라 [창 크기와 배치](window-size-and-layout.md#하단-막대--2026-10-13사용자-피드백)에 적었다. 이 문서와 닿는 점만: 결과 칸 아래 상태 행이 없어져 '↓ 새 번역 보기'·'다시 시도'는 창 하단 막대 오른쪽에 있고, '전체 다시 번역'(블록마다)은 결과 글의 오른쪽 클릭 메뉴 맨 위에만 있다. 예전 SwiftUI `.contextMenu`는 결과 글 위에서 열리지 않아(그 아래 `NSTextView`가 자기 메뉴로 답한다) `ResultTextView.menu(for:)`로 옮겼다. 결과 선과 원문 가로줄은 바뀌지 않았다.

### 최신 main과 합치기 — 2026-10-14

처음 구현은 `dd2f0f9` 위였다. 그 뒤 main에 실행 중 결과 검사(#55), 복사한 코드 블록 정리(#56), 코드 표시 S6′(#57–#59), 계획 문서 보완(#60)이 들어왔다. PR을 올리기 전에 main을 합쳤고, 겹친 곳은 이렇게 맞췄다.

- 요청 시작: main은 요청을 `launch(_:token:cacheKey:)`로 보내고, 원문 반복 재요청도 같은 토큰으로 이 함수를 다시 부른다. U1의 토큰(덮는 원문 = 앞 문서 + 구분 + 이 단위, I5)을 그 호출에 넘긴다. 재요청은 같은 단위를 다시 보내므로 토큰도 같다.
- 캐시: 단위가 끝날 때마다 `bypassCache`를 끄지 않는다(U1, 원문 전체를 게시할 때만 끔). 반복이 남은 문서는 저장하지 않는다(#55)는 그대로 둔다.
- 결과 창: 코드 상자는 이제 스타일마다 머리줄·아래 여백이 다르다(`CodeBoxLayout.geometry.box`). 단위 선은 그 상자의 실제 위·아래를 기준으로 그린다. U1이 따로 계산하던 상자(`CodeBlockStyle.top`·`bottom`)는 지웠다. 테스트도 고정값(10·26pt) 대신 그린 상자를 읽는다.
- 하단 막대: #55가 예전 상태 행에 더한 원문 반복 표시를 막대로 옮겼다. 다시 요청 중 문구, 주황 경고 표시와 '원문이 그대로 남아 있을 수 있습니다', 그 결과에서만 막대에 보이는 '전체 다시 번역'이다(우선순위는 [창 크기와 배치](window-size-and-layout.md#하단-막대--2026-10-13사용자-피드백)). `TranslationFooterStateTests.unresolvedEchoWarns`가 확인한다.
- `test.sh`: `SourceEditor.swift`를 결과 창 공용 목록에 넣었다. 저장소를 컴파일하는 새 묶음(SourceEditor, TranslationFooterState)에는 #55의 검사 파일을 더했다.

이슈 #63의 완료 기준 가운데 이 PR이 다루는 것은 경계 뒤 블록만 요청(1)과 결과에 `---`가 섞이지 않음(3)이다. '전체 다시 번역'과 방향·제공자 재번역에서 구조 복사의 링크·칩을 지키는 것(2)은 첫 블록이 복사본과 같을 때만 된다. 경계가 없는 구조 복사를 다시 번역하거나 복사본을 고친 뒤에는 여전히 링크·칩이 사라진다. 이 남은 부분은 #64로 나눴다.
