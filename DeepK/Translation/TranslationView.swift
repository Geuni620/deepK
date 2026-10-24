import AppKit
import SwiftUI

/// One horizontal inset per window size for the text of both panes, the divider between them (small window), the
/// header and the footer, so the source rule, the result line and the divider start and end together.
enum TranslationLayout {
    static func textInset(expanded: Bool) -> CGFloat { expanded ? 28 : 18 }
}

struct TranslationView: View {
    @State private var model = AppModel.shared
    /// Owned here so the footer's '↓ 새 번역 보기' can scroll the result pane.
    @State private var scrollProxy = ResultScrollProxy()
    /// Whether the result pane shows text, parsed once per result for the pane and the footer.
    @State private var presence = ResultTextPresence()

    private var store: TranslationStore { model.store }

    var body: some View {
        GeometryReader { bounds in
            let expanded = bounds.size.width >= 720
            VStack(spacing: 0) {
                header(expanded: expanded, width: bounds.size.width)
                if expanded { Divider() }
                GeometryReader { content in
                    let sourceHeight = expanded ? content.size.height : max(64, (content.size.height - 1) * 0.38)
                    let paneWidth = expanded ? (content.size.width - 1) / 2 : content.size.width
                    let layout = expanded ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                    // 같은 뷰의 배치만 바꿔 편집기·스크롤의 식별자를 유지한다.
                    layout {
                        sourcePane(expanded: expanded)
                            .frame(width: paneWidth, height: sourceHeight)
                        Rectangle().fill(Color(nsColor: .separatorColor))
                            .frame(width: expanded ? 1 : max(0, content.size.width - 2 * TranslationLayout.textInset(expanded: false)),
                                   height: expanded ? content.size.height : 1)
                        ResultPane(model: model, expanded: expanded, scrollProxy: scrollProxy, presence: presence)
                            .frame(width: paneWidth,
                                   height: expanded ? content.size.height : max(0, content.size.height - sourceHeight - 1))
                    }
                }
                // The panes run down to one divider over one fixed footer: no row appears or disappears around the text.
                Divider()
                FooterBar(model: model, expanded: expanded, scrollProxy: scrollProxy, presence: presence)
                    .frame(height: expanded ? 44 : 40)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onExitCommand { if !store.isComposing { model.hideAndRestore() } }
        .onChange(of: store.status) { _, _ in model.resultDidChange() }
    }

    private func header(expanded: Bool, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if expanded {
                HStack {
                    Menu {
                        directionOptions
                    } label: { Text(sourceLanguageTitle) }
                    .menuStyle(.borderlessButton).fixedSize()
                    Spacer(minLength: 0)
                }.padding(.horizontal, TranslationLayout.textInset(expanded: true)).frame(width: (width - 1) / 2)
                Divider().frame(width: 1)
                HStack {
                    Text(targetLanguageTitle).font(.system(size: 13))
                    Spacer(minLength: 8)
                    windowControls(expanded: true)
                }.padding(.horizontal, TranslationLayout.textInset(expanded: true)).frame(width: (width - 1) / 2)
            } else {
                HStack(spacing: 10) {
                    Picker("언어 방향", selection: Binding(get: { store.direction }, set: { model.changeDirection($0) })) {
                        Text("자동 · 한국어 ↔ English").tag(TranslationDirection.automatic)
                        Text("English → 한국어").tag(TranslationDirection.englishToKorean)
                        Text("한국어 → English").tag(TranslationDirection.koreanToEnglish)
                    }.labelsHidden().controlSize(.small).fixedSize()
                    Spacer(minLength: 4)
                    windowControls(expanded: false)
                }.padding(.horizontal, TranslationLayout.textInset(expanded: false))
            }
        }.font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 40)
    }

    private var sourceLanguageTitle: String {
        switch store.direction {
        case .englishToKorean: "English"
        case .koreanToEnglish: "한국어"
        case .automatic: "자동 · \(store.displayedSourceLanguage == .korean ? "한국어" : (store.displayedSourceLanguage == nil ? "원문" : "English"))"
        }
    }

    private var targetLanguageTitle: String {
        switch store.direction {
        case .englishToKorean: "한국어"
        case .koreanToEnglish: "English"
        case .automatic: store.displayedTargetLanguage.map { $0 == .korean ? "한국어" : "English" } ?? "번역"
        }
    }

    private var directionOptions: some View {
        Group {
            Button("자동 · 한국어 ↔ English") { model.changeDirection(.automatic) }
            Button("English → 한국어") { model.changeDirection(.englishToKorean) }
            Button("한국어 → English") { model.changeDirection(.koreanToEnglish) }
        }
    }

    private func windowControls(expanded: Bool) -> some View {
        HStack(spacing: 10) {
            if !store.sourceText.isEmpty {
                Button { model.edit("", composing: false) } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("원문 지우기")
            }
            Button { model.toggleWindowSize() } label: {
                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel(expanded ? "작게 보기" : "크게 보기")
            .help("\(expanded ? "작게" : "크게") 보기 · ⌘⇧E")
            Button { model.presentSettingsWindow() } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("설정")
        }.buttonStyle(.plain)
    }

    private func sourcePane(expanded: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            SourceEditor(text: store.sourceText, fontSize: expanded ? 14 : 13,
                         boundaryLines: store.sourceBoundaryLines,
                         findBoundaryLines: { IncrementalTranslationPlanner.boundaryLineRanges(in: $0) },
                         proxy: model.sourceEditor,
                         onEdit: { model.edit($0, composing: $1) }, onEscape: { model.hideAndRestore() })
            if store.sourceText.isEmpty {
                Text("문장을 입력하거나 다른 앱에서 ⌘C를 두 번 누르세요")
                    .font(.system(size: expanded ? 14 : 13)).foregroundStyle(.tertiary)
                    .padding(.top, 5).allowsHitTesting(false)
            }
        }
        .padding(.horizontal, TranslationLayout.textInset(expanded: expanded))
        .padding(.top, expanded ? 15 : 0)
        .padding(.bottom, expanded ? 12 : 0)
    }
}

/// The translation surface. Its state lives in the window's footer; only while there is no text yet does the state
/// appear here, where the text will appear. Nothing sits below the text, so appended translation cannot move what is
/// being read.
private struct ResultPane: View {
    let model: AppModel
    let expanded: Bool
    let scrollProxy: ResultScrollProxy
    let presence: ResultTextPresence

    private var store: TranslationStore { model.store }

    var body: some View {
        let content = store.resultContent
        TranslationResultTextView(content: content, lineSpacing: expanded ? 6 : 3, display: model.resultDisplay, proxy: scrollProxy,
                                  menuActions: [wholeDocumentRetranslation])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if !presence.showsText(content) { EmptyResultStatus(model: model) }
            }
            .padding(.horizontal, TranslationLayout.textInset(expanded: expanded))
            .padding(.top, expanded ? 20 : 10)
            // The bottom matches the source pane's, so both panes end on one line above the divider.
            .padding(.bottom, expanded ? 12 : 10)
    }

    /// In the result text's own right-click menu (a SwiftUI `.contextMenu` would never open over the text).
    private var wholeDocumentRetranslation: ResultMenuAction {
        ResultMenuAction(title: "전체 다시 번역",
                         isEnabled: { [model] in model.canRetranslateWholeDocument },
                         perform: { [model] in model.retranslateWholeDocument() })
    }
}

/// Reads the pane's state apart from `ResultPane`, so the text view is not updated for footer-only changes.
private struct EmptyResultStatus: View {
    let model: AppModel

    var body: some View {
        if let line = TranslationFooterState(model: model, resultShowsText: false, newContentBelow: false).pane {
            ResultPaneStatus(line: line)
        }
    }
}

/// The state at the top left of an empty result pane, where the text will appear; the footer does not repeat it.
/// The pane has room, so a long error wraps (up to four lines) instead of ending in '…', and it can be selected.
struct ResultPaneStatus: View {
    let line: TranslationFooterState.Line

    var body: some View {
        StatusLineLabel(line: line, lineLimit: 4)
            .textSelection(.enabled)
            .help(line.text)
            // Wraps where the translation will wrap, before the scroller gutter.
            .padding(.trailing, TextPaneMetrics.scrollerGutter)
    }
}

/// One status line in 12pt secondary text. The words start at the same x whether or not they spin: the spinner
/// follows the text, so '입력 중…' → '번역 중…' does not move them.
struct StatusLineLabel: View {
    let line: TranslationFooterState.Line
    var lineLimit = 1

    var body: some View {
        HStack(spacing: 6) {
            if line.isWarning { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text(line.text)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(lineLimit).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: lineLimit > 1)
            if line.showsProgress { ProgressView().controlSize(.small) }
        }
        .frame(minHeight: 16)
    }
}

/// The window's one footer bar, fixed in height. Left: one status line, or nothing until the pointer rests there and
/// reveals the provider, model and time. Right: the contextual text action, then 삽입 and 복사.
private struct FooterBar: View {
    let model: AppModel
    let expanded: Bool
    let scrollProxy: ResultScrollProxy
    let presence: ResultTextPresence
    @State private var showsFullStatus = false
    @State private var hovering = false

    private var store: TranslationStore { model.store }
    private var canCopy: Bool { model.captureMessage == nil && store.canCopy }

    var body: some View {
        let state = TranslationFooterState(model: model, resultShowsText: presence.showsText(store.resultContent),
                                           newContentBelow: scrollProxy.hint != .hidden)
        HStack(spacing: 12) {
            statusSlot(state)
            if let action = state.action { actionButton(action) }
            HStack(spacing: 8) {
                if model.canInsert {
                    Button("삽입") { Task { await model.insertResult() } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(model.inserting)
                }
                copyButton
            }
        }
        // Left edge on the source text, right edge on the result text.
        .padding(.horizontal, TranslationLayout.textInset(expanded: expanded))
        .onChange(of: state.status == nil) { _, empty in
            if empty { showsFullStatus = false }
        }
    }

    private func statusSlot(_ state: TranslationFooterState) -> some View {
        ZStack(alignment: .leading) {
            if let line = state.status {
                Button { showsFullStatus.toggle() } label: { StatusLineLabel(line: line) }
                .buttonStyle(.plain)
                .help(state.detail)
                .popover(isPresented: $showsFullStatus) {
                    Text(line.text).font(.system(size: 12)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14).frame(width: 300, alignment: .leading)
                }
            } else {
                Text(state.detail)
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                    .opacity(hovering ? 1 : 0)
                    .help(ifPresent: state.detailHasElapsedTime ? "입력 또는 두 번째 복사부터 전체 번역 완료까지의 시간" : nil)
                    .accessibilityLabel(state.detail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Not `.onHover`: ⌘C twice shows the window without activating deepK, and the detail must not wait for a click.
        .background(PointerHover { hovering = $0 })
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    /// A copy is confirmed where it was pressed: the pill reads '복사됨' for about two seconds. It keeps the width of
    /// the longer label, so nothing beside it moves.
    private var copyButton: some View {
        let confirmed = model.copyConfirmed && canCopy
        return Button(action: model.copyResult) {
            ZStack {
                Text("복사됨").hidden()
                Text(confirmed ? "복사됨" : "복사")
            }
        }
        .buttonStyle(PillButtonStyle(prominent: true))
        .disabled(!canCopy)
        .accessibilityLabel(confirmed ? "복사됨" : "복사")
        // Why 삽입 is missing, for an invocation that cannot insert.
        .help(ifPresent: model.insertionNote)
    }

    @ViewBuilder private func actionButton(_ action: TranslationFooterState.Action) -> some View {
        switch action {
        case .connectProvider:
            textAction("번역 제공자 연결 설정") { model.presentSettingsWindow() }
        case .retranslate(let enabled):
            textAction("다시 번역", enabled: enabled) { model.retranslateSelection() }
        case .retry:
            textAction("다시 시도") { model.retry() }
        case .revealNewContent:
            textAction("↓ 새 번역 보기") { scrollProxy.revealNewContent() }
                .accessibilityLabel("아래에 추가된 번역으로 이동")
        case .retranslateWholeDocument(let enabled):
            textAction("전체 다시 번역", enabled: enabled) { model.retranslateWholeDocument() }
        }
    }

    private func textAction(_ title: String, enabled: Bool = true, perform: @escaping @MainActor () -> Void) -> some View {
        Button(title, action: perform)
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            .disabled(!enabled)
            .fixedSize()
    }
}

/// 삽입 and 복사 share height, radius and type. 복사 is the dark primary pill, 삽입 the light grey secondary one;
/// a disabled pill drops to a faint fill and faint text.
private struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(fill(pressed: configuration.isPressed), in: shape)
            .contentShape(shape)
    }

    private var foreground: Color {
        guard isEnabled else { return Color(nsColor: .tertiaryLabelColor) }
        return prominent ? .white : Color(nsColor: .labelColor)
    }

    private func fill(pressed: Bool) -> Color {
        // The window is always light (aqua), so black at a low opacity reads as light grey.
        guard isEnabled else { return .black.opacity(0.05) }
        if prominent { return Color(red: 0.114, green: 0.114, blue: 0.122).opacity(pressed ? 0.78 : 1) }
        return .black.opacity(pressed ? 0.13 : 0.07)
    }
}

extension TranslationFooterState {
    /// The footer's inputs from the app. The label names the shown result's own model, so it survives a provider change.
    @MainActor init(model: AppModel, resultShowsText: Bool, newContentBelow: Bool) {
        let store = model.store
        var input = Input()
        input.captureMessage = model.captureMessage
        input.feedback = model.feedback
        input.feedbackIsStanding = model.feedbackIsShortcutFailure
        input.status = store.status
        input.canCopy = store.canCopy
        input.hasPartialResult = store.hasPartialResult
        input.isShowingSupersededText = store.isShowingSupersededText
        input.connecting = model.connecting
        input.requiresRetranslation = model.requiresRetranslation
        input.engineReady = store.engineReady
        input.isComposing = store.isComposing
        input.shortcutMessage = model.shortcutMessage
        input.resultShowsText = resultShowsText
        input.newContentBelow = newContentBelow
        input.modelLabel = store.resultModelLabel ?? model.requestModelLabel ?? "\(model.selectedProvider.title) · \(model.selectedModel)"
        input.elapsedMilliseconds = model.elapsedMilliseconds
        input.resultWasCached = store.lastResultWasCached
        input.unresolvedEcho = store.outputNotice == .unresolvedEcho
        input.isRetryingAfterEcho = store.isRetryingAfterEcho
        input.canRetranslateWholeDocument = model.canRetranslateWholeDocument
        self.init(input)
    }
}

private extension TranslationStore {
    /// What the result pane draws. The footer reads the same to know whether the pane shows any text.
    var resultContent: TranslationResultContent {
        let shown = display
        return TranslationResultContent(
            identity: shown.identity, text: shown.text ?? "", tailStart: shown.tailStart,
            isStreaming: status == .translating, isStale: shown.isStale, inline: shown.inline,
            sourceFences: resultFenceStyle, unitBreaks: shown.unitBreaks
        )
    }
}

/// Whether the result pane shows any text. The pane and the footer both ask on every streamed chunk; the answer is
/// parsed once per text. A draft that is only an opening fence shows nothing yet.
@MainActor final class ResultTextPresence {
    private var last: (text: String, streaming: Bool, inline: InlineOptions, shows: Bool)?
    private(set) var parses = 0

    func showsText(_ content: TranslationResultContent) -> Bool {
        let streaming = content.endsInDraft
        if let last, last.streaming == streaming, last.inline == content.inline, last.text == content.text { return last.shows }
        parses += 1
        let shows = !TranslationMarkup(content.text, streaming: streaming, inline: content.inline).displayText.isEmpty
        last = (content.text, streaming, content.inline, shows)
        return shows
    }
}

/// Reports the pointer entering and leaving, also while deepK is inactive.
private struct PointerHover: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView { HoverTrackingView() }

    func updateNSView(_ view: HoverTrackingView, context: Context) {
        view.onChange = onChange
    }
}

/// An `.activeAlways` tracking area: ⌘C twice shows the window without activating deepK, and SwiftUI's hover is not
/// promised there. The view never takes clicks.
final class HoverTrackingView: NSView {
    var onChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onChange?(true) }
    override func mouseExited(with event: NSEvent) { onChange?(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension View {
    /// A tooltip only when there is something to say.
    @ViewBuilder func help(ifPresent text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}
