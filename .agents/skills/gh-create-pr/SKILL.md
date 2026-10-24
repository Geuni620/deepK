---
name: gh-create-pr
description: deepK GitHub PR을 맥락 없는 독립 리뷰(에이전트, 허락 시 Codex)로 검토해 PR 코멘트로 남기고, 작업 세션이 지적을 확인·수정·답글한 뒤 머지 전 검증을 거쳐 요청 시 Merge commit으로 머지합니다. deepK에서 "PR 리뷰", "독립 리뷰", "리뷰 코멘트 반영", "리뷰 후 머지", "Codex로 리뷰", /gh-create-pr 요청 시 사용합니다. PR 생성 자체는 저장소의 .agents/skills/create-pr 절차를 따르고, 이 스킬은 만든 PR의 리뷰·반영·머지를 맡습니다. deepK PR의 머지는 이 스킬의 머지 전 검증을 거칩니다.
---

# deepK PR 독립 리뷰 → 반영 → 머지

작업한 세션은 자기 설계 의도와 가정을 공유하므로 같은 맹점을 반복한다. 그래서 리뷰는 **맥락 없는 리뷰어**가 하고,
결과와 조치는 **PR 코멘트에 남긴다**. 세션이 끝나도 근거가 남고, 사용자가 중간에 개입할 수 있다.
PR #52·#53에서 이렇게 진행했다.

```bash
/gh-create-pr 52            # 리뷰 → 반영까지
/gh-create-pr 52 --merge    # 반영 후 머지 전 검증·머지까지
/gh-create-pr 52 --codex    # Codex 리뷰도 함께(이 플래그가 이번 요청의 Codex 허락이다)
```

```
PR ─┬─ 리뷰어(관점별) → 반박 검증 ─────┐
    └─ Codex (codex review, 허락 시) ─┴→ PR에 "🤖 독립 리뷰" 리뷰(인라인 + 요약)
          → 작업 세션: 지적마다 확인 → 수정·테스트 → 커밋·푸시 → 답글(커밋 해시)
          → PR 본문 갱신 + 리뷰 반영 요약 → 머지 전 검증 → 머지(요청 시) → 다른 PR 충돌 확인
```

**범위**
- 사용자가 리뷰만 요청했으면 2단계 뒤에 멈추고 보고한다.
- 수정·커밋·푸시는 반영까지 요청받았을 때만 한다.
- 머지는 `--merge`나 머지 요청이 있을 때만 한다.

**명령 실행 방식**
- 셸 상태(`cd`, 변수, `cd -`)는 다음 명령 호출로 이어지지 않을 수 있다.
- 아래 `<repo-path>`에는 `git rev-parse --show-toplevel` 결과(절대 경로)를 그대로 적고, `git -C <경로>`나 `(cd <경로> && …)`로 실행한다.
- `gh api`의 `{owner}/{repo}`는 gh가 현재 디렉터리의 저장소로 채운다. 저장소 밖에서 실행하면 `GH_REPO=Geuni620/deepK`를 붙인다.
- 임시 worktree는 `<repo-path>/.context/` 아래에 둔다. `.context/`가 Git에서 제외되어 있지 않으면 저장소 밖 임시 경로(`/private/tmp/deepk-…`)를 쓴다.

## 0. 준비

- `gh auth status`로 인증을 확인한다.
- `gh pr view <N> --json state,baseRefName,headRefName,headRefOid,isCrossRepository,url`로 PR 정보를 얻는다. 얻은 값을 아래 `<base>`·`<head-branch>`·`<head-sha>`에 넣는다.
  - base가 main이 아닌 PR(선행 PR 위에 쌓인 PR)도 `origin/<base>`가 그 base를 가리킨다.
- `git -C <repo-path> fetch origin`을 실행한 뒤 `git -C <repo-path> rev-parse origin/<head-branch>`가 `<head-sha>`와 같은지 확인한다.
- PR이 없으면 이 스킬의 범위가 아니다. 사용자가 요청했을 때 저장소의 `.agents/skills/create-pr/SKILL.md`를 직접 읽고 그 절차로 먼저 만든다. 이름이 같은 다른 스킬과 혼동하지 않는다.

## 1. 독립 리뷰

리뷰용 worktree를 먼저 만든다. 리뷰어가 작업 checkout(아직 커밋하지 않은 변경이 있을 수 있다)을 읽지 않게 하기 위해서다.

```bash
git -C <repo-path> worktree add --detach <repo-path>/.context/pr<N>-review <head-sha>
```

리뷰어에게는 **PR 번호와 이 worktree 경로만** 준다.
- 작업자의 설명·결론·의도는 넣지 않는다.
- 관점(lens)은 주제만 정해 준다.
- 리뷰 대상 diff는 `gh pr diff <N>` 또는 `git diff origin/<base>...<head-sha>`다.

**리뷰어 에이전트**: 3–4명이 변경에 맞는 관점을 하나씩 맡는다. 관점마다 별도 검증 에이전트가 지적을 반박해 본다. 여러 에이전트를 병렬로 돌리는 것은 사용자가 허락한 범위에서 한다.

- 관점 예: 기능 결합·통합, 보안 우회, 사용자 체감 회귀, 테스트 실효성(고친 코드를 되돌려도 테스트가 통과하는지 변형으로 확인).
- 리뷰어 규칙
  - 읽기 전용이다. 실험은 `/private/tmp` 사본에서 한다.
  - push, GitHub 코멘트, 브랜치 변경을 하지 않는다.
  - 아래 "deepK 기준"의 금지 명령과 구독 사용량을 쓰는 테스트를 실행하지 않는다.
  - 일반 클립보드에 쓰지 않는다. 클립보드 테스트는 이름 있는 개별 pasteboard를 쓴다.
- 재현 근거(파일:줄, 입력, 실행한 명령과 출력)가 있는 지적만 받는다. 문체 취향과 추측은 빼고, 지적이 없으면 빈 목록을 돌려받는다.

**Codex 리뷰**: 이번 요청에 `--codex`나 "Codex로 리뷰"가 있거나 이번 대화에서 허락받았을 때만 실행한다(구독 사용량을 쓴다). 이전 PR에서 받은 허락은 이어지지 않으므로, 그 밖의 경우에는 실행 전에 묻는다.

```bash
(cd <repo-path>/.context/pr<N>-review && codex review --base origin/<base> < /dev/null > /private/tmp/pr<N>-codex-review.txt 2>&1)
```

- 백그라운드로 실행한다. 10분 넘게 걸릴 수 있다.
- `--base`와 직접 쓴 지시문은 함께 쓸 수 없다. 기본 기준으로 리뷰한다.
- macOS에는 `timeout` 명령이 없다.
- 출력의 MCP 연결 오류 로그는 무시해도 된다.
- 결과는 영어로, P0–P3 등급과 파일:줄이 붙어 나온다.

리뷰가 모두 끝나면 `git -C <repo-path>/.context/pr<N>-review status --short`가 비었는지 확인하고 `git -C <repo-path> worktree remove <repo-path>/.context/pr<N>-review`로 지운다.

## 2. PR에 올리기

payload는 `/private/tmp/pr<N>-review.json`에 쓴다(작업 checkout에 두지 않는다). 그다음 `gh api repos/{owner}/{repo}/pulls/<N>/reviews --method POST --input /private/tmp/pr<N>-review.json`으로 리뷰 하나를 올린다.

**payload 필드**
- `event`: `COMMENT`
- `commit_id`: 리뷰한 `<head-sha>`. 그사이 head가 바뀌었으면 새 diff 기준으로 줄을 다시 맞춘다.
- `body`: `🤖 독립 리뷰 (요약)`으로 시작한다.
  - 리뷰어 구성(Codex 여부, 관점), 올린 지적 수와 분류, 합친 중복을 적는다.
  - 반박 단계에서 기각한 지적과 이유도 적는다.
  - 끝에 `리뷰 대상: <짧은 SHA>`를 적는다.
- `comments`: `{path, line, side: "RIGHT", body}`
  - 줄은 PR diff에 들어 있는 head 쪽 줄이어야 한다. 하나라도 밖에 있으면 리뷰 전체가 422로 실패한다.
  - 올리기 전에 `gh pr diff <N>`의 `@@ … +start,count @@` 범위로 확인하고, 밖에 있으면 가장 가까운 diff 안 줄로 옮긴다.

**코멘트 형식**
- 각 코멘트는 `🤖 독립 리뷰 · <리뷰어> · 심각도 <값>`으로 시작한다.
- 이어서 **제목**, 본문, `<details><summary>근거</summary>…</details>`, `**제안:**`, `**반박 검증:**`을 적는다.
- 같은 문제를 두 리뷰어가 찾았으면 한 코멘트로 합치고 그 사실을 적는다.
- Codex 지적
  - 한국어로 옮기되 심각도는 P 등급을 그대로 쓴다.
  - 근거 안에 영어 원문을 함께 붙인다.
  - 반박 검증 칸에는 "Codex 단독 지적이라 반박 단계를 거치지 않았다. 메인 세션 답글에서 확인한다."라고 적는다.

**올린 뒤**
- 응답의 리뷰 `id`로 `gh api repos/{owner}/{repo}/pulls/<N>/comments --paginate --jq '.[] | select(.pull_request_review_id==<review-id>) | [.id, .path, (.line // .original_line)] | @tsv'`를 실행해 답글 대상 id를 기록한다. 리뷰별 엔드포인트(`reviews/<review-id>/comments`)에는 `line`이 없다.
- diff 줄에 달 수 없었던 지적은 요약 body에 번호로 적고, 답은 3단계의 리뷰 반영 요약에 번호별로 단다.

**개인 정보**
- 올리는 글(리뷰, 답글, 요약, PR 본문)에는 다음을 넣지 않는다: 홈 경로(`/Users/<이름>/…`), 메일 주소, 토큰·키 형태 문자열, 클립보드나 번역 원문 같은 개인 텍스트, Codex·셸 원본 로그.
- 경로는 저장소 기준 상대 경로로 쓰고, 임시 파일은 `<tmp>/…`로 줄인다. 명령 출력은 필요한 줄만 옮긴다.
- 저장소는 공개될 예정이고, PR 코멘트는 이력을 재작성해도 지워지지 않는다([공개 전 보안 점검](../../../plans/public-release-security.md)).
- 본인 PR은 Approve할 수 없으니 코멘트만 남긴다.

## 3. 확인·수정·답글

작업 세션은 지적을 **하나씩 코드나 재현으로 직접 확인**한다. 리뷰어의 결론을 그대로 믿지 않는다.

**어디서 고치나**
- 지금 작업 checkout이 `<head-branch>`이고 깨끗하며 `HEAD`가 `origin/<head-branch>`와 같으면 거기서 고친다.
- 아니면 `git worktree list`로 그 브랜치를 다른 worktree가 들고 있는지 본다.
  - 다른 worktree가 들고 있으면 고치지 않는다. 리뷰 링크와 함께 사용자에게 알리거나 그 세션에 넘긴다.
  - 아무도 들고 있지 않으면 `git -C <repo-path> worktree add --detach <repo-path>/.context/pr<N>-sync <head-sha>`에서 고치고 `git -C <그 경로> push origin HEAD:<head-branch>`로 올린다. 작업 checkout의 브랜치는 바꾸지 않는다.
  - 끝나면 `status`가 깨끗한지 확인하고 worktree를 지운다.

**순서**
1. 고친다. 필요하면 회귀 테스트를 더한다.
2. 변형을 확인한다. 고친 부분을 하나씩 되돌려도 새 테스트가 실패하는지 본다.
   - 수정 커밋 뒤 `/private/tmp` 사본이나 그 커밋으로 만든 임시 detached worktree에서 한다.
   - 작업 checkout에서 `git stash`나 `git checkout -- <파일>`로 되돌리지 않는다. stash는 모든 worktree가 공유하고, 사용자가 스테이징한 변경을 잃을 수 있다.
3. `./scripts/test.sh` 전체, `./scripts/build.sh`, `git diff --check`를 돌린다.
4. 기존 커밋은 고치지 않고 리뷰 반영 커밋을 새로 더해 푸시한다. 주제가 여럿이면 주제별로 나누고, 강제 push는 하지 않는다.
5. 푸시한 뒤 답글을 단다. 본문은 `/private/tmp/pr<N>-reply-<id>.md`에 쓰고 `gh api repos/{owner}/{repo}/pulls/<N>/comments/<id>/replies -F body=@/private/tmp/pr<N>-reply-<id>.md`로 올린다. 본문을 셸 문자열에 직접 넣지 않는다(백틱이 명령으로 실행된다).

**답글 형식**
- 첫 줄은 넷 중 하나다.
  - `**확인됨, 고침** (<커밋>)`
  - `**확인됨, 테스트 추가** (<커밋>)`
  - `**근거 부족**`(무엇을 확인했는지 적는다)
  - `**확인됨, 이번 PR에서는 보류**`(이유를 반드시 적는다)
- 본문은 확인(재현), 조치, 테스트(변형 확인), 남는 한계 순으로 적는다.
- 일부만 고쳤으면 첫 줄은 "고침"으로 두고, 본문의 남는 한계(보류)에 이유를 적는다.
- 큰 지적을 보류하려면 머지 전에 사용자에게 묻는다.

**마무리**
1. `gh pr edit <N> --body-file /private/tmp/pr<N>-body.md`로 PR 본문을 갱신한다.
   - 변경 표의 리뷰 반영 커밋에는 `(리뷰 반영)`을 붙인다.
   - 검증에는 리뷰 결과(확인·고침·보류·근거 부족 수)와 변형 확인을 적는다.
   - 보류한 지적은 하지 않은 것·알려진 한계에 적는다.
2. `gh pr comment <N> --body-file …`로 `**리뷰 반영 요약** (메인 세션)` 코멘트를 남긴다. 요약에는 다음을 적는다.
   - 고침(커밋별), 테스트 추가, 일부러 넣지 않은 것, 보류(이유), 근거 부족
   - 반박 단계에서 기각한 지적에 대한 입장
   - 남는 한계
   - 실행한 검증: 전체 테스트, 빌드, `git diff --check`, 변형 확인 수

## 4. 머지 전 검증

최신 base 위에 PR head를 합친 상태가 실제로 머지될 결과다. 원격 CI와 브랜치 보호가 없으므로 이 검증이 머지 조건이다.

```bash
git -C <repo-path> fetch origin
git -C <repo-path> worktree add --detach <repo-path>/.context/pr<N>-premerge origin/<base>
git -C <repo-path>/.context/pr<N>-premerge merge --no-commit --no-ff <head-sha>
git -C <repo-path>/.context/pr<N>-premerge diff --cached --check
(cd <repo-path>/.context/pr<N>-premerge && ./scripts/test.sh && ./scripts/build.sh)
git -C <repo-path>/.context/pr<N>-premerge merge --abort   # "Already up to date"였으면 할 일이 없다
git -C <repo-path> worktree remove <repo-path>/.context/pr<N>-premerge
```

- remove가 거절되면 `git -C <임시 경로> status`로 남은 파일을 확인한다. 임시 worktree이므로 `--force`로 지운다.
- 테스트가 실패하면 원인을 확인한다. 알려진 간헐 실패([실행 계획의 알려진 테스트 불안정](../../../plans/remaining-work.md#알려진-테스트-불안정))는 그 스위트만 따로, 전체 테스트도 다시 돌린다. 첫 실패와 재실행 결과를 함께 보고한다.
- PR 본문의 검사 실행 횟수·관련 회귀 사례와 [속도·성능 보고 기준](../create-pr/SKILL.md#테스트-실행-범위와-속도성능-보고)을 확인한다. 전후 측정의 head/base·조건이 이번 검증과 맞는지 보고, 측정 누락과 품질·성능 퇴행은 PR에 명시한다.
- 검증한 `<head-sha>`를 기록해 둔다.

## 5. 머지 (요청 시)

- `gh pr merge <N> --merge --match-head-commit <검증한 head-sha>`
  - Merge commit으로 머지한다. squash와 rebase는 쓰지 않는다.
  - 원격 브랜치는 지우지 않는다(`--delete-branch` 금지).
  - 검증 뒤 `origin/<base>`가 움직였으면 4단계를 다시 하거나 사용자에게 알린다.
- 머지 후 다른 열린 PR의 충돌을 확인한다.
  1. `git -C <repo-path> fetch origin`을 먼저 한다(GitHub에서 머지됐으므로 로컬 `origin/<base>`가 아직 옛 상태다).
  2. `gh pr list --state open --json number,headRefName,baseRefName`로 열린 PR을 얻는다.
  3. PR마다 `git -C <repo-path> merge-tree --write-tree --name-only origin/<그 PR base> origin/<그 PR head>`를 실행한다. exit 1이면 충돌이고 충돌 파일이 출력된다.
  4. `gh pr view <M> --json mergeable,mergeStateStatus`도 함께 보고한다.
- 다른 PR의 충돌을 풀지는 사용자에게 묻는다.
  - 풀 때는 3단계의 "어디서 고치나"를 따른다. 임시 worktree에서 그 PR 브랜치에 base를 merge하고 `HEAD:<브랜치>`로 푸시한다(강제 push 없음).
  - 양쪽 의도를 모두 지키는 회귀 테스트를 더하고, 그 PR에 이 스킬을 다시 적용한다.
- 로컬 main 최신화를 요청받으면 `git worktree list`에서 `[main]`으로 표시된 경로를 찾는다.
  - `git -C <그 경로> status --porcelain`이 비었는지, `git -C <그 경로> log origin/main..main`에 로컬 커밋이 없는지 확인한다.
  - 그다음 `git -C <그 경로> fetch origin && git -C <그 경로> merge --ff-only origin/main`을 실행한다.
  - 작업 worktree에서는 실행하지 않는다. 머지된 작업 브랜치가 main으로 fast-forward된다.

## 6. 보고

사용자에게 한국어로 보고한다. 내용은 다음과 같다.
- PR 링크
- 지적 수와 조치(고침·테스트 추가·근거 부족·보류)
- 검증 결과(재실행한 간헐 실패 포함)
- 전체 테스트의 실행 횟수, 변경 전후 성능 지표·측정 조건·표본 수와 미측정 항목
- 머지 커밋, 다른 PR 충돌 여부, 남은 일

실행하지 않은 것(live 테스트, 실제 앱 확인)은 그대로 밝힌다.

## deepK 기준

- 테스트는 `./scripts/test.sh`, 빌드는 `./scripts/build.sh`다.
- `./scripts/build-and-run.sh`는 실행 중인 deepK를 끄므로 사용자에게 묻고 쓴다.
- `DEEPK_RUN_LIVE_*` 테스트·벤치마크와 `codex review`는 구독 사용량을 쓰므로 허락받았을 때만 실행한다.
- 시간에 민감한 테스트(`TranslationResultTextViewTests`의 "a newly attached proxy receives the current hint", 전송 시간 초과 테스트)는 부하가 크면 가끔 실패한다.
- `benchmarks/`의 측정 원본 결과는 고치지 않는다.
