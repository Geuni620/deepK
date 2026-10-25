# deepK 랜딩페이지

deepK 앱과 같은 저장소에서 랜딩페이지를 관리하는 영역이다. 현재는 선택된 18개 디자인·반응형·체험 예시를 비교하는 Astro 미리보기가 구현되어 있다. 실제 번역 API와 운영 배포는 연결하지 않았다.

## 디렉터리와 책임

```text
landing/
|-- README.md                    # 현재 구조와 결정 상태
|-- src/
|   |-- pages/                   # 비교 목록과 예시별 정적 경로
|   |-- data/                    # 예시 목록·디자인 구성·번역 표본
|   |-- components/              # 공통 UI·히어로·섹션·체험·비교 화면
|   |-- scripts/                 # 후보 선택과 예시 체험 상태
|   `-- styles/                  # 색상·글꼴과 공통 스타일
|-- public/                      # 기존 아이콘과 원본 시안 썸네일
|-- tests/                       # 예시 누락·선택 복원·예시 번역 검증
|-- astro.config.mjs             # Astro 정적 빌드
|-- wrangler.jsonc               # Cloudflare Workers 정적 자산 설정
`-- plans/
    |-- experimentation-and-deployment.md
    |                            # A/B 테스트·배포 운영 검토안
    |-- implementation.md        # 이전 구현 검토 초안
    `-- translation-provider.md  # 이전 제공자·비용 검토 초안
```

- 웹 소스, 정적 자산, 테스트, 설정, 의존성과 lockfile은 모두 `landing/` 아래에서 관리한다.
- Mac 앱의 소스, Xcode 프로젝트, 테스트와 실행 스크립트는 현재 위치에서 관리한다.
- 루트 `docs/`와 `plans/`는 기존 앱 문서·계획의 위치를 유지한다. 랜딩에만 해당하는 계획은 `landing/plans/`에 둔다.
- 저장소 전체의 안내와 문서 진입점은 [루트 README](../README.md)에서 관리한다.

## 현재 확정한 구조와 방향

- deepK 앱과 랜딩페이지를 하나의 Git 저장소에서 관리한다.
- 기존 Mac 앱의 디렉터리와 빌드 경로를 유지하고 `landing/`을 추가한다.
- 웹 의존성과 빌드 설정은 `landing/`에서 관리한다. 현재 루트에 JavaScript 패키지나 워크스페이스 설정을 추가하지 않는다.
- 사용자가 확인한 기존 pen.dev 시안을 디자인 기준으로 사용한다.
- 배포 대상은 Cloudflare Workers로 유지한다. 계정·도메인 연결과 운영 배포는 아직 실행하지 않았다.
- 제작 후 A/B 테스트와 배포 운영을 고려해 구현한다. 도구·지표·계정·비용은 아래 검토안에서 별도로 정한다.

## 현재 운영 검토

[A/B 테스트와 배포 검토안](plans/experimentation-and-deployment.md)에 기준 페이지의 계측, 실험 배정·성과, 미리보기·운영 분리와 롤백을 정리했다. 비교용 페이지 외에 실제 계측·운영 배포는 구현된 상태가 아니다.

측정의 중점은 사용 흐름 체험 완료와 앱 설치·다운로드 행동이다. 설치 파일 공개 전의 관심 행동과 공개 후 다운로드를 구분해 관측한다.

## 실행과 검증

Node.js 22.23.4 이상과 `package.json`에 고정한 pnpm 12.15.0을 사용한다. 이 폴더에서 실행한다.

```sh
pnpm install
pnpm dev
```

로컬 주소는 `http://127.0.0.1:4321/`이다. 전역 pnpm 버전이 다르면 `npm exec --yes --package=pnpm@12.15.0 -- pnpm install`처럼 프로젝트 버전을 명시할 수 있다.

```sh
pnpm check
pnpm test
pnpm format:check
pnpm build
```

카드에서 구현 화면과 원본을 비교하고 후보를 저장할 수 있다. 후보에는 예시 식별자만 사용하며 현재 브라우저에 저장한다. 데스크톱·태블릿·모바일은 같은 기준 컴포넌트를 각 너비에서 표시한다.

체험은 준비된 표본만 번역 결과를 제공한다. 직접 입력한 새 문장은 실제 API 연결 전까지 번역하지 않으며, 원문·결과를 분석 도구나 서버로 보내지 않는다.

### 브라우저 회귀 검사

정적 빌드의 후보 저장·미리보기·표본 번역·설치 안내·FAQ를 실제 Chromium에서 확인할 수 있다. 복사 성공·실패는 브라우저 안의 모의 클립보드로 검사한다. 아래 명령은 이 폴더에서 실행하며, Playwright 브라우저 설치가 필요하면 CLI의 `install-browser`를 먼저 실행한다.

```sh
pnpm build
pnpm preview --port 4433
npm exec --yes --package=@playwright/cli@0.1.22 -- playwright-cli --session deepk-landing open http://127.0.0.1:4433/
npm exec --yes --package=@playwright/cli@0.1.22 -- playwright-cli --session deepk-landing run-code --filename tests/browser-smoke.mjs
npm exec --yes --package=@playwright/cli@0.1.22 -- playwright-cli --session deepk-landing run-code --filename tests/browser-layout.mjs
npm exec --yes --package=@playwright/cli@0.1.22 -- playwright-cli --session deepk-landing close
pnpm exec astro preview stop
```

첫 검사는 8개 사용자 흐름, 두 번째는 목록과 예시 18개를 1440·768·390px에서 확인한다. 이 검사는 Safari·실제 번역 API·Cloudflare 운영 환경 검증과 구분한다.

## 다음 단계에서 정할 내용

비교한 디자인을 고른 뒤 운영용 콘텐츠·체험 범위, API·모델·비용과 배포 계정·도메인을 정한다. Cloudflare Workers용 설정은 준비했으며 실제 공개 배포는 아직 실행하지 않았다.

## 이전 검토 자료

별도 랜딩 저장소에서 작성했던 두 문서를 참고용으로 가져왔다. 원본 파일은 별도 저장소에 보존했다. 사본에는 참고 초안 표시와 경로·줄바꿈 표기 정리만 적용했다.

- [이전 구현 계획](plans/implementation.md)
- [이전 번역 제공자·비용 계획](plans/translation-provider.md)

이전 문서에 적힌 확정 사항, 구현 범위, 모델, 비용과 완료 기준은 당시의 검토 기록이다. 현재 구현 결정이나 비용 승인을 뜻하지 않는다. 현재 결정 상태는 이 README를 기준으로 확인한다.
