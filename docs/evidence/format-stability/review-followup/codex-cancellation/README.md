# Codex 시작 응답 취소의 중단 누락

첫 통합 재시도(`deaab3f` + main `f1203d4`)는 기존 `cancellation interrupt` 검사에서 실패했다([기록](../premerge-retry1.json)). 서버가 turn을 만들었다는 marker는 클라이언트가 시작 응답을 처리했다는 ACK가 아니다. 기존 코드는 시작 응답 대기 중 취소하면 호출자에게 CancellationError를 돌려주지만, 나중에 도착한 turn ID를 회수해 중단하지 않았다. 원래 통합 실패의 정확한 스케줄은 기록되지 않았으므로, 같은 누락 경계를 결정적으로 재현한 결과와 구분한다.

제품 수정은 `turn/start` 응답 대기와 응답 수신 후 호출자 인계를 구분한다. 취소한 호출의 늦은 응답에서 turn ID를 회수하고 retire·interrupt한다. 응답이 continuation을 깨웠어도 요청이 반환하기 전까지 ID를 보관한다. 기존 thread/start 정리와 연결 generation 확인은 유지한다. 정상 응답은 반환 직전에 정리 책임을 호출자에게 넘긴다.

영구 회귀는 서버가 live turn을 만든 뒤 응답을 gate하고, 취소한 호출자가 먼저 반환한 것을 확인한 뒤 응답을 release한다. 그 뒤 interrupt를 정확히 한 번 관측한다. 기존 활성 turn 검사는 partial callback으로 클라이언트의 ID 소유를 확인한 뒤 취소한다. 별도 검증자가 발견한 fixture의 자동 gate 해제·응답 후 로그 기록도 수정했다. gate 만료는 응답 없이 실패하며 응답 기록은 전송보다 먼저 남긴다. 초기 로그는 덮어쓰지 않고 최종 fixture로 다시 검사했다.

수정 전/수정 OFF는 `late turn/start cancellation interrupt` 단언에서 종료133, 수정 후 집중 검사는 종료0이었다. 응답 전 취소·활성 turn 취소를 각각3회 반복하고 기존 늦은 스트림 차단·thread/start 정리도 통과했다. 응답 인계 순간 취소는 **임시 계측 사본에만** 주입했다. 제품에는 테스트 후크가 없다. 두 경계의 최종 관측은 각각 수정 전 interrupt0/3 → 후3/3이며, 모든 호출자는 CancellationError·unsubscribe1회를 보였다. CodexTransport와 ExecutableResolver 전체 프로그램은 담당자1회·메인 세션 직접1회 모두 통과했다(메인 실행43.23초). 이는25개 프로그램 전체 스크립트 실행과 별도다.

[검증·관측값·제품/fixture SHA](verification.json), [정확한 컴파일·실행 인수](commands.json), [계측 소스의 해시 시점과 재현 사본 차이](reproduction-harness.json)를 남긴다. 별도 Codex 반박 검증자는 소스·원본 로그·SHA·12개 경계 표본을 직접 확인했고, fixture 강화 후 차단 지적0개였다. 중복 컴파일·실행은 하지 않았다.

단독 순차 관측은 같은 최종 fixture·진단 사본에서 before3회 뒤 after3회를 실행했다. marker polling은 명목2ms이며 스케줄러 지연을 포함한다.

| 관측 | 수정 전3개 | 수정 후3개 |
| --- | --- | --- |
| 취소 호출자 반환 ms | 7.587 / 8.700 / 0.124 | 0.155 / 0.226 / 0.250 |
| 늦은 interrupt | 0/3; 약4.09–4.12초 관측 창에서 미관측 | 3/3 |
| 응답 release → interrupt 관측 ms | 미관측; 완료 지연으로 쓰지 않음 | 16.416 / 7.418 / 59.424 |

세 표본의 호출자 중앙값 차이를 속도 향상으로 주장하지 않는다. 컴파일과 겹친 경계 검사의 시간은 위 순차 관측과 섞지 않는다. 실제 제공자·전체 앱·모델 첫 응답/완료·메모리는 미측정이며, 실제 모델·일반 클립보드·사용자 앱 실행/종료는0회다.

재현은 최종 fixture가 있는 저장소를 작업 디렉터리로 사용한다. [명령 인수](commands.json)의 `<tmp>`를 새 임시 경로로 바꾼다. 원본 client는 `git show deaab3f:DeepK/Translation/CodexTranslationClient.swift`로, 수정 client는 검증 SHA와 일치하는 최종 파일로 각각 임시 사본에 둔다. 원본 client를 전체 CodexTransport 컴파일의 첫 소스로 바꾸면 새 영구 회귀가 실패한다. 작업 checkout을 되돌리지 않는다.

집중 검사를 재현하려면 임시 저장소 사본에 [before](before-focused-test-main.diff) 또는 [after](after-focused-test-main.diff) 호출 축소 패치를 `git apply --unidiff-zero`로 적용한다. 인계 주입은 각 client 임시 사본에 [before](before-handoff-injection.diff)·[after](after-handoff-injection.diff) 패치를 적용하고 [BoundaryProbe.swift](BoundaryProbe.swift)를 명령 인수대로 컴파일한다. `pending`은 응답 gate, `handoff`는 continuation resume 직전 동기 취소 후크를 사용하며 프로세스마다3개 JSON 관측을 출력한다. 후크에는 대기·추가 비동기 전환이 없다. 이 진단 드라이버는 관측 출력용이며, 실제 통과/실패 단언은 영구 회귀 검사에 있다.

문서용 Probe는 원본의 고정 임시 경로 한 줄만 시스템 임시 폴더로 바꿨고 다시 측정하지 않았다. 원본 파일과 수치는 그대로 보존했다. 계측 사본·Probe 해시는 실행 뒤 보존 파일에서 계산했으며, 실행 당시 기록한 해시로 주장하지 않는다. 최종 최신-base 전체 검사·앱 빌드는 [PR #66](https://github.com/Geuni620/deepK/pull/66)의 별도 머지 조건이다.
