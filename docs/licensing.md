# 라이선스 적용 범위 · License scope

## 한국어

별도 고지나 아래 예외가 없는 deepK 자체 소스 코드와 문서는 [MIT License](../LICENSE)를 따릅니다. 상업적 사용·수정·재배포를 허용하며, 소프트웨어의 사본 또는 상당 부분을 배포할 때 저작권·허가 고지를 유지해야 합니다.

아래 항목에 MIT를 일괄 적용하지 않습니다.

| 항목 | 적용 범위와 고지 |
| --- | --- |
| Unicode Unihan 데이터 | `DeepK/Translation/HanjaReadingData.swift`의 생성 데이터는 Unicode License v3를 따릅니다. [제3자 고지](../THIRD-PARTY-NOTICES.txt)와 파일 머리말을 유지합니다. |
| 제품 아이콘·일러스트·시안·스크린샷 | `DeepK/Assets.xcassets/`, `landing/public/`, `docs/screenshots/`, `docs/evidence/` 등에 있는 이미지·영상 및 디자인 자료는 MIT 허가 대상에서 제외합니다. 별도 허가 고지가 없는 자료의 독립적인 재사용·재배포 권한을 이 문서에서 부여하지 않습니다. |
| 외부 문서·모델 응답·복사 표본 | 벤치마크, fixture와 검증 기록에 포함된 제3자 원문·응답은 해당 자료의 권리와 조건을 따릅니다. 자체 테스트 코드와 자료의 권리를 구분합니다. |
| 의존성·외부 도구 | npm 의존성, Apple SDK, Codex CLI, Claude Code 등은 각자의 라이선스와 이용 조건을 따릅니다. deepK의 MIT가 이들에 대한 별도 권리를 부여하지 않습니다. |
| 외부 글꼴 | 랜딩에서 Google Fonts로 요청하는 IBM Plex Sans KR·IBM Plex Mono·Black Han Sans·Noto Serif KR은 각 글꼴의 라이선스를 따릅니다. 직접 번들링·재배포할 때는 해당 글꼴의 고지를 함께 확인해야 합니다. |

MIT는 제품명·상표에 관한 별도 권리나 제공자 구독·API 사용 권한을 부여하지 않습니다. 소스 공개, 앱 배포와 외부 서비스 이용 조건은 각각 확인해야 합니다.

## English

Original deepK source code and documentation are provided under the [MIT License](../LICENSE), except where separately noted or excluded below. Commercial use, modification, and redistribution are permitted. Keep the copyright and permission notice when distributing copies or substantial portions of the software.

The MIT grant does not automatically cover:

| Material | Scope and notices |
| --- | --- |
| Unicode Unihan data | Generated data in `DeepK/Translation/HanjaReadingData.swift` is covered by Unicode License v3. Retain the [third-party notices](../THIRD-PARTY-NOTICES.txt) and the file header. |
| Product icons, illustrations, designs, and screenshots | Images, videos, and design material in locations including `DeepK/Assets.xcassets/`, `landing/public/`, `docs/screenshots/`, and `docs/evidence/` are excluded from the MIT grant. This document grants no standalone reuse or redistribution rights for material without a separate permission notice. |
| External text, model responses, and copied samples | Third-party text and responses in benchmarks, fixtures, and evidence retain their applicable rights and terms, separately from the original test code. |
| Dependencies and external tools | npm dependencies, Apple SDKs, Codex CLI, Claude Code, and other external software retain their own licenses and terms. deepK's MIT license grants no additional rights to them. |
| External fonts | IBM Plex Sans KR, IBM Plex Mono, Black Han Sans, and Noto Serif KR requested through Google Fonts retain their respective licenses. Check the applicable notices before bundling or redistributing them. |

MIT grants no separate rights to product names or trademarks, or access to provider subscriptions or APIs. Source licensing, app distribution, and external-service terms must be considered separately.
