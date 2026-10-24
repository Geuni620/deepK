import AppKit

/// Renders the real result view offscreen for every style, in light and dark, at the small and large window widths,
/// with syntax colors and the 7-line block folded to 5 (the defaults), with the source pill, with the block expanded, and
/// folded with everything selected, and writes PNGs. A manual check, not part of scripts/test.sh:
///
///     swiftc -swift-version 6 <RESULT_VIEW_SOURCES in scripts/test.sh> DeepKTests/Fixtures/ResultStyleFixtures.swift \
///       DeepKTests/Fixtures/ResultStyleSnapshots.swift -o /tmp/deepk-snap && /tmp/deepk-snap /tmp/deepk-shots
@main
@MainActor
private enum ResultStyleSnapshots {
    static let text = """
    핵심은 모델에 정확히 네 가지 도구만 줍니다. `read`, `bash`만 씁니다. 확인해 보세요: <a1>하네스 찾기</a1>.

    ```typescript
    // Claude로 시작
    import { getModel } from 'ai';
    const claude = getModel('anthropic');
    const ctx = await loadContext(repo);
    const reply = await complete(claude, ctx);
    console.log(reply.text);
    export default reply;
    ```

    설치는 한 줄입니다.

    ```
    npm install deepk
    ```

    에이전트에 맞는 명령을 고르세요.

    ```text title="Most Agents"
    /impeccable document
    ```

    npm으로 설치합니다.

    ```bash title="npm"
    npm install deepk
    ```

    제목이 길면 복사 앞에서 줄입니다.

    ```ts title="src/components/settings/CodeStylePickerPreview.tsx"
    export const preview = true;
    ```

    문서: <a2>안내서</a2>, 메일: <a3>문의</a3>.
    """
    static let inline = InlineOptions(code: .only(["read", "bash"]), links: [
        SourceLink(url: URL(string: "https://www.blog.example.com/harness")!, text: "Finding the best harness"),
        SourceLink(url: URL(string: "https://docs.example.com/guide")!, text: "guide"),
        SourceLink(url: URL(string: "mailto:hello@example.com")!, text: "contact")
    ])

    static func main() {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/deepk-shots")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var count = 0
        for style in ResultStyle.builtIns + ResultStyle.fixtures {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for width in [384.0, 439.0] {
                    for variant in Variant.allCases {
                        var display = ResultDisplaySettings.standard
                        display.style = style
                        display.showsLinkSource = variant == .pill
                        let suffix = variant == .folded ? "" : "-\(variant)"
                        let name = "\(style.id.rawValue)-\(appearance == .aqua ? "light" : "dark")-\(Int(width))\(suffix).png"
                        render(display: display, variant: variant, appearance: appearance, width: width, to: output.appendingPathComponent(name))
                        count += 1
                    }
                }
            }
        }
        print("ResultStyleSnapshots wrote \(count) images to \(output.path)")
    }

    private enum Variant: CaseIterable { case folded, pill, expanded, selected }

    private static func render(display: ResultDisplaySettings, variant: Variant, appearance: NSAppearance.Name, width: CGFloat, to url: URL) {
        let scroll = TranslationResultTextView.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 1200)
        scroll.layoutSubtreeIfNeeded()
        TranslationResultTextView.update(scroll, content: TranslationResultContent(
            identity: UUID(), text: text, tailStart: nil, isStreaming: false, isStale: false, inline: inline
        ), lineSpacing: 3, display: display)
        let view = scroll.documentView as! ResultTextView
        switch variant {
        case .expanded:
            if let box = view.codeBoxes().first(where: { $0.fold.hasFooter }) { view.perform(.fold(box.key)) }
        case .selected:
            view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        case .folded, .pill: break
        }
        let padding: CGFloat = 18
        let canvas = Canvas(frame: NSRect(x: 0, y: 0, width: width + 2 * padding, height: view.frame.height + 2 * padding))
        canvas.appearance = NSAppearance(named: appearance)
        scroll.frame = NSRect(x: padding, y: padding, width: width, height: view.frame.height)
        canvas.addSubview(scroll)
        canvas.layoutSubtreeIfNeeded()
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The result pane's background.
    private final class Canvas: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }
}
