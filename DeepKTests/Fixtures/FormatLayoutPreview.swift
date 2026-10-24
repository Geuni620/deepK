import AppKit

/// Executes the app's native source/result views with synthetic input and a deterministic translated
/// fixture. No app launch, subscription client, general clipboard or external insertion is involved.
@main
@MainActor
private struct FormatLayoutPreview {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("usage: preview <new-output-directory> <label>") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let label = CommandLine.arguments[2]
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        let english = [
            "Describe the outcome: ordinary language is enough. For a change you can name, commands such as layout, typeset, and colorize focus the work.",
            "Ask for a review: critique explains what is holding the design back and recommends where to start. You choose which changes to make.",
            "Compare alternatives: generate takes an element and a direction from chat, then shows variants in your running page. Choose the version to keep in source.",
            "Point at the page: Live Mode lets you select elements yourself. Use Steer for a direction that applies across the page."
        ]
        let korean = [
            "결과 설명: 원하는 결과를 일상적인 말로 설명하세요. 바꾸고 싶은 내용이 분명하면 레이아웃, 조판, 색상처럼 구체적인 작업을 지정하세요.",
            "검토 요청: 디자인을 어렵게 만드는 문제와 시작할 지점을 확인하세요. 어떤 변경을 적용할지는 직접 선택합니다.",
            "대안 비교: 요소와 원하는 방향을 전달하면 여러 안을 비교할 수 있습니다. 소스에 유지할 버전을 고르세요.",
            "페이지 가리키기: 바꾸려는 요소를 직접 선택하세요. 페이지 전반에 적용할 방향도 지정할 수 있습니다."
        ]
        let plain = english.joined(separator: "\n")
        let html = "<ul>" + english.map { "<li>" + $0 + "</li>" }.joined() + "</ul>"
        let captured = RichSourceImporter.copiedSource(plain: plain, html: html)
        let marked = captured.plain.components(separatedBy: "\n").filter { $0.hasPrefix("- ") || $0.hasPrefix("• ") }.count
        // A controlled response preserves the explicit item markers that reached the model.
        let translated = korean.map { (marked == english.count ? "- " : "") + $0 }.joined(separator: "\n")
        var metrics: [[String: Any]] = []
        for expanded in [true, false] {
            let size = expanded ? NSSize(width: 1040, height: 610) : NSSize(width: 430, height: 960)
            let root = NSView(frame: NSRect(origin: .zero, size: size))
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            func caption(_ text: String, _ frame: NSRect, bold: Bool = false) {
                let field = NSTextField(labelWithString: text)
                field.frame = frame
                field.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 12)
                field.textColor = .secondaryLabelColor
                root.addSubview(field)
            }
            caption("deepK · 목록 구조 검증 · \(label)", NSRect(x: 18, y: size.height - 32, width: size.width - 36, height: 20), bold: true)
            caption("합성 입력과 번역 응답 · 실제 앱의 SourceEditor / TranslationResultTextView 실행", NSRect(x: 18, y: 6, width: size.width - 36, height: 18))
            let source = SourceEditor.makeScrollView(fontSize: 14)
            let result = TranslationResultTextView.makeScrollView()
            if expanded {
                let width = (size.width - 52) / 2
                source.frame = NSRect(x: 18, y: 32, width: width, height: size.height - 104)
                result.frame = NSRect(x: width + 34, y: 32, width: width, height: size.height - 104)
                caption("English · 원문", NSRect(x: 18, y: size.height - 62, width: width, height: 20))
                caption("한국어 · 고정 번역 표본", NSRect(x: width + 34, y: size.height - 62, width: width, height: 20))
            } else {
                source.frame = NSRect(x: 18, y: size.height - 344, width: size.width - 36, height: 272)
                result.frame = NSRect(x: 18, y: 32, width: size.width - 36, height: size.height - 414)
                caption("English · 원문", NSRect(x: 18, y: size.height - 62, width: size.width - 36, height: 20))
                caption("한국어 · 고정 번역 표본", NSRect(x: 18, y: size.height - 377, width: size.width - 36, height: 20))
            }
            root.addSubview(source)
            root.addSubview(result)
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = root
            let spec = SourceEditor(text: captured.plain, fontSize: 14, onEdit: { _, _ in }, onEscape: {})
            let coordinator = spec.makeCoordinator()
            let editor = source.documentView as! SourceEditor.Editor
            coordinator.show(captured.plain, boundaryLines: [], in: editor)
            TranslationResultTextView.update(result, content: TranslationResultContent(identity: UUID(), text: translated,
                tailStart: nil, isStreaming: false, isStale: false), lineSpacing: 5)
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { fatalError("bitmap unavailable") }
            root.cacheDisplay(in: root.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG unavailable") }
            let name = label + (expanded ? "-wide.png" : "-compact.png")
            try data.write(to: output.appendingPathComponent(name), options: .withoutOverwriting)
            let style = editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            metrics.append(["image": name, "width": Int(size.width), "sourceMarkerCount": marked,
                            "sourceHeadIndent": style?.headIndent ?? 0, "sourceFirstLineIndent": style?.firstLineHeadIndent ?? 0,
                            "sourceTextKit2": editor.textLayoutManager != nil])
            window.contentView = nil
            window.close()
        }
        let resultMarkup = TranslationMarkup(translated)
        try Data(resultMarkup.html.utf8).write(to: output.appendingPathComponent(label + "-copy.html"), options: .withoutOverwriting)
        let summary: [String: Any] = ["label": label, "source": captured.plain, "translation": translated,
            "sourceRawPreserved": captured.raw == plain, "snapshots": metrics,
            "scope": "Executed native components with synthetic deterministic translation; not a live model or real cross-app clipboard test."]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(label + ".json"), options: .withoutOverwriting)
        print("Native format fixture: \(label), markers=\(marked), snapshots=2, live requests=0")
    }
}
