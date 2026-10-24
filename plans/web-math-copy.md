# 웹 수식 복사 정리

상태: 2026-10-09 0단계(Chrome), 1단계 구현, 실제 앱 확인(2절) 완료. Safari는 측정하지 않는다.

## 1. 문제

KaTeX로 수식을 그린 글을 Chrome에서 두 번 복사하면 원문 창에 수식 조각이 한 줄씩 나뉘고 같은 수식이 한 번 더 붙는다. 번역도 이 줄 구조를 따라 깨지고 일부 문단이 빠진다.

관찰 페이지는 https://shud.in/thoughts/metaphors 이다. KaTeX 0.16.25를 서버에서 렌더링한다(react-katex). 헤드리스 Chrome 154와 Chromium 145로 같은 범위를 복사한 text/plain이 원문 창 스크린샷과 보이는 글자 기준으로 일치했다.

| 화면의 수식 | 들어온 text/plain |
| --- | --- |
| `3 m + 2 s` | `seconds. \n3\n \nm\n+\n2\n \ns\n3m+2s isn’t` |
| `period T (a time)` | `period \nT\nT (a time)` |
| `T ∝ √(L/g)` (디스플레이) | `T\n∝\nL\n/\ng\nT∝ \nL/g\n​\n ` |
| `Turn × Into +` (제목) | `Turn \n×\n× Into \n+\n+` |

원인은 다음과 같다.

- KaTeX는 수식마다 숨긴 MathML(`.katex-mathml`)과 화면용 HTML(`.katex-html`, `aria-hidden="true"`)을 함께 둔다. MathML은 `display:none`이 아니라 잘라서 숨긴 것이라 복사에 포함된다.
- Chrome은 MathML 토큰(`mi`, `mo`, `mn`, `mtext`)을 블록으로 배치해 토큰마다 줄을 바꾼다. 이어서 화면용 HTML 글자가 공백 없이 한 번 더 붙는다. `aria-hidden`은 복사에 영향이 없다.
- 빈 줄처럼 보이는 줄에는 U+2009(`\,`), U+200B(KaTeX vlist)나 공백 하나가 있다. 수식 앞 줄은 공백으로 끝난다.
- √는 어디에도 없다. MathML의 `msqrt`는 글자가 없고, 화면용 HTML의 근호는 SVG다.
- TeX 원본(`<annotation encoding="application/x-tex">`)은 `display:none`이라 text/plain과 text/html 모두에서 빠진다. 복사본으로는 TeX를 복원할 수 없다.
- text/html에는 `<math>` 트리(`msqrt`, `mfrac`, `msup` 등)와 `katex-mathml`, `katex-html` 클래스가 남는다. √와 분수 구조는 HTML에서만 복원된다.

다른 렌더러도 Chrome text/plain을 같은 방식으로 측정했다.

| 렌더러 | text/plain | 비고 |
| --- | --- | --- |
| KaTeX 기본(htmlAndMathml) | 토큰 줄 + 붙은 화면 글자 | 이번 문제 |
| KaTeX copy-tex 확장 | `$T$`, `$$T \propto \sqrt{L/g}$$` | 이미 깨끗하다. 문단 구분이 약해진다 |
| 네이티브 MathML | 토큰 줄만, 중복 없음 | HTML의 `alttext`에 TeX가 있다 |
| Wikipedia 이미지 모드 | `{\displaystyle …}` | img alt |
| MathJax 3 CHTML·SVG | 수식이 통째로 사라진다 | assistive MathML도 복사되지 않는다 |
| MathJax 4 CHTML | 읽을 수 있다(`𝑇∝√𝐿/𝑔`, U+2062 포함) | HTML의 `data-latex`에 TeX가 있다 |
| MathJax 4 SVG | 공백만 남는다 | `data-latex` |

번역이 깨지는 것은 깨진 원문의 줄과 문단을 보존하라는 프롬프트 지시를 모델이 따른 결과로 본다. 문단 누락은 원문을 정리한 뒤 벤치마크로 다시 확인한다(미확인).

## 2. 결정

Chrome이 함께 쓰는 `public.html`에서 KaTeX 수식마다 MathML을 읽고, text/plain 안의 그 수식 자리만 한 줄짜리 유니코드 수식으로 바꾼다. 나머지 글자는 text/plain 그대로 둔다.

- 기준은 text/plain이다. 수식이 없는 복사와 맞추지 못한 수식은 지금과 바이트 단위로 같다.
- HTML의 수식 토큰이 text/plain의 연속된 줄과 정확히 같고, 바로 뒤에 같은 글자 묶음의 화면 글자가 올 때만 수식 구간으로 인정한다. 추측으로 지우지 않는다.
- 표기는 유니코드 선형식이다. 예: `3 m + 2 s`, `n × n`, `T ∝ √(L/g)`, `T = 2π√(L/g)`, `a/b`, `x²`, `a_i`. `$…$` 구분자와 펜스는 쓰지 않는다.

| 버린 대안 | 이유 |
| --- | --- |
| text/plain만으로 수리 | 시제품 재현율은 글 형태 96%, 실제 파일 5,644개에서 오탐 0건이었다. 그러나 √·분수·첨자를 구분하지 못해 `T = 2π√(L/g)`를 `T = 2πL/g`로 만든다. 그럴듯한 틀린 수식은 지금의 깨진 글자보다 위험하다. |
| HTML 전체를 직접 텍스트로 변환 | 모든 렌더러를 다루지만 시제품 기준 약 1,200줄을 이식해야 한다. 수식 밖 공백이 Chrome과 다를 수 있다(일반 복사 38건 중 8건). MathJax 3 대응이 필요해질 때 다시 본다. |
| NSAttributedString HTML 가져오기 | 같은 중복을 만들고 √를 잃는다. 첫 호출에 1.2–3.2초가 걸리고 메인 스레드 제약이 있다. |
| TeX 표기 | Chrome의 KaTeX 복사본에는 TeX가 없다. `$…$`는 Codex `$skill` 멘션, 통화 기호와 겹친다. |
| 수식 보호 표시(TranslationLiteralPlan 방식) | 한국어 조사 결합(`n × n개`)에 필요한 의미를 가린다. Claude 경로에는 없고, 복원 오류가 Codex 오류 타입에 묶여 있다. 측정에서 수식 변형이 확인될 때만 검토한다. |

## 3. 구현 순서

### 0단계: 실제 클립보드 확인

- 읽기 전용 덤프 스크립트(`scripts/dump-pasteboard.swift`)로 일반 클립보드의 타입과 크기를 출력하고 `.string`, `public.html`을 파일로 저장한다. 사용자가 실제 Chrome과 Safari에서 shud.in 두 절을 복사한 뒤 실행한다.
- 확인할 것: Chrome `public.html`에 `<math>`와 `katex-mathml`이 있는지, 앞에 `<meta charset='utf-8'>`가 붙는지, Safari가 `public.html`을 쓰는지, Safari text/plain이 같은 모양인지. Safari의 HTML 기록 여부는 Chromium 주석과 WebKit 소스가 다르게 말하므로 실측으로 정한다.
- 커밋할 픽스처는 직접 만든 KaTeX 페이지를 실제 Chrome에서 복사해 얻는다. 외부 글은 수동 확인에만 쓴다. 페이지 생성 스크립트는 실험 위치에서 `scripts/math-copy/`로 옮긴다.

결과(2026-10-09, macOS Chrome 154에서 shud.in 1·2절을 ⌘C로 복사):

- 타입은 `public.html`, `public.utf8-plain-text`, `org.chromium.source-url`, `org.chromium.internal.source-rfh-token` 네 개다.
- `public.html`은 `<meta charset='utf-8'>`로 시작한다. 두 절 모두 `<math>`, `katex-mathml`, `katex-html`이 수식 수(8개)만큼 있고, 2절에는 `<msqrt>`가 2개 있다. TeX 주석(`application/x-tex`)은 없다.
- text/plain과 MathML은 헤드리스 Chrome으로 복사한 결과와 바이트 단위로 같다. 그래서 픽스처는 `scripts/math-copy/`의 헤드리스 Chrome 복사로 만든다.
- Safari는 사용자 결정으로 측정하지 않는다. 1단계는 Chromium 출처 타입이 있는 복사에서만 HTML을 읽으므로, Safari 복사는 지금과 같다.

### 1단계 PR: 두 번 복사 경로의 KaTeX 정리

- `DoubleCopyMonitor.pollSecondCopy`에서 `.string`을 읽는 줄(454) 옆에서 `public.html`도 읽는다. 기존 changeCount 전후 비교(448, 455)가 두 값을 함께 보호한다. 폴링 루프 안에서는 파싱하지 않는다. 512KB를 넘는 HTML은 없는 것으로 본다.
- HTML은 `org.chromium.source-url` 타입이 있는 복사에서만 읽는다. 다른 앱은 HTML을 읽는 순간에 만들 수 있고(지연 제공), 그동안 메인 액터가 멈춘다. 400ms 걸리는 제공자로 측정하니 408ms 동안 멈췄다.
- `captureResult` 판정은 바꾸지 않는다. HTML만 있는 복사는 지금처럼 `clipboardNonText`다.
- HTML은 새 콜백이나 기본값 있는 인자로 넘긴다. `DoubleCopyMonitorPermissionTests`와 `DoubleCopyMonitorSmoke`(3인자 클로저)가 그대로 컴파일되어야 한다. 새 타입을 참조하면 `scripts/test.sh`의 모니터 컴파일 목록에 추가한다.
- 새 파일 `DeepK/Translation/CopiedMathNormalizer.swift`(Foundation만, 상태 없음)에 `static func normalize(plain: String, html: String?) -> (text: String, formulas: Int)`를 둔다.
  1. `html`이 없거나 `katex-mathml`이 없으면 `plain`을 그대로 돌려준다.
  2. `.katex` 안의 `<math>…</math>`를 순서대로 잘라 `XMLDocument`로 파싱한다. `&nbsp;`는 먼저 바꾼다. 파싱에 실패한 수식은 건너뛴다.
  3. 수식마다 토큰 목록(`mi`, `mn`, `mo`, `mtext`의 글자), 선형식, 디스플레이 여부(`display="block"`)를 만든다. `</math>` 바로 뒤 `.katex-html`의 화면 글자 묶음이 토큰과 다른 수식은 버린다. 선택이 숨은 MathML 안에서 시작해 `<math>`가 잘린 수식, SVG로 그린 악센트(`\widehat`, `\overrightarrow`)가 있는 수식이 여기에 해당한다.
  4. text/plain을 앞에서부터 훑는다. 토큰 목록이 연속된 줄과 정확히 같고 바로 뒤 16줄 안의 글자가 같은 글자 묶음이면(공백, U+200B, U+2061–2064 제외) 그 구간과 뒤따르는 U+200B 줄, 공백 한 줄까지 선형식으로 바꾼다. 바꾼 구간 밖에 같은 토큰 목록이 맞는 줄이 남아 HTML의 그 수식 수보다 많으면 어느 자리가 수식인지 모르므로 그 수식은 맞추지 않는다. 코드 블록, 목록, 제목의 `1\n1`, `x\nx-axis` 같은 줄이 해당한다.
  5. 인라인 수식은 앞 줄과 뒤 문장에 이어 붙이고, 앞 줄 끝 공백을 구분자로 쓴다. 디스플레이 수식은 한 줄로 둔다. HTML에서 수식 바로 앞이나 뒤가 `<br>`, 블록 경계, pre·pre-wrap 줄바꿈이면 그쪽은 잇지 않는다. `<kbd>`, `<img>`, `<wbr>` 같은 알려진 인라인 요소는 줄을 나누지 않는 것으로 본다.
  6. 맞지 않는 수식은 원래 글자를 둔다. 바꾼 구간 밖의 바이트는 바꾸지 않는다.
  7. 결과가 비었거나, 바꾼 구간 밖의 3글자 이상 단어가 하나라도 사라졌으면 `plain`을 돌려준다.
- 선형식 규칙:
  - `msqrt` → `√(…)`, `mfrac` → `a/b`(항이 복합이면 괄호), `msup` → 숫자는 위첨자(`x²`) 그 밖은 `^`, `msub` → `_`, `munderover` → `∑_(i=1)^n`, `mtable` → `(a, b; c, d)`.
  - 여러 글자 첨자는 괄호로 묶고(`e^(iπ)`, `x^(ab)`), 첨자 뒤 항은 띄운다(`A^T A`, `log_2 n`, `sin² x`, `u_n v_n`). 첨자가 붙은 닫는 괄호는 앞 항에 붙인다(`(x − x_0)²`, `∥w − w*∥²`).
  - 연산자 앞뒤에 공백을 둔다(`3 m + 2 s`).
  - 수식 안에서만 U+2009, U+00A0을 공백으로 바꾸고, U+200B와 U+2061–2064를 지우고, 수학 이탤릭 글자를 일반 글자로 바꾼다.
- `AppModel`의 복사 콜백 맨 앞에서 정리한 문자열을 만들고, `store.invokeCopiedText`(322)와 `pendingCopy`(323)에 같은 값을 넘긴다. 원문 창에 보이는 글자와 번역에 보내는 글자가 같아야 한다. 정리는 결정적이어야 재복사 중복 판정, 캐시 키, `continues()`가 유지된다.
- 시제품은 수식 16개를 약 41ms에 처리했다. 512KB 상한에서 측정해 50ms를 넘으면 정리를 메인 액터 밖으로 옮기고, 그 사이 새 복사가 오면 결과를 버린다.
  - 측정(Debug): 맞지 않는 수식이 많은 486KB 입력은 23ms, 수식이 모두 맞는 506KB 페이지는 약 42ms다. `-O`에서는 13–23ms다. 50ms 안이라 메인 액터에서 그대로 정리한다.
- 원문, HTML, 출처 URL은 로그와 진단에 남기지 않는다. 남기더라도 정리한 수식 개수만 남기기로 했으나, 실제로는 PR #53의 복사 가져오기 로그가 소요 시간과 링크·인라인 코드 개수만 남기고 수식 개수는 남기지 않는다.
- 테스트: `DeepKTests/CopiedMathNormalizerTests.swift`와 `scripts/test.sh` 블록을 추가한다. 4절의 정리 사례, 비수식 픽스처의 바이트 동일성, 결정성, 빈 결과 금지, 크기 상한을 검사한다.

범위는 0단계와 1단계로 끝낸다. 아래 후속은 실제 사용에서 해당 문제가 확인될 때만 진행한다.

### 후속(문제가 확인될 때만)

| 확인된 문제 | 대응 |
| --- | --- |
| 정리된 원문인데도 모델이 수식을 LaTeX·말로 바꾸거나 문단을 빠뜨린다 | 두 프롬프트(Claude `ClaudeTranslationClient.translationPrompt`, Codex `CodexTranslationClient.translationDeveloperInstructions`)에 수식을 그대로 옮기라는 한 문장을 넣고, `TranslationOutputLint`와 벤치마크 표본으로 확인한다 |
| 모델이 수식을 ```` ```latex ```` 블록으로 감쌌는데 첫 코드 줄에서 채팅식으로 닫히거나(```` ```latex⏎x^2``` ````) 내용 없이 닫혀 `latex`가 코드 줄로 보인다 | `TranslationMarkup.languageTags`에 `latex`, `tex`, `math`, `katex`를 추가한다. 수식 줄이 이어지는 블록은 PR #50(2026-10-09)부터 목록 밖 이름도 뒤에 코드 줄이 오면 언어 태그로 읽어 이미 라벨로 보인다 |
| 원문 창에 ⌘V나 끌어놓기로 넣은 수식이 깨진다 | `SourceEditor.Editor`의 `readSelection(from:type:)`에서 같은 정리를 적용하고 `scripts/test-input.sh` 컴파일 목록을 갱신한다 |
| 네이티브 MathML, Wikipedia, MathJax 4 글이 깨진다 | `alttext`, `{\displaystyle …}`, `data-latex`로 같은 구간 치환을 넓힌다 |
| MathJax 3 글에서 수식 자리가 빈다 | 그 사이트를 실측한 뒤 HTML 전체 변환기 도입을 정한다 |
| HTML이 없는 복사에서 수식이 깨진다 | text/plain 전용 수리를 √·분수·첨자가 없는 무손실 일치에만 적용하는 안을 검토한다 |
| Safari 복사에서 KaTeX 수식이 깨진다 | Safari 클립보드의 HTML 타입과 지연 제공 여부를 실측한 뒤 HTML을 읽는 조건을 넓힌다 |
| 짧은 수식(`$x$`, `$1$`)이 같은 모양의 줄이나 같은 글자의 악센트 수식(`\vec a`) 때문에 정리되지 않는다 | HTML의 수식 위치로 text/plain 자리를 정하는 안을 검토한다 |

증분 번역은 바꾸지 않는다. 2026-10-07 판정 완화 뒤로 `/`, `+`, 짝이 맞는 괄호는 산문으로 본다. 그래서 `n × n`, `3 m + 2 s`, `T ∝ √(L/g)`처럼 `=`가 없는 수식 문단은 증분 대상이 될 수 있고, 앞 문단 문맥 없이 번역되는 [증분 번역](incremental-translation.md) §7 한계가 같이 적용된다. 백틱·중괄호·대괄호·`=`·`;`·`<>`·`|`·`\`·`*`나 `식별자(`(`sin(`, `∑_(`)가 들었거나 목록·인용·헤딩·4칸 들여쓰기·탭이 있는 문서는 `IncrementalTranslationPlanner.isPlainText`에서 빠져 전체 번역된다.

## 4. 검증 사례

| 사례 | 확인할 결과 |
| --- | --- |
| Chrome, shud.in 1절 | `1. Protocols Turn × Into +`, `Say you have n editors and n programming languages. … that’s n × n integrations, … Now it’s n + n.`이 한 문단으로 들어온다 |
| Chrome, shud.in 2절 | `seconds. 3 m + 2 s isn’t`, `period T (a time) … length L, gravity g … mass m.`, 디스플레이 `T ∝ √(L/g)` 한 줄, `T = 2π√(L/g), and the 2π comes` |
| KaTeX 분수·첨자·합·행렬 | `a/b`, `x²`, `a_i`, `∑_(i=1)^n i = (n(n + 1))/2`, `(a, b; c, d)` |
| 수식 없는 Chrome 복사(GitHub README, 뉴스, 표) | 지금과 바이트 동일 |
| HTML 없는 복사(메모, Xcode, 터미널) | 지금과 바이트 동일 |
| copy-tex, MathJax, 네이티브 MathML, Wikipedia | 1단계에서는 지금과 바이트 동일 |
| 수식 중간에서 시작하거나 끝나는 선택 | 맞지 않는 수식은 원래 글자 유지, 다른 글자 손실 없음 |
| 코드 블록, 목록, 제목에 수식 토큰과 같은 짧은 줄 | 그 줄은 그대로 두고, 토큰이 같은 수식은 원래 글자 유지 |
| SVG 악센트 수식(`\widehat`, `\overrightarrow`) | 원래 글자 유지, 뒤 글의 `^`, `~`, `→` 보존 |
| 수식 앞뒤가 `<br>`, pre 줄, 들여 쓴 코드 줄 | 원래 줄바꿈 유지 |
| 수식 뒤에 `<kbd>`, `<img>`, `<wbr>` 같은 인라인 요소 | 줄을 나누지 않고 같은 문장으로 잇는다 |
| HTML을 지연 제공하는 앱의 복사 | HTML을 읽지 않고 지금과 바이트 동일 |
| HTML 512KB 초과 | 지금과 동일 |
| 같은 선택 다시 복사 | 같은 정리 결과, 중복 요청 방지와 캐시 동작 유지 |
| Safari, shud.in | 측정하지 않는다. Chromium 출처 타입이 없어 HTML을 읽지 않으므로 지금과 동일 |
| 정리된 원문 번역(실제 앱) | 수식이 그대로 남고 문단이 빠지지 않는다. 어긋나면 후속 표의 프롬프트 대응으로 넘긴다 |

외부 앱 복사와 실제 클립보드 동작은 단위 테스트나 빌드 성공으로 대체하지 않는다.

## 5. 완료 기준

- [x] 0단계: 실제 Chrome 클립보드 타입과 HTML 내용 기록(Safari는 측정하지 않음)
- [x] 1단계: 테스트 전체 통과, 비수식 픽스처 바이트 동일
- [x] 실제 앱에서 shud.in 2절을 두 번 복사해 원문 창과 번역 확인(2026-10-09 사용자 스크린샷, Codex). 4절의 2절 기대 결과와 일치했고 번역에도 수식이 그대로 남았다. 1절은 따로 확인하지 않았다.

## 6. 결정 기록

- 범위: 2026-10-09 사용자 결정으로 최소 범위(0·1단계)만 진행하고, 그 밖의 문제는 실제로 확인될 때 3절 후속 표에 따라 개선한다.
- 정리 사실 표시: 2026-10-09 사용자 결정으로 두지 않는다. 정리한 수식은 원문 창과 결과 창에 보이는 것으로 충분하다. 피드백 줄과 정리 전 원문으로 다시 번역하는 동작은 만들지 않는다.
- Safari: 2026-10-09 사용자 결정으로 측정하지 않는다. Safari 복사는 HTML을 읽지 않아 지금과 같다. Safari에서 수식이 깨지는 사례가 나오면 3절 후속 표에 따라 실측한다.
- MathJax 3: 2026-10-09 사용자 결정으로 1단계는 KaTeX만 다룬다. MathJax 3은 복사본에 수식 글자가 없어 HTML 전체 변환기가 필요하다. 자주 읽는 사이트에서 수식 자리가 비는 사례가 나오면 그 사이트를 실측한 뒤 정한다.
- HTML 읽기 공유: 2026-10-12 PR #53부터 같은 `public.html`을 링크·인라인 코드 가져오기에도 쓴다. `AppModel`은 `RichSourceImporter.copiedSource(plain:html:)`로 수식을 먼저 정리하고, 정리로 글자가 바뀐 복사에는 링크·인라인 코드를 붙이지 않는다(수식 우선). 결과는 `store.invokeCopiedText` 대신 `store.invokeCopiedSource`로 넘긴다. HTML은 여전히 `DoubleCopyMonitor.readPasteboard`에서 문자열과 같은 changeCount 전후 비교 안에서 읽으므로, 512KB 상한이 링크 가져오기에도 먼저 걸린다(`RichSourceImporter.maxHTMLBytes` 1 MiB보다 앞).
- 민감 복사: 2026-10-12 PR #52부터 비밀번호 관리자 표시(`org.nspasteboard.ConcealedType`·`TransientType`)가 있으면 문자열과 HTML을 읽기 전에 거절한다. 성공 후보는 다음 poll에서 같은 항목에 표시가 없을 때 HTML과 함께 확정한다([두 번 복사 자동 번역](double-copy-translation.md)).

## 7. 참고

- 실험 기록은 임시 위치 `/private/tmp/deepk-math-lab/`에 있었고 재부팅으로 사라졌다. 페이지 생성·복사 재현 스크립트는 `scripts/math-copy/`(`page.mjs`, `capture.mjs`)에 커밋되어 있다.
- 원인 근거: Chromium MathML Core에서 토큰 요소는 `display: block math`다. KaTeX `.katex-mathml`은 `clip`으로만 숨긴다. `semantics` 아래 `annotation`은 `display:none`이다.
- 관련 계획: [두 번 복사 자동 번역](double-copy-translation.md), [증분 번역](incremental-translation.md), [번역 캐시와 디자인](translation-cache-and-design.md).
