import AppKit
import SwiftUI

/// The window beside the translation window for questions about the translated passage.
struct FollowUpChatView: View {
    @State private var model = AppModel.shared
    @FocusState private var inputFocused: Bool

    var body: some View {
        let chat = model.followUp
        VStack(spacing: 0) {
            if model.followUpIsStale { staleBanner }
            if let conversation = chat.conversation { ContextStrip(conversation: conversation) }
            FollowUpMessages(chat: chat)
            FollowUpInput(chat: chat, focused: $inputFocused)
        }
        .frame(minWidth: 300, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { inputFocused = true }
        .onChange(of: chat.quote) { _, quote in if quote != nil { inputFocused = true } }
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Text("원문이 바뀌었어요")
            Spacer(minLength: 4)
            Button("새 원문으로 시작") { model.restartFollowUp() }
                .buttonStyle(.borderless).fontWeight(.semibold)
                .disabled(!model.canAskFollowUp)
        }
        .font(.system(size: 12)).foregroundStyle(Color(nsColor: .systemOrange))
        .padding(.horizontal, 10).frame(height: 30)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12).padding(.top, 10)
    }
}

/// What every question sends along, with the passage and translation a click away.
private struct ContextStrip: View {
    let conversation: FollowUpConversation
    @State private var showsContext = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").foregroundStyle(.tertiary)
            Text("원문·번역을 함께 보내요 · \(conversation.source.count)자")
            Spacer(minLength: 4)
            Button("보기") { showsContext.toggle() }
                .buttonStyle(.borderless)
                .popover(isPresented: $showsContext, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("원문").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Text(conversation.source).textSelection(.enabled)
                            Divider()
                            Text("번역").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Text(conversation.translation).textSelection(.enabled)
                        }
                        .font(.system(size: 12)).padding(14).frame(width: 320, alignment: .leading)
                    }
                    .frame(maxHeight: 360)
                }
        }
        .font(.system(size: 11.5)).foregroundStyle(.secondary)
        .padding(.horizontal, 10).frame(height: 28)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .padding(.horizontal, 12).padding(.top, 10)
    }
}

private struct FollowUpMessages: View {
    let chat: FollowUpChat

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let conversation = chat.conversation {
                        ForEach(conversation.turns) { turn in
                            QuestionBubble(question: turn.question, quote: turn.quote)
                            AnswerText(text: turn.answer, label: chat.modelLabel)
                        }
                    }
                    if let pending = chat.pending {
                        QuestionBubble(question: pending.question, quote: pending.quote)
                        if chat.draft.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("답변 중…").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        } else {
                            AnswerText(text: chat.draft, label: chat.modelLabel)
                        }
                    }
                    if let error = chat.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if chat.conversation?.turns.isEmpty != false, chat.pending == nil {
                        Suggestions(chat: chat)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: chat.conversation?.turns.count) { _, _ in reader.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: chat.pending) { _, _ in reader.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: chat.draft) { _, _ in reader.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }

    private static let bottom = "bottom"
}

private struct Suggestions: View {
    let chat: FollowUpChat

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(FollowUpConversation.suggestions, id: \.title) { suggestion in
                Button(suggestion.title) { chat.send(suggestion.question) }
                    .buttonStyle(ChipStyle())
                    .help(suggestion.question)
            }
        }
        .disabled(chat.answer == nil || chat.conversation == nil)
    }
}

private struct QuestionBubble: View {
    let question: String
    let quote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let quote {
                Text(quote).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                    .padding(.leading, 7)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 2) }
            }
            Text(question).textSelection(.enabled)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Color.black.opacity(0.06), in: UnevenRoundedRectangle(
            topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 3, topTrailingRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 36)
    }
}

/// An answer: prose with inline Markdown, fenced code in a box. Selectable, so ⌘C copies any part.
private struct AnswerText: View {
    let text: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { Text(label).font(.system(size: 11)).foregroundStyle(.tertiary) }
            ForEach(Array(AnswerBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let prose):
                    Text(AnswerBlock.inlineMarkdown(prose)).font(.system(size: 13)).lineSpacing(3)
                case .code(let code):
                    Text(code).font(.system(size: 12, design: .monospaced))
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FollowUpInput: View {
    let chat: FollowUpChat
    let focused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var chat = chat
        VStack(alignment: .leading, spacing: 6) {
            if let quote = chat.quote {
                HStack(alignment: .top, spacing: 6) {
                    Text(quote).lineLimit(2).foregroundStyle(.secondary)
                        .padding(.leading, 7)
                        .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 2) }
                    Spacer(minLength: 4)
                    Button { chat.quote = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary).accessibilityLabel("인용 지우기")
                }
                .font(.system(size: 12))
            }
            TextField(chat.conversation?.turns.isEmpty == false ? "이어서 묻기…" : "이 글에 대해 묻기…",
                      text: $chat.input, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...6)
                .focused(focused)
                .onSubmit { chat.send() }
            HStack(spacing: 8) {
                Text(chat.modelLabel).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if chat.isAnswering {
                    Button { chat.stop() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 18))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("멈추기")
                } else {
                    let canSend = chat.conversation != nil && chat.answer != nil
                        && !chat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button { chat.send() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
                    }
                    .buttonStyle(.plain).foregroundStyle(canSend ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    .disabled(!canSend).accessibilityLabel("보내기")
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }
}

private struct ChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12)).foregroundStyle(Color(nsColor: .labelColor))
            .padding(.horizontal, 10).frame(height: 24)
            .background(.black.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Lays chips out in rows, wrapping at the proposed width.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
