import Foundation

/// Translates a passage the way the app's automatic direction does, then opens a terminal conversation about it with
/// the same prompt and the same provider path as the '묻기' window. Uses the subscription of the chosen provider.
@main
struct TryFollowUp {
    struct Options {
        var provider: TranslationProvider
        var model: String
        var koreanTarget = TranslationLanguage.english
        var source: String?
        var showPrompt = false
    }

    static let usage = """
        사용법: ./scripts/try-followup.sh [옵션] [원문]
          원문을 생략하면 표준 입력에서 읽는다(끝나면 Ctrl-D).
          --provider claude|codex   기본값: deepK 앱 설정의 번역 제공자
          --model ID                기본값: deepK 앱 설정의 그 제공자 모델
          --korean-target CODE      한국어 원문을 번역할 언어(기본 en). 예: ja, zh-Hans, de
          --file PATH               원문을 파일에서 읽는다
          --show-prompt             질문마다 보내는 프롬프트를 출력한다
        대화 중 명령: /요약 /쉽게 풀어서 /용어 설명 /예시 들어서 /원문 문법 · /quote 낱말(다음 질문의 인용)
                      /new 새 원문 · /q 끝내기
        """

    static func main() async {
        guard var options = parseOptions() else { exit(64) }
        // Piped without a source argument: the pipe is the passage, and questions come from the terminal.
        if options.source == nil, isatty(STDIN_FILENO) == 0 {
            options.source = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
            if freopen("/dev/tty", "r", stdin) == nil { options.source = options.source ?? "" }
        }
        let app = UserDefaults(suiteName: "com.deepk.app") ?? .standard
        print("제공자: \(TranslationSelection(provider: options.provider, model: options.model).label) · 구독 사용량을 씁니다.\n")

        let claude = ClaudeTranslationClient(configuration: .init(
            executableURL: app.string(forKey: "claudeExecutablePath").map { URL(fileURLWithPath: $0) },
            transport: .oneShotJSON, subscriptionProofMaxAge: 0, subscriptionRefreshInterval: 0
        ))
        let codexPath = app.string(forKey: "codexExecutablePath")
        let codex = CodexTranslationClient(configuration: .init(
            prewarmEnabled: false,
            userExecutablePathProvider: { codexPath }
        ))
        defer { Task { await claude.disconnect(); await codex.disconnect() } }

        while true {
            let source = options.source ?? readSource()
            options.source = nil
            guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            guard let language = sourceLanguage(of: source) else { continue }
            let direction = TranslationDirection(source: nil, koreanTarget: options.koreanTarget)
            let target = direction.target(for: language)
            print("\n[\(language.displayName) → \(target.displayName)] 번역 중…")
            let translation: String
            do {
                translation = try await translate(source, from: language, to: target, options: options, claude: claude, codex: codex)
            } catch {
                print("번역 실패: \(describe(error))")
                continue
            }
            print("\n\(translation)\n")
            let restart = await converse(about: FollowUpConversation(source: source, translation: translation,
                                                                     sourceLanguage: language.rawValue,
                                                                     targetLanguage: target.rawValue),
                                         options: options, claude: claude, codex: codex)
            if !restart { break }
        }
        await claude.disconnect()
        await codex.disconnect()
    }

    /// Returns true for `/new`.
    static func converse(about start: FollowUpConversation, options: Options,
                         claude: ClaudeTranslationClient, codex: CodexTranslationClient) async -> Bool {
        var conversation = start
        var quote: String?
        let chips = FollowUpConversation.suggestions.map { "/\($0.title)" }.joined(separator: " ")
        print("이 글에 대해 물어보세요. \(chips) · /quote 낱말 · /new · /q")
        while true {
            print(quote.map { "질문 (인용: \($0))> " } ?? "질문> ", terminator: "")
            guard let line = readLine() else { return false }
            let input = line.trimmingCharacters(in: .whitespaces)
            if input.isEmpty { continue }
            if input == "/q" { return false }
            if input == "/new" { return true }
            if input.hasPrefix("/quote") {
                quote = FollowUpConversation.normalizedQuote(String(input.dropFirst("/quote".count)))
                continue
            }
            var question = input
            if input.hasPrefix("/") {
                guard let chip = FollowUpConversation.suggestions.first(where: { "/\($0.title)" == input }) else {
                    print("모르는 명령입니다. \(chips) /quote /new /q")
                    continue
                }
                question = chip.question
                print("→ \(question)")
            }
            let prompt = conversation.prompt(question: question, quote: quote)
            if options.showPrompt { print("----- 프롬프트 -----\n\(prompt)\n--------------------") }
            let printer = StreamPrinter()
            let started = Date()
            do {
                let answer: String
                switch options.provider {
                case .codex:
                    answer = try await codex.answer(prompt: prompt, instructions: FollowUpConversation.instructions,
                                                    model: options.model, onPartialText: { printer.show($0) })
                case .claude:
                    print("(답변 중…)")
                    answer = try await claude.answer(prompt: prompt, instructions: FollowUpConversation.instructions,
                                                     model: options.model)
                }
                printer.finish(answer)
                print(String(format: "\n(%.1f초)\n", Date().timeIntervalSince(started)))
                conversation.append(question: question, quote: quote, answer: answer.trimmingCharacters(in: .whitespacesAndNewlines))
                quote = nil
            } catch {
                print("\n답변 실패: \(describe(error))\n")
            }
        }
    }

    static func translate(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage, options: Options,
                          claude: ClaudeTranslationClient, codex: CodexTranslationClient) async throws -> String {
        switch options.provider {
        case .codex:
            try await codex.translate(text: text, source: source.rawValue, target: target.rawValue, model: options.model)
        case .claude:
            try await claude.translate(text: text, source: source.rawValue, target: target.rawValue, model: options.model)
        }
    }

    /// Detection as in the app; when it cannot decide, the reader picks like the app's chips.
    @MainActor static func sourceLanguage(of text: String) -> TranslationLanguage? {
        if let detected = TranslationStore.detectedLanguage(in: text) { return detected }
        let offered = TranslationStore.likelyLanguages(in: text)
        print("원문 언어를 정하지 못했어요. 후보: \(offered.map { "\($0.displayName)(\($0.rawValue))" }.joined(separator: ", "))")
        print("언어 코드를 입력하세요 (\(TranslationLanguage.allCases.map(\.rawValue).joined(separator: " "))): ", terminator: "")
        guard let code = readLine()?.trimmingCharacters(in: .whitespaces), let language = TranslationLanguage(rawValue: code) else {
            print("알 수 없는 언어입니다. 원문을 다시 넣어 주세요.")
            return nil
        }
        return language
    }

    static func readSource() -> String? {
        print("원문을 붙여넣고 Ctrl-D를 누르세요 (비우고 Ctrl-D면 끝):")
        var lines: [String] = []
        while let line = readLine(strippingNewline: true) { lines.append(line) }
        clearerr(stdin)
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    static func parseOptions() -> Options? {
        let app = UserDefaults(suiteName: "com.deepk.app") ?? .standard
        let saved = TranslationSelection.load(from: app)
        var provider = saved.provider
        var model: String?
        var koreanTarget = TranslationLanguage(rawValue: app.string(forKey: "koreanTargetLanguage") ?? "") ?? .english
        var source: String?
        var showPrompt = false
        var arguments = Array(CommandLine.arguments.dropFirst())[...]
        var words: [String] = []
        while let argument = arguments.popFirst() {
            switch argument {
            case "-h", "--help":
                print(usage)
                exit(0)
            case "--provider":
                guard let value = arguments.popFirst(), let chosen = TranslationProvider(rawValue: value) else {
                    print("--provider는 claude 또는 codex입니다.\n\n\(usage)"); return nil
                }
                provider = chosen
            case "--model":
                guard let value = arguments.popFirst() else { print(usage); return nil }
                model = value
            case "--korean-target":
                guard let value = arguments.popFirst(), let target = TranslationLanguage(rawValue: value), target != .korean else {
                    print("--korean-target 코드: \(TranslationLanguage.allCases.filter { $0 != .korean }.map(\.rawValue).joined(separator: ", "))")
                    return nil
                }
                koreanTarget = target
            case "--file":
                guard let path = arguments.popFirst(), let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                    print("--file 경로를 읽지 못했습니다."); return nil
                }
                source = text
            case "--show-prompt":
                showPrompt = true
            default:
                words.append(argument)
            }
        }
        if source == nil, !words.isEmpty { source = words.joined(separator: " ") }
        return Options(provider: provider, model: model ?? TranslationSelection.model(for: provider, in: app),
                       koreanTarget: koreanTarget, source: source, showPrompt: showPrompt)
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

/// Prints a streamed answer as it grows. Codex sends the whole text so far each time.
final class StreamPrinter: @unchecked Sendable {
    private let lock = NSLock()
    private var printed = ""

    func show(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        guard text.hasPrefix(printed) else { return }
        print(text.dropFirst(printed.count), terminator: "")
        fflush(stdout)
        printed = text
    }

    func finish(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        if text.hasPrefix(printed) { print(text.dropFirst(printed.count), terminator: "") } else { print("\n" + text, terminator: "") }
        print("")
        printed = text
    }
}
