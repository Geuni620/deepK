import Foundation

/// 2026-10-08 Haiku 비교 측정에서 실제로 나온 출력을 픽스처로 쓴다.
@main
struct TranslationOutputLintTests {
    typealias Lint = TranslationOutputLint

    static func main() {
        catchesSourceEcho()
        catchesSelfCorrectionAfterEcho()
        fixesLeakedInstructionPreamble()
        catchesForeignScript()
        catchesMissingLiterals()
        acceptsCleanTranslations()
        keepsTranslatedLabelsAndInstructions()
        keepsColonsThatBelongToTheTranslation()
        separatePreambleLineIsOnlyFixable()
        acceptsCarriageReturnParagraphs()
        ignoresCodeRepeatedFromTheSource()
        catchesEchoWithLinkTagsAndPageChrome()
        normalizesSpacesAndQuotesBeforeMatching()
        keepsVerbatimLinesOutOfTheEchoDecision()
        catchesEchoOfAParagraphThatCites()
        acceptsAppMadeFences()
        readsChatFencesLikeTheResultView()
        readsASelectionThatStartsInsideCode()
        trimsACarriageReturnPreambleInPlace()
        partialEchoImpliesFinalEcho()
        keepsAnEnglishLineOfAShortSource()
        keepsTranslationTalkFromTheSource()
        keepsACLReferencesOutOfTheEchoDecision()
        streamSkipsALogLineTheTranslationFences()
        print("TranslationOutputLintTests passed")
    }

    private static let longSource = """
    When a user copies a paragraph twice, the application should show the copied text and start translating without another click. The first copy must still work normally in the original application.

    The clipboard may update after the keyboard event arrives. Wait briefly for the current copy, but do not send old clipboard content if the copy failed.

    Measure completion when the entire translated paragraph is visible, not when the first word appears.
    """

    private static func catchesSourceEcho() {
        let output = """
        When a user copies a paragraph twice, the application should show the copied text and start translating without another click. The first copy must still work normally in the original application.

        사용자가 단락을 두 번 복사하면, 애플리케이션은 복사된 텍스트를 표시하고 추가 클릭 없이 번역을 시작해야 합니다. 첫 번째 복사는 원래 애플리케이션에서 여전히 정상적으로 작동해야 합니다.

        The clipboard may update after the keyboard event arrives. Wait briefly for the current copy, but do not send old clipboard content if the copy failed.

        클립보드는 키보드 이벤트가 도착한 후에 업데이트될 수 있습니다. 현재 복사를 잠시 기다리되, 복사가 실패한 경우에는 이전 클립보드 내용을 보내지 마십시오.

        Measure completion when the entire translated paragraph is visible, not when the first word appears.

        완료 시점은 첫 단어가 나타날 때가 아니라 번역된 단락 전체가 표시될 때 측정하십시오.
        """
        let rules = Set(Lint.lint(source: longSource, output: output, sourceLanguage: "en", targetLanguage: "ko").map(\.rule))
        require(rules.contains(.sourceEcho), "interleaved source paragraphs must be reported as source echo")
        require(rules.contains(.structure), "doubling the paragraph count must be reported")
    }

    private static func catchesSelfCorrectionAfterEcho() {
        let source = "We sincerely apologize for the inconvenience. Your refund has been processed and should appear in your account within 3–5 business days."
        let output = """
        We sincerely apologize for the inconvenience. Your refund has been processed and should appear in your account within 3–5 business days.

        Wait. Let me correct that. Here is the translation:

        불편을 드린 점 진심으로 사과드립니다. 환불이 처리되었으며, 영업일 기준 3~5일 이내에 고객님의 계정에 반영될 것입니다.
        """
        let violations = Lint.lint(source: source, output: output, sourceLanguage: "en", targetLanguage: "ko")
        require(violations.contains { $0.rule == .sourceEcho }, "the echoed source sentence must be reported")
        require(violations.contains { $0.rule == .preamble && $0.severity == .retry }, "a mid-output self-correction must require a retry")
        require(Lint.removingPreamble(from: output, source: source) == nil, "an echo is not fixable by trimming a preamble")
    }

    private static func fixesLeakedInstructionPreamble() {
        let source = "When a user copies a paragraph twice, the application should show the copied text."
        let translation = "사용자가 단락을 두 번 복사하면 애플리케이션은 복사된 텍스트를 표시해야 합니다."
        let output = "다음 텍스트를 한국어로 번역해 주세요: " + translation
        let violations = Lint.lint(source: source, output: output, sourceLanguage: "en", targetLanguage: "ko")
        require(violations.map(\.rule) == [.preamble], "only the leaked instruction should be reported: \(violations)")
        require(violations.first?.severity == .fixable, "a leading instruction before a colon is fixable")
        require(Lint.removingPreamble(from: output, source: source) == translation, "trimming must keep the translation intact")
        require(Lint.lint(source: source, output: translation, sourceLanguage: "en", targetLanguage: "ko").isEmpty, "the trimmed output must pass")

        let english = "Translation: Please do not close the original window."
        require(Lint.removingPreamble(from: english, source: "원래 창을 닫지 말아 주세요.") == "Please do not close the original window.",
                "an English label preamble is fixable too")
    }

    private static func catchesForeignScript() {
        let source = "If you have any further questions, please don't hesitate to reach out."
        let output = "추가로 궁금한 点이 있으시면 언제든지 편하게 문의해 주시기 바랍니다."
        let violations = Lint.lint(source: source, output: output, sourceLanguage: "en", targetLanguage: "ko")
        require(violations.map(\.rule) == [.foreignScript], "a stray Han character must be reported: \(violations)")

        let emotive = Lint.lint(source: "야 오늘 회의 또 미뤄졌대ㅋㅋ ㅎㅎ ㅠㅠ ㅜㅜ ㄷㄷ",
                                output: "Hey, the meeting got postponed again todayㅋㅋ ㅎㅎ ㅠㅠ ㅜㅜ ㄷㄷ",
                                sourceLanguage: "ko", targetLanguage: "en")
        require(emotive.isEmpty, "standalone jamo such as ㅋㅋ, ㅠㅠ, ㄷㄷ are allowed in English output: \(emotive)")
        let untranslated = Lint.lint(source: "야 오늘 회의 또 미뤄졌대ㅋㅋ", output: "Hey, 회의 got postponed againㅋㅋ",
                                     sourceLanguage: "ko", targetLanguage: "en")
        require(untranslated.map(\.rule) == [.foreignScript], "other Korean left in an English result must be reported")

        let kept = Lint.lint(source: "漢字 표기는 그대로 두세요.", output: "Keep the 漢字 notation as is.", sourceLanguage: "ko", targetLanguage: "en")
        require(kept.map(\.rule) == [.foreignScript], "English output still must not carry CJK outside code")
        let hanInSource = Lint.lint(source: "Write 漢字 in the title.", output: "제목에 漢字를 쓰세요.", sourceLanguage: "en", targetLanguage: "ko")
        require(hanInSource.isEmpty, "Han characters copied from the source are allowed in Korean output: \(hanInSource)")
    }

    private static func catchesMissingLiterals() {
        let source = "Delete {count} items? Run `npm ci --omit=dev` and see https://example.com/docs."
        let good = "{count}개 항목을 삭제하시겠습니까? `npm ci --omit=dev`를 실행하고 https://example.com/docs 를 참고하세요."
        require(Lint.lint(source: source, output: good, sourceLanguage: "en", targetLanguage: "ko").isEmpty, "preserved literals must pass")
        let bad = "{개수}개 항목을 삭제하시겠습니까? `npm ci`를 실행하고 문서를 참고하세요."
        let violations = Lint.lint(source: source, output: bad, sourceLanguage: "en", targetLanguage: "ko")
        require(violations.map(\.rule) == [.literalMismatch], "changed placeholder, code, and URL must be reported: \(violations)")
    }

    private static func acceptsCleanTranslations() {
        let cases: [(String, String, String, String)] = [
            // "Wait briefly"는 번역문 안의 정상 문장이며 머리말이 아니다.
            ("클립보드가 갱신될 수 있습니다. 이번 복사를 잠시 기다리세요.",
             "The clipboard may be updated. Wait briefly for this copy.", "ko", "en"),
            ("Call `cancel()` before starting the next request.\nKeep `requestID` unchanged until completion.",
             "다음 요청을 시작하기 전에 `cancel()`을 호출하세요.\n완료될 때까지 `requestID`를 변경하지 마세요.", "en", "ko"),
            // 이미 대상 언어인 원문은 같은 문장이 남아도 원문 섞임이 아니다.
            ("이 문장은 이미 한국어로 작성되어 있으므로 그대로 두어도 됩니다.",
             "이 문장은 이미 한국어로 작성되어 있으므로 그대로 두어도 됩니다.", "en", "ko"),
            // 원문에 있는 문구는 번역 대상이므로 머리말로 보지 않는다.
            ("Here is the translation: keep it short.", "Here is the translation: 짧게 유지하세요.", "en", "ko"),
            ("`./scripts/build.sh`", "`./scripts/build.sh`", "en", "ko")
        ]
        for (source, output, from, to) in cases {
            let violations = Lint.lint(source: source, output: output, sourceLanguage: from, targetLanguage: to)
            require(violations.isEmpty, "clean output was flagged: \(output) → \(violations)")
        }
    }

    /// 원문에 있던 라벨·지시문을 번역한 줄은 머리말이 아니다(PR #48 리뷰).
    private static func keepsTranslatedLabelsAndInstructions() {
        let cases: [(String, String, String, String)] = [
            ("번역: 김철수", "Translation: Kim Cheol-su", "ko", "en"),
            ("Translated text: The file was saved.", "번역문: 파일이 저장되었습니다.", "en", "ko"),
            ("Translate the following text into Korean: I love you.", "다음 텍스트를 한국어로 번역하세요: 사랑해요.", "en", "ko")
        ]
        for (source, output, from, to) in cases {
            let violations = Lint.lint(source: source, output: output, sourceLanguage: from, targetLanguage: to)
            require(violations.isEmpty, "a translated label was treated as a preamble: \(output) → \(violations)")
            require(Lint.removingPreamble(from: output, source: source) == nil, "a translated label must never be trimmed: \(output)")
        }
    }

    /// 머리말 문구 뒤에서 문장이 끝나면 그 뒤의 콜론은 번역문에 속하므로 지우지 않고 재요청한다.
    private static func keepsColonsThatBelongToTheTranslation() {
        let source = "The meeting starts at three in the afternoon."
        let output = "Let me translate this. 회의 시간: 오후 3시"
        require(Lint.removingPreamble(from: output, source: source) == nil, "a colon after the preamble sentence belongs to the translation")
        let violations = Lint.lint(source: source, output: output, sourceLanguage: "en", targetLanguage: "ko")
        require(violations.contains { $0.rule == .preamble && $0.severity == .retry }, "an untrimmable preamble must require a retry: \(violations)")
    }

    /// 머리말이 따로 한 줄을 차지해도 지우면 끝나는 출력에 재요청 판정을 함께 내지 않는다.
    private static func separatePreambleLineIsOnlyFixable() {
        let violations = Lint.lint(source: "The clipboard may be updated.", output: "Here is the translation:\n\n클립보드가 업데이트될 수 있습니다.",
                                   sourceLanguage: "en", targetLanguage: "ko")
        require(violations.map(\.severity) == [.fixable], "a separate preamble line must only be fixable: \(violations)")
    }

    private static func acceptsCarriageReturnParagraphs() {
        let violations = Lint.lint(source: "First paragraph here.\r\n\r\nSecond paragraph here.", output: "첫 번째 문단입니다.\n\n두 번째 문단입니다.",
                                   sourceLanguage: "en", targetLanguage: "ko")
        require(violations.isEmpty, "CRLF and LF paragraphs must count the same: \(violations)")
    }

    // MARK: - 코드를 뺀 원문 반복(EchoProbe)

    private static func echo(_ source: String, _ output: String, from: String = "en", to: String = "ko") -> Lint.EchoProbe.Echo {
        Lint.EchoProbe(source: source, sourceLanguage: from, targetLanguage: to).measure(output)
    }

    private static func hasSourceEcho(_ source: String, _ output: String, from: String = "en", to: String = "ko") -> Bool {
        Lint.lint(source: source, output: output, sourceLanguage: from, targetLanguage: to).contains { $0.rule == .sourceEcho }
    }

    /// 원문 코드(펜스·펜스 없음·명령·로그·인라인 코드)를 결과에 그대로 옮긴 것은 원문 반복이 아니다.
    private static func ignoresCodeRepeatedFromTheSource() {
        // benchmarks/codeblock-samples.json의 en-codeblock-1, en-codeblock-stray-1
        let codeblock = """
        Context handoff works across providers:

        import { getModel, complete } from '@mariozechner/pi-ai';

        // Start with Claude
        const claude = getModel('anthropic', 'claude-sonnet-4-5');
        const reply = await complete(claude, context);

        The reply keeps the previous messages.
        """
        let fenced = """
        컨텍스트 전달은 제공자 간에도 동작합니다:

        ```typescript
        import { getModel, complete } from '@mariozechner/pi-ai';

        // Start with Claude
        const claude = getModel('anthropic', 'claude-sonnet-4-5');
        const reply = await complete(claude, context);
        ```

        응답은 이전 메시지를 유지합니다.
        """
        let bare = fenced.replacingOccurrences(of: "```typescript\n", with: "").replacingOccurrences(of: "\n```", with: "")
        let stray = """
        Serialize the context before saving it:

        const serialized = JSON.stringify(context);
        const restored = JSON.parse(serialized);
        """
        let strayOutput = "저장하기 전에 컨텍스트를 직렬화하세요:\n\n```javascript\nconst serialized = JSON.stringify(context);\nconst restored = JSON.parse(serialized);\n```"
        // 펜스 안 문장은 산문처럼 보여도 코드다.
        let textBlock = "Add this note to the release checklist:\n\n```text\nThe server will restart automatically when the configuration changes.\n```\n\nThen tag the release."
        let textOutput = "릴리스 체크리스트에 이 메모를 추가하세요:\n\n```text\nThe server will restart automatically when the configuration changes.\n```\n\n그런 다음 릴리스에 태그를 붙이세요."
        // 소스가 펜스 안에서 끝난 선택이어도 그 코드는 코드다.
        let unclosed = "Run the following to start the development server:\n\n```bash\nnpm run dev -- --port 3000\n# The server prints the local address when it is ready to accept requests"
        let unclosedOutput = "개발 서버를 시작하려면 다음을 실행하세요:\n\n```bash\nnpm run dev -- --port 3000\n# The server prints the local address when it is ready to accept requests"
        // 결과가 원문 줄을 인라인 코드로 감쌌다.
        let commit = "Paste the following line into the commit message field and save it.\nUpdate the onboarding guide for the new contributors"
        let commitOutput = "다음 줄을 커밋 메시지 칸에 붙여 넣고 저장하세요.\n`Update the onboarding guide for the new contributors`"
        let cases: [(String, String)] = [
            (codeblock, fenced), (codeblock, bare), (stray, strayOutput), (textBlock, textOutput), (unclosed, unclosedOutput),
            ("Install the package first.\n\nnpm install --save-dev typescript eslint\n\nThen restart the server.",
             "먼저 패키지를 설치하세요.\n\nnpm install --save-dev typescript eslint\n\n그런 다음 서버를 다시 시작하세요."),
            ("Error: Cannot find module 'express'\nRequire stack:\n- /app/index.js", "Error: Cannot find module 'express'\nRequire stack:\n- /app/index.js"),
            (commit, commitOutput)
        ]
        for (source, output) in cases {
            require(!echo(source, output).isEcho, "code kept from the source is not an echo: \(output)")
            require(!hasSourceEcho(source, output), "lint must not report code kept from the source: \(output)")
        }
        require(Lint.EchoProbe(source: textBlock, sourceLanguage: "en", targetLanguage: "ko").count == 1, "fenced prose is not a candidate")
        require(hasSourceEcho(commit, commit.replacingOccurrences(of: "Paste the following line into the commit message field and save it.", with: "다음 줄을 붙여 넣으세요.")),
                "the same line outside backticks is still an echo")
    }

    private static let impeccableInput = """
    If your product already has a design you want to keep, give Impeccable that context before asking it to expand the interface. Existing code, components, and rendered pages are evidence of the system too.

    Record what you have
    Ask Impeccable to document the current system:

    Most Agents
    Codex
    Copy
    /impeccable document
    It reads the implementation and records colors, typography, layout rules, and components in `DESIGN.md`, with additional generated metadata in `.impeccable/design.json`. Review the record so it captures intentional decisions, rather than accidents or outdated styles.

    If `DESIGN.md` already exists, ask for a refresh when the implementation has changed. Keep audience, goals, and product constraints in `PRODUCT.md`, established with <a1>init</a1>. <a2>Context files</a2> explains what belongs in each record.
    """

    /// 링크 태그는 반복이면 그대로 복사되므로 남겨 비교한다. 2026-10-12 impeccable.style 사례(위젯 글자가 섞인 원문 그대로 반환).
    private static func catchesEchoWithLinkTagsAndPageChrome() {
        let link = "<a1>Read the installation guide</a1> before you configure the server."
        require(echo(link, link).isEcho && hasSourceEcho(link, link), "an echo that keeps the link tags is an echo")
        let result = echo(impeccableInput, impeccableInput)
        require(result.isEcho && result.coverage == 1, "the impeccable.style echo must be caught: \(result)")
        require(hasSourceEcho(impeccableInput, impeccableInput), "lint must report the impeccable.style echo")
    }

    /// U+00A0, 보이지 않는 문자, 둥근 따옴표가 달라도 같은 문장이다.
    private static func normalizesSpacesAndQuotesBeforeMatching() {
        let source = "The dialog says \u{201C}Saved\u{201D}\u{00A0}when the upload fin\u{00AD}ishes, and the status\u{200B} badge turns green."
        let output = "The dialog says \"Saved\" when the upload finishes, and the status badge turns green.\n\n업로드가 끝나면 대화 상자에 \"Saved\"가 표시되고 상태 배지가 초록색으로 바뀝니다."
        require(echo(source, output).isEcho, "normalized whitespace, invisible characters and quotes must match")
    }

    /// 번역에서도 그대로 두는 것이 정상인 영어: 참고문헌, 제목 목록, 링크만 있는 내비게이션, 따옴표로 감싼 화면 문구.
    private static func keepsVerbatimLinesOutOfTheEchoDecision() {
        let citations = """
        Transformers replaced recurrent networks for most sequence tasks within a few years. The original paper showed that attention alone was enough for machine translation, and later work extended the idea to images and audio.

        References
        [1] Vaswani, A., et al. (2017). Attention is all you need. Advances in Neural Information Processing Systems, 30.
        [2] Devlin, J., et al. (2019). BERT: Pre-training of deep bidirectional transformers for language understanding. In Proceedings of NAACL-HLT.
        [3] Dosovitskiy, A., et al. (2021). An image is worth 16x16 words: Transformers for image recognition at scale. In International Conference on Learning Representations.
        """
        let citationsOutput = """
        트랜스포머는 몇 년 만에 대부분의 시퀀스 작업에서 순환 신경망을 대체했습니다. 원 논문은 기계 번역에 어텐션만으로 충분하다는 것을 보였고, 이후 연구는 이 아이디어를 이미지와 오디오로 넓혔습니다.

        참고문헌
        [1] Vaswani, A., et al. (2017). Attention is all you need. Advances in Neural Information Processing Systems, 30.
        [2] Devlin, J., et al. (2019). BERT: Pre-training of deep bidirectional transformers for language understanding. In Proceedings of NAACL-HLT.
        [3] Dosovitskiy, A., et al. (2021). An image is worth 16x16 words: Transformers for image recognition at scale. In International Conference on Learning Representations.
        """
        let titles = """
        These papers explain the ideas behind modern language models, and each one is worth reading slowly.
        - Attention Is All You Need
        - Language Models Are Few-Shot Learners
        - Training Language Models to Follow Instructions with Human Feedback
        """
        let titlesOutput = """
        이 논문들은 현대 언어 모델의 바탕이 되는 아이디어를 설명하며, 하나하나 천천히 읽어 볼 만합니다.
        - Attention Is All You Need
        - Language Models Are Few-Shot Learners
        - Training Language Models to Follow Instructions with Human Feedback
        """
        let navigation = """
        Read the setup guide first, then continue with the section that matches how you deploy the application.
        <a1>Getting started with the command line</a1>
        <a2>Configuring your development environment</a2>
        <a3>Deploying to production with containers</a3>
        """
        let navigationOutput = """
        먼저 설정 안내를 읽은 뒤 애플리케이션을 배포하는 방식에 맞는 섹션으로 넘어가세요.
        <a1>Getting started with the command line</a1>
        <a2>Configuring your development environment</a2>
        <a3>Deploying to production with containers</a3>
        """
        let messages = """
        When the upload finishes, the app shows one of the following messages in the status bar.
        \u{201C}Your changes have been saved to the cloud.\u{201D}
        \u{201C}The file could not be uploaded because it is too large.\u{201D}
        \u{201C}You are offline, so the upload will resume later.\u{201D}
        """
        let messagesOutput = """
        업로드가 끝나면 앱은 상태 표시줄에 다음 메시지 중 하나를 보여 줍니다.
        "Your changes have been saved to the cloud."
        "The file could not be uploaded because it is too large."
        "You are offline, so the upload will resume later."
        """
        for (source, output) in [(citations, citationsOutput), (titles, titlesOutput), (navigation, navigationOutput), (messages, messagesOutput)] {
            let result = echo(source, output)
            require(!result.isEcho, "kept names, titles, links and quoted strings are not an echo: \(result)\n\(output)")
            // 벤치마크 판정이 줄지 않도록 lint()의 문장 규칙은 그대로 두는 줄을 거르지 않는다.
            require(hasSourceEcho(source, output), "lint keeps its sentence rule for kept lines: \(output)")
            require(echo(source, source).isEcho, "returning the whole source is still an echo: \(source)")
        }
        // 두 문장 이상인 원문은 한 문장만 그대로 남아서는 반복이 아니다.
        let paragraph = """
        The update changes how the editor saves drafts. Drafts are now stored on the device until you sign in again. Your existing documents are not affected by this change.
        """
        let oneKept = "이번 업데이트는 편집기가 초안을 저장하는 방식을 바꿉니다. 이제 초안은 다시 로그인할 때까지 기기에 저장됩니다. Your existing documents are not affected by this change."
        let kept = echo(paragraph, oneKept)
        require(!kept.isEcho && kept.found == 1 && kept.coverage < 0.4, "one kept sentence of three is not an echo: \(kept)")
        require(hasSourceEcho(paragraph, oneKept), "lint keeps its sentence rule")
    }

    /// 본문 문단 속 인용(연도, et al.)은 참고문헌 항목이 아니다. 그런 문단 하나를 그대로 돌려주면 원문 반복이다.
    private static func catchesEchoOfAParagraphThatCites() {
        let paragraphs = [
            "James Cameron directed Titanic (1997), which became the highest-grossing film of all time until his own Avatar overtook it. The film won eleven Academy Awards, including Best Picture and Best Director.",
            "Vaswani et al. introduced the Transformer architecture, and it quickly became the standard approach for sequence modeling. Later models scaled the same idea to billions of parameters.",
            "As Smith (2020) and Lee et al. (2021) report, sleep improves memory consolidation in adults. The effect is strongest after a full night of rest."
        ]
        for paragraph in paragraphs {
            let result = echo(paragraph, paragraph)
            require(result.isEcho && result.coverage == 1, "an echoed paragraph with an in-text citation is an echo: \(result)\n\(paragraph)")
            require(hasSourceEcho(paragraph, paragraph), "lint reports an echoed paragraph with an in-text citation: \(paragraph)")
        }
        let translated = "제임스 캐머런은 타이타닉(1997)을 감독했고, 이 영화는 그의 아바타가 넘어설 때까지 역대 최고 흥행작이었습니다. 이 영화는 작품상과 감독상을 포함해 아카데미상 11개를 받았습니다."
        require(!echo(paragraphs[0], translated).isEcho, "the translated paragraph is not an echo")
        // 참고문헌 항목 모양의 줄(저자 이름 + 연도)은 형식이 달라도 후보가 아니다.
        let entries = [
            "1. Vaswani A, Shazeer N, Parmar N. Attention is all you need. Advances in Neural Information Processing Systems. 2017.",
            "- Devlin, Jacob, et al. BERT: Pre-training of deep bidirectional transformers for language understanding. NAACL, 2019.",
            "[4] A. Radford, K. Narasimhan, T. Salimans, and I. Sutskever, Improving language understanding by generative pre-training, 2018."
        ]
        for entry in entries {
            require(Lint.EchoProbe(source: entry, sourceLanguage: "en", targetLanguage: "ko").count == 0, "a reference entry is not a candidate: \(entry)")
        }
    }

    /// PR B가 만드는 모델 입력 형태: ```text 블록, 맨 펜스 짝, ```가 든 4백틱 펜스. 코드를 펜스째로 또는 펜스 없이 옮겨도 반복이 아니다.
    private static func acceptsAppMadeFences() {
        let command = "Ask Impeccable to document the current system:\n\n```text\n/impeccable document\n```\n\nIt reads the implementation and records colors, typography, and layout rules in `DESIGN.md`."
        let commandOutput = "Impeccable에게 현재 시스템을 문서로 남기라고 요청하세요:\n\n```text\n/impeccable document\n```\n\n구현을 읽고 색상, 타이포그래피, 레이아웃 규칙을 `DESIGN.md`에 기록합니다."
        let bare = "Use this exact commit message:\n\n```\nPlease review the attached report before the meeting on Friday.\n```\n\nThe bot posts it to the team channel."
        let bareOutput = "다음 커밋 메시지를 그대로 쓰세요:\n\n```\nPlease review the attached report before the meeting on Friday.\n```\n\n봇이 팀 채널에 올립니다."
        let nested = "Write the snippet exactly like this in your README file:\n\n````markdown\n```bash\nnpm install\n```\nThis command installs every package that the project needs.\n````\n\nThe renderer shows it as a code block."
        let nestedOutput = "README 파일에 이 코드를 그대로 쓰세요:\n\n````markdown\n```bash\nnpm install\n```\nThis command installs every package that the project needs.\n````\n\n렌더러는 이것을 코드 블록으로 보여 줍니다."
        let cases: [(String, String)] = [
            (command, commandOutput), (command, commandOutput.replacingOccurrences(of: "```text\n", with: "").replacingOccurrences(of: "\n```", with: "")),
            (bare, bareOutput), (bare, bareOutput.replacingOccurrences(of: "```\n", with: "").replacingOccurrences(of: "\n```", with: "")),
            (nested, nestedOutput), (nested, nestedOutput.replacingOccurrences(of: "````markdown\n", with: "").replacingOccurrences(of: "\n````", with: ""))
        ]
        for (source, output) in cases {
            require(!echo(source, output).isEcho && !hasSourceEcho(source, output), "repeating app-made fenced code is not an echo: \(output)")
        }
    }

    /// 펜스 줄은 결과 창(`TranslationMarkup.reading(of:)`)처럼 읽는다. 아는 명령(```pwd)과 코드 줄로 닫히는 모르는 이름(```node)은
    /// 그 줄에서 닫히는 채팅식 블록이므로, 뒤의 산문과 맨 펜스 블록의 짝이 결과 창과 같다. 코드를 그대로 옮긴 번역은 반복이 아니다.
    private static func readsChatFencesLikeTheResultView() {
        let source = """
        Check where you are first.
        ```pwd
        /home/user/project```
        Then compare your log with the expected output below.
        ```
        The server started successfully and is now listening for new connections on port 8080.
        All background workers have been initialized and are ready to accept new jobs.
        ```
        That is all you need.
        """
        let translation = """
        먼저 현재 위치를 확인하세요.
        ```pwd
        /home/user/project```
        그런 다음 로그를 아래의 예상 출력과 비교하세요.
        ```
        The server started successfully and is now listening for new connections on port 8080.
        All background workers have been initialized and are ready to accept new jobs.
        ```
        이것으로 충분합니다.
        """
        for (opener, command) in [("```pwd", "/home/user/project```"), ("```node", "node -v```")] {
            let source = source.replacingOccurrences(of: "```pwd\n/home/user/project```", with: "\(opener)\n\(command)")
            let translation = translation.replacingOccurrences(of: "```pwd\n/home/user/project```", with: "\(opener)\n\(command)")
            let probe = Lint.EchoProbe(source: source, sourceLanguage: "en", targetLanguage: "ko")
            require(probe.count == 2, "the log lines are code, the prose around them is: \(opener) \(probe.count)")
            require(!probe.measure(translation).isEcho && !hasSourceEcho(source, translation), "a verbatim log block is not an echo: \(opener)")
            var stream = Lint.EchoProbe.Stream(probe)
            var prefix = ""
            for scalar in translation.unicodeScalars {
                prefix.unicodeScalars.append(scalar)
                require(!stream.update(with: prefix).isEcho, "the stream is never cut short: \(opener) at \(prefix.utf16.count)")
            }
            require(probe.measure(source).isEcho, "returning the source is still an echo: \(opener)")
        }
    }

    /// 선택이 코드 블록 안에서 시작하면 첫 펜스는 닫는 줄(스트레이)이다. 그 뒤 산문은 후보이고 반복이면 잡는다.
    private static func readsASelectionThatStartsInsideCode() {
        let source = "    return total;\n}\n```\n\nThen run the tests again to confirm that the fix works as expected."
        let translated = "    return total;\n}\n```\n\n그런 다음 테스트를 다시 실행해 수정이 예상대로 동작하는지 확인하세요."
        require(!echo(source, translated).isEcho && !hasSourceEcho(source, translated), "code before a stray closer is not an echo")
        require(echo(source, source).isEcho && hasSourceEcho(source, source), "prose after a stray closer is compared at completion")
    }

    private static func trimsACarriageReturnPreambleInPlace() {
        let output = "다음 텍스트를 한국어로 번역해 주세요:\r\n\r\n첫 번째 문단입니다.\r\n\r\n두 번째 문단입니다."
        require(Lint.removingPreamble(from: output, source: "First paragraph.\r\n\r\nSecond paragraph.") == "첫 번째 문단입니다.\r\n\r\n두 번째 문단입니다.",
                "trimming a preamble keeps the CRLF line ends of the rest")
    }

    /// 스트리밍 조각에서 원문 반복이면 완료 글도 원문 반복이다(조기 중단이 완료 판정과 어긋나지 않는다).
    private static func partialEchoImpliesFinalEcho() {
        let interleaved = """
        When a user copies a paragraph twice, the application should show the copied text and start translating without another click. The first copy must still work normally in the original application.

        사용자가 단락을 두 번 복사하면, 애플리케이션은 복사된 텍스트를 표시하고 추가 클릭 없이 번역을 시작해야 합니다. 첫 번째 복사는 원래 애플리케이션에서 여전히 정상적으로 작동해야 합니다.

        The clipboard may update after the keyboard event arrives. Wait briefly for the current copy, but do not send old clipboard content if the copy failed.

        클립보드는 키보드 이벤트가 도착한 후에 업데이트될 수 있습니다.
        """
        let fixtures: [(String, String)] = [
            (longSource, interleaved),
            (impeccableInput, impeccableInput),
            ("We sincerely apologize for the inconvenience. Your refund has been processed and should appear in your account within 3–5 business days.",
             "We sincerely apologize for the inconvenience. Your refund has been processed and should appear in your account within 3–5 business days.\n\nWait. Let me correct that."),
            ("<a1>Read the installation guide</a1> before you configure the server.", "<a1>Read the installation guide</a1> before you configure the server."),
            ("    return total;\n}\n```\n\nThen run the tests again to confirm that the fix works as expected.",
             "    return total;\n}\n```\n\nThen run the tests again to confirm that the fix works as expected."),
            (longSource, "사용자가 단락을 두 번 복사하면 애플리케이션은 복사한 텍스트를 보여 주고 바로 번역을 시작해야 합니다.\n\n```\nnpm test\n```"),
            ("Use this exact commit message:\n\n```\nPlease review the attached report before the meeting on Friday.\n```\n\nThe bot posts it to the team channel.",
             "다음 커밋 메시지를 그대로 쓰세요:\n\nPlease review the attached report before the meeting on Friday.\n\n봇이 팀 채널에 올립니다.")
        ]
        for (source, output) in fixtures {
            let probe = Lint.EchoProbe(source: source, sourceLanguage: "en", targetLanguage: "ko")
            let final = probe.measure(output)
            var stream = Lint.EchoProbe.Stream(probe)
            var prefix = ""
            var flagged = false
            for scalar in output.unicodeScalars {
                prefix.unicodeScalars.append(scalar)
                flagged = stream.update(with: prefix).isEcho || flagged
                require(!flagged || final.isEcho, "a partial echo must stay an echo at completion: \(prefix)")
            }
            var whole = Lint.EchoProbe.Stream(probe)
            require(whole.update(with: output) == stream.update(with: output), "the windowed search must match one full pass: \(output)")
        }
        let beforeKorean = String(interleaved[..<interleaved.range(of: "사용자가")!.lowerBound])
        var stream = Lint.EchoProbe.Stream(Lint.EchoProbe(source: longSource, sourceLanguage: "en", targetLanguage: "ko"))
        require(stream.update(with: beforeKorean).isEcho, "the interleaved echo is caught before its first Korean paragraph")
    }

    /// 후보가 두 개 이하인 짧은 원문은 모든 후보가 그대로 있어야 반복이다. 로그·오류 문구 한 줄을 영어로 두는 번역은 정상이다.
    private static func keepsAnEnglishLineOfAShortSource() {
        let install = "Run npm install in the project folder and wait for it to finish.\nadded 245 packages from 120 contributors and audited 300 packages in 5s"
        let installOutput = "프로젝트 폴더에서 npm install을 실행하고 끝날 때까지 기다리세요.\nadded 245 packages from 120 contributors and audited 300 packages in 5s"
        let crash = "When I open the app on my laptop, it crashes right away with this message.\nThe application was unable to start correctly because a required file is missing\nHow can I fix this?"
        let crashOutput = "노트북에서 앱을 열면 바로 이 메시지와 함께 꺼집니다.\nThe application was unable to start correctly because a required file is missing\n어떻게 고칠 수 있나요?"
        for (source, output) in [(install, installOutput), (crash, crashOutput)] {
            let probe = Lint.EchoProbe(source: source, sourceLanguage: "en", targetLanguage: "ko")
            let result = probe.measure(output)
            require(probe.count == 2 && result.found == 1 && !result.isEcho, "one kept line of a two-candidate source is not an echo: \(result)\n\(output)")
            var stream = Lint.EchoProbe.Stream(probe)
            var prefix = ""
            for scalar in output.unicodeScalars {
                prefix.unicodeScalars.append(scalar)
                require(!stream.update(with: prefix).isEcho, "the stream is never cut short: \(prefix)")
            }
            require(probe.measure(source).isEcho, "returning the whole two-candidate source is still an echo: \(source)")
        }
    }

    /// 원문이 번역 자체를 말하면(번역, translat-, 翻訳, 翻译) "Here is the … translation …:" 같은 첫 문장도 충실한 번역이다.
    /// 머리말로 보고하지 않고 잘라 내지도 않는다.
    private static func keepsTranslationTalkFromTheSource() {
        let cases: [(String, String)] = [
            ("다음은 이 책의 영어 번역본에 대한 소개이며 출판사는 이 책을 이렇게 설명한다: 한 세대의 기억을 담은 기록.",
             "Below is an introduction to the English translation of this book, and the publisher describes it like this: a record that holds the memory of a generation."),
            ("이 소설의 영어 번역본은 여기에 있으며, 그 첫 문장은 이렇게 시작한다: 그날 아침에는 비가 내렸다.",
             "Here is the English translation of this novel, and its first sentence begins like this: it rained that morning."),
            ("번역은 제가 직접 고쳐 보겠습니다, 이유는 아주 간단한데 바로 이것입니다: 이 문장이 틀렸습니다.",
             "Let me fix the translation myself, and the reason is very simple: this sentence was wrong.")
        ]
        for (source, output) in cases {
            require(Lint.removingPreamble(from: output, source: source) == nil, "a faithful sentence about translation is never cut: \(output)")
            let violations = Lint.lint(source: source, output: output, sourceLanguage: "ko", targetLanguage: "en")
            require(!violations.contains { $0.rule == .preamble }, "a faithful sentence about translation is not a preamble: \(violations)")
            // 원문이 번역을 말하지 않으면 같은 첫 문장은 머리말이다.
            let other = source.replacingOccurrences(of: "번역", with: "소개")
            require(Lint.removingPreamble(from: output, source: other) != nil, "the same output is still a preamble for another source: \(other)")
        }
        for mention in ["The translation team wrote this note for new readers: welcome aboard.", "TRANSLATED BY THE AUTHOR, WITH NOTES: READ SLOWLY.",
                        "この本の翻訳について、編集者は新しい読者のために長い前書きの中でこう書いている：ようこそ。",
                        "关于这本书的翻译，编辑在写给所有新读者的那篇很长的序言里这样写道：欢迎。"] {
            require(Lint.removingPreamble(from: "Here is the translation: 월요일에 회의합니다.", source: mention) == nil,
                    "a source that mentions translation before a colon turns preamble removal off: \(mention)")
        }
        // 콜론 없는 원문의 낱말만으로는 끄지 않는다(benchmarks haiku55-prompt-v2 en-long-1#1의 머리말).
        let translating = "When a user copies a paragraph twice, the application should show the copied text and start translating without another click."
        let leaked = "다음 텍스트를 한국어로 번역해 주세요: 사용자가 단락을 두 번 복사하면 애플리케이션은 복사한 텍스트를 보여 주고 번역을 시작해야 합니다."
        require(Lint.removingPreamble(from: leaked, source: translating) == "사용자가 단락을 두 번 복사하면 애플리케이션은 복사한 텍스트를 보여 주고 번역을 시작해야 합니다.",
                "a leaked instruction is still cut when the source only uses the word")
        require(Lint.lint(source: translating, output: leaked, sourceLanguage: "en", targetLanguage: "ko").contains { $0.rule == .preamble },
                "lint still reports that preamble")
    }

    /// ACL·ACM 형식 참고문헌(이름이 앞에 오는 저자, ". 2019." 연도 문장)도 그대로 두는 줄이다.
    private static func keepsACLReferencesOutOfTheEchoDecision() {
        let entries = """
        Jacob Devlin, Ming-Wei Chang, Kenton Lee, and Kristina Toutanova. 2019. BERT: Pre-training of deep bidirectional transformers for language understanding. In Proceedings of NAACL-HLT, pages 4171–4186.
        Ashish Vaswani, Noam Shazeer, Niki Parmar, Jakob Uszkoreit, Llion Jones, Aidan N. Gomez, Lukasz Kaiser, and Illia Polosukhin. 2017. Attention is all you need. In Advances in Neural Information Processing Systems, pages 5998–6008.
        Tom B. Brown and Benjamin Mann. 2020. Language models are few-shot learners. In Advances in Neural Information Processing Systems, volume 33, pages 1877–1901.
        """
        let source = "We thank the anonymous reviewers for their helpful comments on this paper. This work was supported by a grant from the national research foundation.\n\nReferences\n" + entries
        let output = "이 논문에 유익한 의견을 준 익명의 심사자들께 감사드립니다. 이 연구는 국가 연구 재단의 지원을 받았습니다.\n\n참고문헌\n" + entries
        let probe = Lint.EchoProbe(source: source, sourceLanguage: "en", targetLanguage: "ko")
        require(probe.count == 2, "ACL reference entries are not candidates: \(probe.count)")
        require(!probe.measure(output).isEcho, "a translation that keeps ACL references is not an echo: \(probe.measure(output))")
        require(hasSourceEcho(source, output), "lint keeps its sentence rule for kept lines")
        require(probe.measure(source).isEcho, "returning the whole source is still an echo")
        for entry in entries.split(separator: "\n") {
            require(Lint.EchoProbe(source: "- " + entry, sourceLanguage: "en", targetLanguage: "ko").count == 0, "a listed ACL entry is not a candidate: \(entry)")
        }
        // 이름으로 시작해도 ". 2019." 연도 문장이 없는 본문은 후보다.
        for prose in ["John Smith, the CEO, said in 2019 that the product would ship.",
                      "Mary Ann Jones and her team released the first version of the library in 2019."] {
            require(Lint.EchoProbe(source: prose, sourceLanguage: "en", targetLanguage: "ko").count == 1, "prose that starts with a name is a candidate: \(prose)")
        }
    }

    /// 원문에서 들여쓰기만 한 로그 줄은 산문 후보다. 올바른 번역이 그 줄을 펜스 블록에 넣으면 조각 판정도 코드로 읽어야 한다.
    private static func streamSkipsALogLineTheTranslationFences() {
        let source = "Run the tool and read the result.\n\n    The application could not find the configuration file in this folder\n\nThen fix the path and run it again."
        let translation = "도구를 실행하고 결과를 읽으세요.\n\n```\nThe application could not find the configuration file in this folder\n```\n\n그런 다음 경로를 고치고 다시 실행하세요."
        let probe = Lint.EchoProbe(source: source, sourceLanguage: "en", targetLanguage: "ko")
        require(probe.count == 3, "the indented log line is a candidate: \(probe.count)")
        var stream = Lint.EchoProbe.Stream(probe)
        var prefix = ""
        for line in translation.split(separator: "\n", omittingEmptySubsequences: false) {
            prefix += prefix.isEmpty ? String(line) : "\n" + line
            require(!stream.update(with: prefix).isEcho, "the fenced log line never cuts the stream short: \(prefix)")
        }
        require(!probe.measure(translation).isEcho, "the fenced log line is not an echo at completion")
        require(probe.measure(source).isEcho, "returning the source is still an echo")
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("TranslationOutputLintTests failed: \(message)") }
    }
}
