# PR #66 독립 리뷰 반영

[독립 리뷰](https://github.com/Geuni620/deepK/pull/66#pullrequestreview-5557265584)는 별도 detached checkout `142e5e4`에서 Codex 리뷰어 3명이 기능 결합·가져오기/내보내기·화면/테스트를 나눠 수행했다. 별도 Codex 검증자 3명이 반박 검증했고 메인 세션도 직접 재현했다. 확정 5개 모두 P2이며 `5e9ffd3`에서 수정했다. 보류·기각·중복 통합은 0개다. Claude는 사용하지 않았다.

| 지적 | 수정 | 회귀·변형 근거 |
| --- | --- | --- |
| 같은 문자열 재입력 후 내어쓰기 소실 | 문단 속성을 지우는 편집·조합 확정에서 캐시를 무효화하고 이전 목록은 유지 | insertText·이름 있는 pasteboard·IME: 수정 전 실패 → 후 통과 → 무효화 OFF 재실패 |
| 인라인 코드의 `- `·`1. `를 목록으로 오인 | 코드 span과 목록 마커가 겹칠 때만 제외 | HTML·RTF 전후 검사, 정상 `- ` 목록 본문의 코드 대조군, marker mask OFF 재실패 |
| 새로 입력한 백틱 코드의 서식·삽입 기호 소실 | `InlineOptions.literalCode`로 직접 입력한 값의 구분 기호 유지 | 실제 importer·고정/자동 방향·제공자/전체 재번역·캐시·undo·부분 선택, 수정 되돌림 재실패 |
| 코드 블록 끝 같은 줄 확장이 닫는 펜스를 오염 | 실제 코드 내용 확장은 평문으로 처리하고 SP/TAB·개행 뒤 문단은 구조 유지 | 요청 payload·echo 대조·복사/삽입·재시도·캐시, 수정 되돌림 재실패 |
| 매 줄 코드 제외 범위 전체 탐색 | 범위 정렬·병합 후 순차 탐색 | 8,000 제외 범위·겹침/역순/범위 밖 검사, 동일 입력의 main/리뷰본/최종본 CPU 비교 |

- 제품 최소 재현: [수정 전](before-results.json), [수정 후](after-results.json), [수정 되돌림](reverted-results.json).
- [최종 Store 그룹 결과](store-results.json), [검사한 파일 해시](tested-files.json), [화면·RTF·helper 검증](ui-verification-summary.json).
- 추가한 CRLF 기대값 검사에서 한 차례 실패했다. Swift의 `String.contains("\n")`가 CRLF를 하나의 문자로 다뤄 기대값을 잘못 계산한 테스트 문제였으며, Unicode scalar 기준으로 교정했다. [첫 실패](failed-store-results.json)를 보존했고 제품 변경 없이 재실행한 Store 그룹이 통과했다.
- 캡처와 직접 입력에 같은 코드 값이 있으면 출처를 출력 순서로 추측하지 않고 해당 값의 백틱을 모두 보존한다. 이때 캡처된 같은 값에도 백틱이 남을 수 있다.

검사는 고정 응답·가짜 제공자·이름 있는 pasteboard·창 없는 AppKit을 사용했다. 실제 모델·전체 앱·실제 Chrome 복사·외부 앱 삽입을 확인한 결과가 아니다. 파서 측정도 GUI 전체 지연과 구분한다.

[최종 파서 수치](parser-final-metrics.json), [동일 하네스](parser-benchmark.swift), [독립 리뷰의 원래 측정](parser-review-original-metrics.json)은 서로 구분해 보존한다. 원래 측정과 최종 측정의 호스트 부하가 달라 서로 다른 실행의 절대값을 직접 비교하지 않는다.

## 검색 작업량의 되돌림 검사

시간 임계값 대신 정규화 뒤 범위 검색 작업량을 검사했다. 계측은 임시 소스 사본에만 넣었으며 제품 코드에는 카운터가 없다. 8,000 제외 범위·24,000줄에서 허용 작업량을 320,000으로 두면 최종 sweep은 **32,000회·통과(0)**, 이전 전체 선형 검색을 복원한 변형은 **160,004,000회·실패(1)**다. 두 버전 모두 목록 항목은 0개로 같아 검색 비용만 구분한다.

[결과·제품 소스 SHA](parser-work-bound/results.json), [검사 드라이버](parser-work-bound/WorkBound.swift), [계측 패치](parser-work-bound/instrumentation.diff), [이전 탐색 복원 패치](parser-work-bound/restored-scan.diff)를 보존했다. `5e9ffd3`의 `TranslationLists.swift`를 새 사본으로 가져와 zero-context 계측 패치를 적용한 후 `swiftc -O -swift-version 6 -warnings-as-errors -parse-as-library TranslationLists.swift WorkBound.swift -o WorkBound`로 실행한다. 복원 패치 적용 뒤 다시 컴파일하면 같은 작업량 검사가 실패한다. 모델·GUI·일반 클립보드는 사용하지 않았다.

## 첫 리뷰 반영 후 작업 브랜치 전체 검사

제품·테스트 코드 `5e9ffd3`과 동일한 상태에서 `scripts/test.sh` 전체 **25개 프로그램·29개 파일**이 종료0으로 통과했다(컴파일 포함940.71초). 포맷 엄격 검사는36 PASS·0 XFAIL, 빌드·서명 확인도 통과했다(43.15초). [기계 판독 기록](branch-verification.json)을 남긴다. 최신 main과 합친 상태의 검사·빌드는 별도 머지 조건이다.

컴파일과 테스트가 합쳐진 로그에서 디코딩 진단1줄이 관측됐다. 해당 Footer 제품/테스트는 기준 main과 동일하고 JSON 파손 검사를 포함하지 않는다. 현재 바이너리3회와 이전 보관 바이너리3회는 모두 종료0·stderr빈값이었다(이전 바이너리의 정확한 리비전은 미확인). 로컬 매크로 컴파일러 라이브러리의 문자열과 같은 Swift6.2.1의 [공식 이슈#86833](https://github.com/swiftlang/swift/issues/86833)를 근거로 기존 컴파일러 매크로 진단과 일치한다고 분류했다. 원래 발생 프로세스는 미확정이며 제품 런타임 실패는 재현되지 않았다. [진단JSON](compiler-log-classification.json)과 최초 통합 로그를 보존했고 환경은 변경하지 않았다.

## 머지 전 첫 실패와 새 번역 힌트 검사 대기 수정

최신 main `f1203d4`와 head `e4e00dd`를 합친 첫 전체 검사에서 14번째 프로그램의 기존 `a newly attached proxy receives the current hint` 검사가 실패했다(종료133, 컴파일 포함1285.72초). 앞선13개 프로그램과 포맷36개는 통과했지만 이후11개는 실행하지 못했으므로 전체 통과로 세지 않는다. 같은 병합 상태의 앱 빌드는 통과했다(325.76초). [첫 실패 기록](premerge-first-attempt.json)과 로컬 최초 로그를 보존한다. 초기에는 cold 앱 빌드와 검사가 겹쳤고 호스트 메모리 압박이 관측됐다. 프로세스 중단·강제 종료는 하지 않았으며, 다음 전체 검사와 빌드는 순차 실행한다.

제품의 MainActor 비동기 전달은 그대로 두고 테스트만 수정했다. 고정50ms 대기 대신 action 전에 Observation을 등록해 실제 변경 알림과 정확한 값을 모두 기다린다(최대5초, 수신 즉시 종료). 기본 `.hidden`으로 잘못 통과하지 않도록 `.arrived`를 실제 수신한 같은 proxy에서 `.hidden` 전환도 검사한다. 이는 무기한 스케줄러 정체에서도 무실패를 보장하는 변경은 아니다.

수정한 **결과 뷰 테스트 프로그램 하나**를 같은 바이너리로10회 실행해 모두 종료0이었고, 메인 세션의 직접 실행도 종료0이었다(18.35초). 이11회는 25개 프로그램의 `scripts/test.sh` 전체 실행 횟수와 별도다. 임시 생산 코드 사본에서 attach 전달을 제거하면 기존 `.arrived` 단언, `.hidden`을 잘못 전달하면 새 `.hidden` 단언이 각각 종료133으로 실패했다. 두 변형 모두 Swift6·경고를 오류로 처리하는 컴파일은 성공했다.

별도 Codex 검증자는 소스와 원본 결과·SHA를 직접 확인했다. 값·수신 단언의 약화나 기본값 거짓 통과를 찾지 못했고 차단 지적은0개다. 중복 컴파일·실행은 하지 않았다. [검사 범위·반복·두 변형·파일 해시](proxy-hint-wait-verification.json)를 보존한다. 실제 제공자·일반 클립보드·사용자 앱 실행/종료는0회이며, 제품 파일은 `5e9ffd3`과 동일해 기존 성능 비교를 다시 측정하지 않았다.

변형은 공유 checkout을 바꾸지 않고 최종 소스의 임시 사본에서 재현한다. [main 호출 축소 패치](proxy-hint-mutations/focus-test-main.diff)와 [전달 제거](proxy-hint-mutations/delivery-disabled.diff) 또는 [잘못된 hidden 전달](proxy-hint-mutations/hidden-delivery-wrong.diff)을 각각 `git apply --unidiff-zero`로 적용한 뒤, `scripts/test.sh`의 `RESULT_VIEW_SOURCES`·`ResultStyleFixtures.swift`·`TranslationResultTextViewTests.swift`를 사용하는 결과 뷰 컴파일 명령과 해당 바이너리만 실행한다. 각 변형은 독립 사본에 적용하며 원래 실패 메시지를 확인한다. 최종 head의 최신 base 통합 전체 검사·빌드 결과는 [PR #66](https://github.com/Geuni620/deepK/pull/66)에 별도로 기록한다.

## 통합 재시도에서 발견한 Codex 취소 정리 누락

head `deaab3f`의 통합 재시도는 기존 Codex 취소 검사에서 종료133으로 실패했다(438.09초, 앞선4개 프로그램 통과·이후20개 미실행·앱 빌드 미실행). [첫 재시도 기록](premerge-retry1.json)을 보존한다. 소스 반박 검증과 응답 gate 재현에서 시작 응답 전 취소의 제품 정리 누락을 확인했다. 테스트 취소를 늦추는 대신 늦은 응답과 응답 인계 중의 turn ID를 회수해 중단하도록 수정했다.

[취소 수정 근거](codex-cancellation/README.md)에는 수정 전/수정 OFF 실패·후 통과, 두 경계 각3회, 최종 fixture 강화, CodexTransport 전체 프로그램 담당자·메인 세션 각1회 통과, 별도의 fake IPC 순차 관측을 남겼다. 초기 실패 로그와 측정은 수정하지 않았다. 이 후속 변경은 Codex client·그 테스트와 fixture이며, 앞서 측정한 importer·parser·네이티브 화면 파일은 그대로다. 모델·전체 앱 성능을 추가 측정한 결과가 아니다. 실제 최신 head의25개 전체 프로그램·빌드 통과 여부는 PR의 마지막 통합 기록으로 확인한다.
