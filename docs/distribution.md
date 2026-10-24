# deepK 설치 파일 준비

`git pull` 후 직접 사용하는 경우에는 `./scripts/build-and-run.sh`를 실행한다. 이 문서는 소스와 Xcode 없이 설치하는 앱 파일을 준비하는 개발자용 안내다. 앱을 받는 Mac에도 번역용 Codex 또는 Claude Code와 구독 로그인이 필요하다.

## 무료 로컬 패키지

```sh
./scripts/package-release.sh --local
```

기본 후보 버전은 `0.1.0`, CPU는 `arm64`(Apple Silicon)다. `--version 0.1.0 --arch arm64`로 지정할 수 있다. Intel(`x86_64`)·Universal 옵션은 제공하지만 별도 실제 검증 전에는 지원 완료로 안내하지 않는다.

Release 빌드 결과를 `dist/release/<버전>/<CPU>/<모드>/<커밋>/`에 패키징한다. ZIP, SHA-256 체크섬, 빌드 정보를 담은 manifest가 생성되며 기존 결과는 덮어쓰지 않는다. 로컬 패키지는 ad-hoc 임시 서명으로 구분한다. 기존 Debug 앱을 바꾸거나 실행 중인 deepK를 종료하지 않는다. 산출물 경로와 로컬 모드 표시는 스크립트 출력에서 확인한다.

이 파일은 Developer ID 서명·Apple 공증을 거친 배포본이 아니다. ZIP 생성 성공이 다른 Mac의 Gatekeeper 통과를 뜻하지 않는다. 본인 Mac에서 비용 없이 사용하는 기본 경로는 해당 Mac에서 소스를 빌드하는 것이다. 보안 기능을 끄거나 격리 속성을 일괄 삭제하는 방법은 설치 절차에 포함하지 않는다.

## 서명·공증 배포

실행 전에 Apple Developer Program, Developer ID Application 인증서, Keychain의 notarytool 인증 프로필이 준비되어 있어야 한다. 프로필은 Apple의 `notarytool store-credentials` 안내에 따라 생성한다. 암호나 인증서 개인 키를 저장소에 넣거나 채팅에 전달하지 않는다.

```sh
DEEPK_DEVELOPER_ID='Developer ID Application: 인증서 이름 (TEAMID)' \
DEEPK_NOTARY_PROFILE='deepk-notary' \
./scripts/package-release.sh
```

인증서·프로필이 없거나 공증이 거절되면 배포를 중단한다. 개발 인증서나 임시 서명으로 대신 게시하지 않는다. 공증 완료 후 앱에 티켓을 첨부하고 검증한 뒤 최종 ZIP과 체크섬을 생성한다. 배포 모드는 커밋되지 않은 변경이 있는 작업 트리를 거부한다. 실패·대기 시간 초과의 공증 JSON은 `.build/release/notary-results/`에 보존하며 자동 재제출하지 않는다. 스크립트는 GitHub에 자동 게시하지 않는다.

## 사용자의 설치·업데이트

1. 게시된 버전의 지원 macOS·CPU를 확인하고 ZIP과 체크섬을 내려받는다.
2. ZIP을 풀어 `DeepK.app`을 `/Applications`에 설치한다. 업데이트할 때는 기존 deepK를 종료한 뒤 앱을 교체한다.
3. 번역할 제공자의 CLI를 설치하고 해당 Mac에서 구독 로그인한다. deepK 설정에서 제공자를 선택하고 연결을 확인한다. 다른 Mac의 토큰이나 개발 checkout의 CLI 경로를 복사하지 않는다.
4. 입력 모니터링과 손쉬운 사용에 설치한 앱을 허용한다. 서명 방식이 바뀐 개발용 앱에서 이전할 때는 기존 권한 등록을 갱신해야 할 수 있다.
5. 다른 앱에서 문장을 선택해 ⌘C 두 번으로 번역하고, 복사·복귀·명시적 삽입을 확인한다.

## 게시 전 확인

- 공증 Accepted, 서명·티켓·Gatekeeper 검증 결과를 확인한다.
- 버전·커밋·CPU·최소 OS와 체크섬이 실제 파일에 일치해야 한다.
- 새 Mac에서 설치·로그인·권한·단축키·번역·삽입 및 업데이트 후 설정 유지를 검증한다.
- 비공개 Release는 저장소 읽기 권한이 있는 사용자에게만 제공한다. 일반 공개하려면 다운로드 위치를 먼저 확정한다.
- 미검증 CPU, 미공증 패키지, 테스트 파일을 정식 배포본으로 표시하지 않는다.

현재 진행 상태와 남은 결정은 [배포 계획](../plans/macos-distribution.md)에서 관리한다.
