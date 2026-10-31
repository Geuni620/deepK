# deepK 랜딩페이지

deepK 앱과 같은 저장소에서 랜딩페이지를 관리하는 영역이다. 선택한 Playful Bear 디자인을 메인 페이지에 적용하고, 0.1.1 앱의 Homebrew 설치와 ZIP 다운로드를 연결한다. 기존 18개 디자인·반응형·체험 예시는 `/designs/`에 보존했다. 실제 웹 번역 API·분석 도구·운영 배포는 연결하지 않았다. 앱 설치 파일은 이 저장소의 GitHub Releases와 `Geuni620/homebrew-tap`에서 배포한다.

## 디렉터리와 책임

```text
landing/
|-- README.md                    # 현재 구조와 결정 상태
|-- src/
|   |-- pages/                   # 메인·설치·개인정보·시안 비교 정적 경로
|   |-- data/                    # 공개 릴리스·디자인 구성·FAQ·번역 표본
|   |-- components/              # 공통 UI·히어로·섹션·체험·비교 화면
|   |-- scripts/                 # 후보 선택과 예시 체험 상태
|   `-- styles/                  # 색상·글꼴과 공통 스타일
|-- public/                      # 기존 아이콘·앱 화면·원본 시안 썸네일
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

측정의 검토 대상은 사용 흐름 체험 완료와 앱 설치·다운로드 행동이다. 현재 구현에는 계측을 추가하지 않았다.

## 현재 페이지

- `/`: Playful Bear 메인. 앱 소개, 사용법, AI 구독 안내, Homebrew·ZIP 설치, FAQ
- `/guide/`: 앱 설치, CLI 구독 로그인, macOS 권한, 업데이트·삭제 안내
- `/privacy/`: 원문 전송, 메모리 캐시, Codex 전역 지침, 페이지의 외부 연결 안내
- `/designs/`: 기존 18개 시안 비교와 후보 저장
- `/examples/<slug>/`: 기존 시안별 화면과 준비된 번역 예시

릴리스 정보는 `src/data/release.ts`에서 관리한다. 버전을 바꿀 때 실제 공개 ZIP의 URL·SHA-256·설치 조건을 함께 갱신한다. 다운로드 URL은 이 저장소의 GitHub Releases를 가리킨다. Homebrew 설치 정보(`Geuni620/homebrew-tap`의 `Casks/deepk.rb`)의 버전·URL·SHA-256도 함께 갱신한다.

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

`/designs/`의 카드에서 구현 화면과 원본을 비교하고 후보를 저장할 수 있다. 후보에는 예시 식별자만 사용하며 현재 브라우저에 저장한다. 데스크톱·태블릿·모바일은 같은 기준 컴포넌트를 각 너비에서 표시한다.

체험은 준비된 표본만 번역 결과를 제공한다. 직접 입력한 새 문장은 실제 API 연결 전까지 번역하지 않으며, 원문·결과를 분석 도구나 서버로 보내지 않는다.

## 다음 단계에서 정할 내용

Cloudflare Workers의 계정·도메인과 운영 배포를 정한다. 운영 도메인이 확정되면 `SITE_URL=https://실제도메인`을 빌드 환경에 설정한다. 메인·설치·개인정보 페이지는 고유 제목·설명·OG 태그를 제공하며, `SITE_URL`이 있을 때 canonical과 절대 OG URL을 생성한다. 비교 시안은 `noindex,nofollow`를 유지한다.

실제 웹 번역을 추가하려면 체험 범위·API·모델·비용을 별도로 정한다. 현재 서버나 모델을 호출하는 체험으로 표시하지 않는다.

## 이전 검토 자료

별도 랜딩 저장소에서 작성했던 두 문서를 참고용으로 가져왔다. 원본 파일은 별도 저장소에 보존했다. 사본에는 참고 초안 표시와 경로·줄바꿈 표기 정리만 적용했다.

- [이전 구현 계획](plans/implementation.md)
- [이전 번역 제공자·비용 계획](plans/translation-provider.md)

이전 문서에 적힌 확정 사항, 구현 범위, 모델, 비용과 완료 기준은 당시의 검토 기록이다. 현재 구현 결정이나 비용 승인을 뜻하지 않는다. 현재 결정 상태는 이 README를 기준으로 확인한다.
