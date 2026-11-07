# deepK 랜딩페이지

deepK 앱과 같은 저장소에서 랜딩페이지를 관리하는 영역이다. 선택한 Playful Bear 디자인을 메인 페이지에 적용하고, 공개한 0.2.0 앱의 Homebrew 설치와 ZIP 다운로드를 연결한다. 운영 주소는 [deepk.geuni.me](https://deepk.geuni.me)이며 Astro 정적 빌드를 별도 Vercel 프로젝트로 배포한다. 기존 18개 디자인·반응형·체험 예시는 `/designs/`에 보존했다. 이전 Cloudflare `deepk-landing` Worker는 2026-11-07에 삭제했다. 웹 번역 API는 없으며, 방문자가 허용한 경우에만 Google Analytics 4로 웹사이트 방문과 설치 관심 행동을 측정한다. 앱 설치 파일은 이 저장소의 GitHub Releases와 `Geuni620/homebrew-tap`에서 배포한다.

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
|-- vercel.json                  # 공식 도메인의 Vercel 정적 배포 설정
|-- wrangler.jsonc               # 저장소에 남은 구 Cloudflare 배포 설정
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
- 공식 도메인의 배포 대상은 별도 Vercel 프로젝트다. Git 연동 시 Root Directory를 `landing`으로 지정하며, CLI로 직접 배포할 때는 `landing/`에서 해당 프로젝트에 연결한다. 기존 `geuni.me` 블로그 프로젝트의 설정은 변경하지 않는다.
- 가비아의 기존 DNS 관리를 유지하고 `deepk` CNAME을 Vercel 프로젝트에서 안내한 값으로 연결한다. 다른 프로젝트의 CNAME 값을 재사용하지 않는다.
- 현재 운영은 Vercel CLI로 배포한다. GitHub App의 저장소 접근 범위를 변경하거나 Git 자동 배포를 연결하지 않았다.
- `wrangler.jsonc`와 `package.json`의 `deploy` 스크립트는 저장소에 남은 구 Cloudflare 배포 경로다. 현재 배포 명령은 `landing/`에서 실행하는 `vercel --prod`이며, 구 Worker를 다시 만들 목적으로 이전 스크립트를 실행하지 않는다.
- 제작 후 A/B 테스트와 배포 운영을 고려해 구현한다. 도구·지표·계정·비용은 아래 검토안에서 별도로 정한다.

## 현재 운영 검토

[A/B 테스트와 배포 검토안](plans/experimentation-and-deployment.md)은 이전 사전 검토 기록이다. 문서 안의 Cloudflare 배포·토큰·롤백 설명은 현재 운영 절차가 아니며, 현재 배포 기준은 아래 [공식 도메인 배포](#공식-도메인-배포) 절이다. A/B 실험은 연결하지 않았다.

실제 측정 범위·수집 제외 항목·지표를 개선에 활용하는 방법은 [웹사이트 측정 안내](docs/measurement.md)를 따른다. 자동 재생 예시는 체험 완료로 집계하지 않으며, 다운로드 클릭을 실제 설치 수로 표시하지 않는다.

## 현재 페이지

- `/`: Playful Bear 메인. 앱 소개, 사용법, AI 구독 안내, Homebrew·ZIP 설치, FAQ
- `/guide/`: 앱 설치, CLI 구독 로그인, macOS 권한, 업데이트·삭제 안내
- `/privacy/`: 원문 전송, 메모리 캐시, Codex 전역 지침, 페이지의 외부 연결 안내
- `/en/`, `/en/guide/`, `/en/privacy/`: 위 세 페이지의 영어판. 문구는 `src/i18n/`(메인 공통)과 `src/pages/en/`(설치·개인정보 본문)에서 관리한다
- `/designs/`: 기존 18개 시안 비교와 후보 저장
- `/examples/<slug>/`: 기존 시안별 화면과 준비된 번역 예시

릴리스 정보는 `src/data/release.ts`에서 관리한다. 버전을 바꿀 때 실제 공개 ZIP의 URL·SHA-256·설치 조건을 함께 갱신한다. 다운로드 URL은 이 저장소의 GitHub Releases를 가리킨다. Homebrew 설치 정보(`Geuni620/homebrew-tap`의 `Casks/deepk.rb`)의 버전·URL·SHA-256도 함께 갱신한다.

## 실행과 검증

Node.js 24.x(검증 환경: 24.14.1)와 `package.json`에 고정한 pnpm 12.15.0을 사용한다. 이 폴더에서 실행한다.

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

메인의 번역 창은 준비된 예시 문장을 입력·번역하는 애니메이션이다. 실제 번역 API를 호출하지 않으며 `prefers-reduced-motion`에서는 정지 화면을 보여 준다.

체험은 준비된 표본만 번역 결과를 제공한다. 직접 입력한 새 문장은 실제 API 연결 전까지 번역하지 않으며, 원문·결과를 분석 도구나 서버로 보내지 않는다.

## 공식 도메인 배포

현재 운영 프로젝트는 `deepk`이며 `landing/`에서 이 프로젝트에 연결한 뒤 `vercel --prod`를 실행한다. 업로드한 `landing/` 자체가 프로젝트 루트다. 기존 `geuni-me` 블로그 프로젝트에 연결하지 않는다. `.vercel/`의 연결 정보와 내려받은 환경변수는 커밋하지 않는다.

나중에 Git 연동을 추가할 경우에는 Root Directory `landing`, Framework `Astro`, Output Directory `dist`를 지정한다. 현재 CLI 배포에서 쓰는 빈 Root Directory 설정과 구분한다.

프로젝트의 Node.js도 `package.json`과 같은 24.x로 지정한다. `ENABLE_EXPERIMENTAL_COREPACK=1`을 설정해 `packageManager`에 고정한 pnpm 버전을 사용한다.

운영 환경의 `SITE_URL`은 `https://deepk.geuni.me`로 지정한다. 미지정 또는 빈 값이면 같은 주소를 기본값으로 사용한다. 별도 주소로 빌드할 때는 `SITE_URL`로 덮어쓸 수 있다. 메인·설치·개인정보 페이지는 언어별 canonical·hreflang과 절대 OG URL을 생성하며, 비교 시안은 `noindex,nofollow`를 유지한다.

`/robots.txt`와 `/sitemap.xml`은 한·영 공식 6개 페이지만 검색엔진에 안내한다. 공식 페이지에는 WebSite·WebPage JSON-LD를, 메인에는 사실에 근거한 SoftwareApplication 정보를 추가한다. 별점·리뷰·유료 구독을 무시한 무료 가격 표시는 만들지 않는다. 사이트맵 제공만으로 색인이나 순위를 보장하지 않는다.

통계를 활성화하려면 운영 빌드 환경에 공개 측정 ID `PUBLIC_GA_MEASUREMENT_ID=G-…`를 지정한다. 비밀 API 키는 사용하지 않는다. ID가 없으면 통계 UI와 Google Analytics가 활성화되지 않는다. 실제 측정은 HTTPS `deepk.geuni.me`의 공식 6개 경로에만 제한하며, localhost·Vercel 미리보기·`embed`·시안·입력 가능한 체험은 제외한다. GA4 전용 웹 스트림의 향상된 측정은 꺼 두고 [측정 안내](docs/measurement.md)의 설정·검증 절차를 함께 따른다.

도메인을 연결한 뒤 HTTPS, 한영 메인·설치·개인정보 페이지, canonical·언어 전환, 이미지와 0.2.0 다운로드 링크를 확인한다. DNS 설정 화면의 저장 완료와 실제 공개 HTTPS 응답을 구분해 검증한다.

Search Console의 URL 접두어 속성 `https://deepk.geuni.me/`은 공개 HTML 메타태그로 소유권을 확인한다. 운영 빌드에 `PUBLIC_GOOGLE_SITE_VERIFICATION` 값을 지정하며, 이는 비밀키가 아닌 공개 검증 문자열이다. 개인 블로그 속성이나 DNS를 바꾸지 않는다. 확인 후 `/sitemap.xml`을 제출하되 제출 성공과 실제 검색 색인 완료는 구분한다.

Vercel CLI로 공개 환경변수 값을 전달할 때도 끝에 줄바꿈을 붙이지 않는다. 운영 빌드 뒤에는 실제 HTML의 측정 ID와 소유권 메타태그 값, 허용 전후 요청, 실제 생성된 쿠키의 이름·도메인·철회 후 삭제를 확인한다. 로컬에서만 올바른 값으로 빌드한 결과로 운영 설정 검증을 대신하지 않는다.

## 다음 단계에서 정할 내용

실제 웹 번역을 추가하려면 체험 범위·API·모델·비용을 별도로 정한다. 현재 서버나 모델을 호출하는 체험으로 표시하지 않는다.

## 이전 검토 자료

별도 랜딩 저장소에서 작성했던 두 문서를 참고용으로 가져왔다. 원본 파일은 별도 저장소에 보존했다. 사본에는 참고 초안 표시와 경로·줄바꿈 표기 정리만 적용했다.

- [이전 구현 계획](plans/implementation.md)
- [이전 번역 제공자·비용 계획](plans/translation-provider.md)

이전 문서에 적힌 확정 사항, 구현 범위, 모델, 비용과 완료 기준은 당시의 검토 기록이다. 현재 구현 결정이나 비용 승인을 뜻하지 않는다. 현재 결정 상태는 이 README를 기준으로 확인한다.
