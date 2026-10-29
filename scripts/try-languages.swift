import Foundation

/// Prints how deepK's automatic direction reads each text: the detected language and where it goes, or the
/// languages offered when it cannot decide. Offline: nothing is sent to a provider.
@main
struct TryLanguages {
    static let samples = [
        "Please keep the original window open.",
        "I smell fear",
        "회의는 다음 주 화요일로 옮겨도 괜찮을까요?",
        "このメソッドは非同期で実行され、完了するとコールバックを呼び出します。",
        "这个方法异步执行，完成后调用回调函数。",
        "這個方法會非同步執行，完成後呼叫回呼函式。",
        "Die Methode wird asynchron ausgeführt und ruft danach den Callback auf.",
        "La méthode s'exécute de manière asynchrone puis appelle le rappel.",
        "El método se ejecuta de forma asíncrona y luego llama a la devolución.",
        "O método é executado de forma assíncrona e depois chama o retorno.",
        "Il metodo viene eseguito in modo asincrono e poi chiama la callback.",
        "Метод выполняется асинхронно, а затем вызывает обратный вызов.",
        "Phương thức chạy bất đồng bộ rồi gọi hàm callback.",
        "Привет мир",
        "No sé.",
        "Jeg er veldig glad",
        "مرحبا بالعالم",
        "12345 — !"
    ]

    @MainActor static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var koreanTarget = TranslationLanguage.english
        if let index = arguments.firstIndex(of: "--korean-target") {
            guard index + 1 < arguments.count, let target = TranslationLanguage(rawValue: arguments[index + 1]),
                  target != .korean else {
                let codes = TranslationLanguage.allCases.filter { $0 != .korean }.map(\.rawValue).joined(separator: ", ")
                FileHandle.standardError.write(Data("--korean-target needs one of: \(codes)\n".utf8))
                exit(64)
            }
            koreanTarget = target
            arguments.removeSubrange(index...(index + 1))
        }
        let direction = TranslationDirection(source: nil, koreanTarget: koreanTarget)
        print("자동 감지 · 한국어 → \(koreanTarget.displayName) (방향 값 \(direction.rawValue))\n")
        var undecided = 0
        for text in arguments.isEmpty ? samples : arguments {
            let shown = text.count > 40 ? String(text.prefix(39)) + "…" : text
            if let source = TranslationStore.detectedLanguage(in: text) {
                let target = direction.target(for: source)
                print("✓ \(shown)\n    \(source.displayName) → \(target.displayName)   [\(source.rawValue) → \(target.rawValue)]")
            } else {
                undecided += 1
                let offered = TranslationStore.likelyLanguages(in: text).map(\.displayName)
                print("? \(shown)\n    정하지 못함 · 칩: \(offered.isEmpty ? "(없음, '원문 언어 고르기…'만)" : offered.joined(separator: " · "))")
            }
        }
        print("\n지원 언어: \(TranslationLanguage.allCases.map(\.displayName).joined(separator: ", "))")
        print("정하지 못한 원문: \(undecided)개")
    }
}
