# 업데이트 안내 창 디자인 시안

상태: 2026-11-15 로컬 시안. PR20 head `fddb8df` 기준. 앱 실행·외부 게시 없음. 미리보기 `preview.html`의 버전 값은 모의값이다.

## 문제

- 사용자 캡처: 제목줄, 큰 파란 화살표, 버전 줄, 버튼 아래로 빈 흰 공간이 크게 남는다. 내용은 약 139pt인데 창은 약 555pt다.
- 원인(재현함): `NSHostingView`의 기본 `sizingOptions`가 SwiftUI의 **최소 크기**를 창 제약으로 건다. 루트의 `.frame(maxWidth: .infinity, maxHeight: .infinity)`와 `fixedSize(vertical:)` 텍스트 조합에서 최소 크기는 폭 85pt 기준으로 계산된다. 이 폭에서는 본문이 여러 줄로 접히므로 창의 최소 높이가 그만큼 커진다. 화면에 띄운 NSPanel을 측정한 결과(화면 밖·투명):

| 언어 | 내용 높이 (실제 창) | `contentMinSize` |
|---|---|---|
| ko | 526 | 85 × 526 |
| en | 781 | 85 × 781 |
| ja | 526 | 85 × 526 |
| zh-Hant | 391 | 85 × 391 |

  ko 526 + 제목줄 28 ≈ 캡처 높이. `contentRect` 360×168은 첫 레이아웃 뒤 덮어쓰인다. 화면에 띄우기 전 `fittingSize`는 정상(139)이라 단위 측정만으로는 드러나지 않는다.
- 구성도 투박하다. 제목줄("deepK 업데이트")과 본문 제목("새 버전이 있습니다")이 중복되고, 28pt 화살표 아이콘이 설정 화면의 13/11pt 체계와 어울리지 않는다. 버튼도 양 끝으로 벌어져 있다.

## 추천안

폭 340pt 고정, 높이는 내용에 맞춘다. 키 포커스를 가져가지 않는 패널이라는 원칙과 기존 동작(공식 릴리스 페이지만 열기, 자동 설치 없음)은 그대로 둔다.

```
┌──────────────────────────────────────┐
│ ●                                    │  ← 투명 제목줄: 닫기 버튼만, 제목 텍스트 숨김
│  [앱 아이콘]  새 버전이 있습니다          │  13pt semibold
│   44pt      ( 0.3.0 → 0.3.1 )        │  12pt 숫자 칩, 새 버전은 semibold
│             지금 업데이트하지 않아도 현재   │  11pt secondary
│             버전으로 계속 사용할 수 있습니다.│
│                  [계속 사용] [업데이트 안내 열기] │  regular, 오른쪽 정렬, 주 버튼이 끝
└──────────────────────────────────────┘
```

- **아이콘**: SF Symbol 화살표 대신 `NSApp.applicationIconImage`(기존 앱 아이콘)를 44pt로 쓴다. 출처가 deepK임이 바로 드러나고, macOS 업데이트 안내의 관례와도 맞는다. 새 자산은 없다.
- **현재 → 새 버전**: 숫자만 쓴 칩 `0.3.0 → 0.3.1`(SF Symbol `arrow.right`). 번역할 글자가 없어 네 언어 모두 같은 폭이다. VoiceOver는 기존 문장 `deepK %1$@ 사용 가능 · 현재 %2$@`을 읽는다.
- **색 대신 굵기**: 패널은 보통 키 창이 아니다. 비키 창에서 AppKit은 `borderedProminent`와 accent 색을 회색으로 그린다(사용자 캡처의 회색 주 버튼이 그 결과다). 그래서 강조는 굵기·버튼 순서·문구로 하고, accent 색에 의존하지 않는다.
- **조용한 미루기**: "계속 사용"은 일반 버튼에 `cancelAction`을 붙였다(창이 키일 때 Esc). 제목줄 닫기 버튼도 같은 효과다. 두 경로 모두 `dismiss()`만 호출하며 번역·복사·삽입에 영향이 없다.
- **긴 문구**: 버튼 두 개가 한 줄에 다 들어가지 않으면 `ViewThatFits`로 세로로 쌓는다(주 버튼이 위). 제목과 본문은 줄바꿈되며 높이가 따라 커진다. 잘림도 빈 공간도 없다.
- **제목줄**: `.fullSizeContentView`에 `titlebarAppearsTransparent`, `titleVisibility = .hidden`을 쓴다. `panel.title`은 VoiceOver와 Mission Control용으로 남긴다. 최소화·확대 버튼은 숨긴다. 본문의 위 여백 30pt가 닫기 버튼 자리를 비워 둔다.

### 업데이트 가치(일본어·대만 번체·간체)를 창에 넣지 않은 이유

이 안내 코드는 0.3.0에 처음 들어간다(`docs/app-updates.md`). 따라서 창을 보는 사용자는 **이미** 일본어·대만 번체·간체를 가진 0.3.0 이상이다. 창에 "일본어·대만 번체·간체 지원"을 새 가치처럼 고정해 두면 앞으로의 모든 버전 안내에서 사실이 아닌 문구가 된다. 릴리스 설명을 네트워크로 받는 확장도 범위 밖이다. 그래서:

- 창에는 범용 문구만 둔다. 무엇이 바뀌었는지는 주 버튼이 여는 공식 릴리스 페이지가 맡는다.
- 0.2.0 → 0.3.0의 언어 가치는 앱 밖 채널(README·릴리스 노트·Homebrew 안내, `docs/ja-zh-update-notice-draft.md`)에서 알린다.

## 창 높이를 코드에서 막는 방법

`DeepK/Settings/AppUpdateNotice.swift` 후보:

1. 루트 뷰: `.frame(width: 340)`, `.fixedSize(horizontal: false, vertical: true)`, `.ignoresSafeArea()`. `maxHeight: .infinity`를 없앤다.
2. `hostingView.sizingOptions = [.intrinsicContentSize]`: SwiftUI 최소·최대 크기를 창 제약으로 올리지 않는다.
3. `let size = hostingView.fittingSize` 뒤 `setContentSize(size)`, `contentMinSize = contentMaxSize = size`. 창 위치 계산은 그 다음에 한다.

검토했지만 버린 대안:
- `sizingOptions = []`: `fittingSize`가 0×0을 돌려 창 크기가 0이 된다(측정함).
- 기본 옵션 유지: 이전처럼 최소 크기 문제가 남는다. `fullSizeContentView`에서는 제목줄 안전 영역만큼 +32pt 빈 공간도 생긴다(측정함).

이후 측정(같은 방법): ko/en/ja 161pt, zh-Hant 147pt. 긴 영어 가상 문구는 223pt에서 버튼을 세로로 쌓았다. 모두 `fittingSize`와 실제 표시 높이가 같다. AppKit 렌더는 `renders/`에 있다. 테스트 바이너리라 앱 아이콘 대신 폴더 아이콘이 보이고, 비키 창이라 주 버튼은 회색이다.

## 문구

기존 카탈로그 키만 쓴다. **새 문구가 필요 없다.** 그래서 `Localizable.xcstrings`를 바꾸지 않아도 된다.

선택 제안(채택하면 카탈로그 소유자가 추가):

| 용도 | ko | en | ja | zh-Hant |
|---|---|---|---|---|
| 본문을 짧게 바꿀 때 | 업데이트는 선택 사항입니다. 지금 버전으로 계속 쓸 수 있습니다. | Updating is optional. You can keep using this version. | 更新は任意です。このバージョンを引き続き使えます。 | 更新為選擇性，您可以繼續使用目前版本。 |
| 칩 앞 접근성 보조(선택) | 현재 %1$@, 새 버전 %2$@ | Current %1$@, new %2$@ | 現在 %1$@、新しいバージョン %2$@ | 目前 %1$@，新版本 %2$@ |
| 앱 밖 0.3.0 소개(창에는 쓰지 않음) | 일본어·대만 번체·간체 번역을 지원합니다. | Adds Japanese, Traditional Chinese (Taiwan), and Simplified Chinese translation. | 日本語・繁体字（台湾）・簡体字の翻訳に対応しました。 | 新增日文、繁體中文（台灣）與簡體中文翻譯。 |

## 지키는 원칙

- 키 포커스를 가져가지 않는 패널, `orderFrontRegardless`, 앱 활성화 없음: 기존과 같다.
- 공식 릴리스 페이지(`AppRelease.pageURL`, 로컬에서 만든 주소)만 연다. 자동 다운로드·설치·강제 업데이트는 없다.
- 업데이트를 미뤄도 기능 제한이 없다.
- SF Symbol `arrow.right`와 기존 앱 아이콘만 쓴다. 새 의존성·다운로드는 없다.

## 검증 / 미검증

검증함:
- `swiftc -typecheck -swift-version 6`(대상 macOS 15): 후보 파일이 `AppRelease.swift`, `Localization.swift`와 함께 통과한다.
- 별도 측정 바이너리로 이전·이후 레이아웃을 화면 밖 투명 NSPanel에 띄워 높이를 측정했다(위 표). 이전 문제가 재현됐고 이후 수치가 안정적이다.

미검증:
- 실제 deepK 앱에서 표시(앱을 실행하지 않음), 전체 `xcodebuild`, `scripts/test-app-updates.sh`.
- 실제 앱 아이콘이 들어간 렌더, 키 창 상태, 다크 모드(패널은 기존처럼 `.aqua` 고정).
- `preview.html`의 브라우저 렌더 확인. 웹 글꼴 줄바꿈은 앱과 다를 수 있다.
- 여러 디스플레이에서의 위치 계산(기존 로직 유지).
