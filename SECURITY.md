# Security policy · 보안 제보

## 비공개 취약점 제보

보안 취약점은 [GitHub 비공개 취약점 제보](https://github.com/Geuni620/deepK/security/advisories/new)로 보내주세요. 로그인한 뒤 Security → Advisories → Report a vulnerability에서도 접근할 수 있습니다. 취약점 세부 내용은 공개 이슈에 올리지 마세요.

다음 내용을 가능한 범위에서 포함해 주세요.

- deepK 버전·빌드 번호 또는 소스 커밋, macOS 버전·CPU
- 관련 제공자(Codex 또는 Claude Code)와 CLI 버전
- 합성 문장·가짜 자격 증명으로 재현하는 최소 절차
- 기대 동작, 실제 동작, 영향을 받는 정보나 기능
- 민감한 내용을 제거한 로그·화면(필요한 경우)

실제 번역 원문, 토큰, 암호, 로그인 파일, 인증서 개인 키는 첨부하지 마세요. 본인 소유이거나 명시적으로 허가받은 환경에서만 재현하고, 다른 사람의 정보나 서비스에 접근하지 마세요.

접수·검토·추가 정보 요청과 수정·공개 시점 조율은 같은 비공개 제보에서 진행합니다. 개인이 관리하는 프로젝트이므로 고정된 응답·수정 기한이나 보상 프로그램을 약속하지 않습니다.

보안 수정은 최신 안정 릴리스와 `main`을 우선 대상으로 합니다. 이전 버전은 최신 버전으로 업데이트한 뒤 문제가 계속되는지 확인해 주세요. 일반 오류·기능 제안은 [GitHub Issues](https://github.com/Geuni620/deepK/issues)를 이용해 주세요. 제보 버튼이 보이지 않으면 GitHub 로그인 상태와 저장소의 Security 탭을 확인하고, 그래도 불가능하면 세부 내용 없이 공개 이슈로 비공개 연락 경로를 요청해 주세요.

## Private vulnerability reports

Report security vulnerabilities through [GitHub private vulnerability reporting](https://github.com/Geuni620/deepK/security/advisories/new), also available under Security → Advisories → Report a vulnerability after signing in. Do not disclose vulnerability details in public issues.

Where possible, include:

- The deepK version and build number or source commit, macOS version, and CPU
- The affected provider (Codex or Claude Code) and CLI version
- Minimal reproduction steps using synthetic text and dummy credentials
- Expected behavior, observed behavior, and the affected information or feature
- Redacted logs or screenshots, if needed

Do not attach real translation text, tokens, passwords, login files, or certificate private keys. Test only in environments you own or are explicitly authorized to use, without accessing other people's data or services.

Acknowledgment, investigation, requests for information, and coordination of fixes and disclosure take place in the private report. This is an individually maintained project with no guaranteed response or fix deadlines and no promised bounty program.

Security fixes prioritize the latest stable release and `main`. If you use an older version, update and check whether the issue persists. Use [GitHub Issues](https://github.com/Geuni620/deepK/issues) for ordinary bugs and feature requests. If the reporting button is missing, check your GitHub sign-in and the repository's Security tab. If private reporting is still unavailable, open a public issue requesting a private contact route without disclosing vulnerability details.
