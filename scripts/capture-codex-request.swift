// 실제 CodexTranslationClient가 보내는 thread/start·turn/start를 로컬 가짜 Responses 서버로 보내 본문을 캡처한다.
// capture-codex-request.py가 실제 app-server 앞에서 중계하므로 모델 요청은 127.0.0.1을 벗어나지 않는다.
// 실행할 Codex는 앱과 같은 ExecutableResolver로 찾는다(--codex가 있으면 사용자 지정 경로로 검증한다).
import Foundation

@main
struct CaptureCodexRequest {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 2 else { fail("usage: capture <proxy> <run-dir> [--codex <path>] [--model <id>]", code: 64) }
        let proxy = URL(fileURLWithPath: arguments.removeFirst()), root = URL(fileURLWithPath: arguments.removeFirst())
        var codexPath: String?, requestedModel: String?
        while !arguments.isEmpty {
            let flag = arguments.removeFirst()
            guard !arguments.isEmpty else { fail("missing value for \(flag)", code: 64) }
            switch flag {
            case "--codex": codexPath = arguments.removeFirst()
            case "--model": requestedModel = arguments.removeFirst()
            default: fail("unknown option \(flag)", code: 64)
            }
        }

        // 앱과 같은 순서로 찾는다. --codex가 없으면 앱 설정(codexExecutablePath)을 읽기만 한다.
        let userPath = codexPath ?? UserDefaults(suiteName: "com.deepk.app")?.string(forKey: "codexExecutablePath")
        let resolver = CodexTranslationClient.ExecutableResolver(inputs: .live(
            environment: ProcessInfo.processInfo.environment,
            userExecutablePath: { userPath }
        ))
        let resolution: CodexTranslationClient.ExecutableResolver.Resolution
        do {
            resolution = try await resolver.resolve()
        } catch {
            fail("Codex를 찾지 못했습니다: \(error.localizedDescription)", code: 1)
        }
        let info = resolver.info(for: resolution)
        write(["path": info.path, "displayPath": info.displayPath, "version": info.version.map { $0 as Any } ?? NSNull(),
               "source": info.source.rawValue, "isNewerThanTested": info.isNewerThanTested],
              to: root.appendingPathComponent("executable.json"))
        FileHandle.standardError.write(Data("Codex: \(info.displayPath) · \(info.version ?? "?") (\(info.source.rawValue))\n".utf8))

        // off·on은 계획 4·5절 기준으로 검사하고, skill은 원문의 `$스킬이름`이 SKILL.md를 끌어오는 크기만 기록한다.
        let samples: [(name: String, text: String, fast: Bool, expectation: String)] = [
            ("off", "Please keep this reply short.", false, "default"),
            ("on", "Please keep this reply short.", true, "priority"),
            ("skill", "Run $diff before you commit the change.", false, "record")
        ]

        // 모델은 앱이 실제로 보내는 값(com.deepk.app의 Codex 모델, 읽기만 한다)을 먼저 캡처한다.
        // 앱 설정이 기본 모델과 다르면 기본 모델도 함께 캡처한다. 모델 카탈로그가 도구와 본문 크기를 바꾸기 때문이다.
        let targets: [(model: String, source: String)]
        if let requestedModel {
            targets = [(requestedModel, "argument")]
        } else {
            let appModel = TranslationSelection.model(for: .codex, in: UserDefaults(suiteName: "com.deepk.app") ?? .standard)
            let defaultModel = TranslationProvider.codex.defaultModel
            targets = appModel == defaultModel ? [(appModel, "app")] : [(appModel, "app"), (defaultModel, "default")]
        }

        var catalog: [CodexTranslationClient.Model]?
        var caseEntries: [String: Any] = [:]
        var modelEntries: [[String: Any]] = []
        for target in targets {
            // 계정 카탈로그에 없으면 카탈로그 기본 모델로 바꾸고 보고서에 남긴다(--model로 지정한 경우는 그대로 쓴다).
            var model = target.model
            var fallback = false
            for sample in samples {
                let name = "\(target.model)/\(sample.name)"
                let client = CodexTranslationClient(configuration: .init(
                    executableURL: proxy,
                    environment: [
                        "DEEPK_CAPTURE_DIR": root.appendingPathComponent(name).path,
                        "DEEPK_CAPTURE_REAL_CODEX": resolution.executable.path
                    ],
                    prewarmEnabled: false
                ))
                do {
                    if catalog == nil { catalog = try await client.listModels() }
                    let models = catalog ?? []
                    if target.source != "argument", !models.contains(where: { $0.model == model }),
                       let replacement = models.first(where: \.isDefault) ?? models.first {
                        fallback = true
                        model = replacement.model
                    }
                    let output = try await client.translate(text: sample.text, source: "en", target: "ko", model: model,
                                                            fastServiceTier: sample.fast)
                    FileHandle.standardError.write(Data("\(name): \(output)\n".utf8))
                } catch {
                    await client.disconnect()
                    fail("\(name) failed: \(error.localizedDescription)", code: 1)
                }
                await client.disconnect()
                caseEntries[name] = ["expectation": sample.expectation, "model": model, "modelSource": target.source]
            }
            modelEntries.append(["requested": target.model, "model": model, "source": target.source, "fallback": fallback])
        }
        write(caseEntries, to: root.appendingPathComponent("cases.json"))
        write(["models": modelEntries], to: root.appendingPathComponent("helper.json"))
    }

    private static func write(_ value: [String: Any], to url: URL) {
        do {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                .write(to: url, options: .atomic)
        } catch {
            fail("could not write \(url.path): \(error.localizedDescription)", code: 1)
        }
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(code)
    }
}
