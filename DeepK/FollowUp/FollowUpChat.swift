import CoreGraphics
import Foundation
import Observation

/// The follow-up window's conversation: one at a time, about one translated passage, kept only while the app runs.
/// The app supplies `answer`, which sends a prompt to the selected provider.
@MainActor @Observable final class FollowUpChat {
    typealias Answerer = @MainActor (_ prompt: String, _ onPartialText: @escaping @Sendable (String) -> Void) async throws -> String

    struct Pending: Equatable {
        let question: String
        let quote: String?
    }

    private(set) var conversation: FollowUpConversation?
    /// The question being answered. `draft` is its answer so far: Codex streams it, Claude's arrives whole.
    private(set) var pending: Pending?
    private(set) var draft = ""
    private(set) var errorMessage: String?
    var input = ""
    /// Words of the translation the next question is about.
    var quote: String?
    /// The provider and model the next answer comes from.
    var modelLabel = ""
    @ObservationIgnored var answer: Answerer?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0

    var isAnswering: Bool { pending != nil }

    /// Where the window opens: right of the translation window with its top aligned, else left of it, else inside
    /// the screen's right edge. At least as tall as the translation window.
    nonisolated static func frame(beside anchor: CGRect, size: CGSize, in screen: CGRect, gap: CGFloat = 8) -> CGRect {
        let height = min(max(size.height, anchor.height), screen.height)
        let y = min(max(anchor.maxY - height, screen.minY), screen.maxY - height)
        let right = anchor.maxX + gap
        if right + size.width <= screen.maxX { return CGRect(x: right, y: y, width: size.width, height: height) }
        let left = anchor.minX - gap - size.width
        if left >= screen.minX { return CGRect(x: left, y: y, width: size.width, height: height) }
        return CGRect(x: max(screen.minX, screen.maxX - size.width), y: y, width: size.width, height: height)
    }

    /// Starts over on `conversation`; an unfinished answer is dropped.
    func start(_ conversation: FollowUpConversation) {
        cancelAnswer()
        self.conversation = conversation
        input = ""
        errorMessage = nil
    }

    func clear() {
        cancelAnswer()
        conversation = nil
        input = ""
        quote = nil
        errorMessage = nil
    }

    /// Sends `question` (a chip) or the typed input with the quote, if any.
    func send(_ question: String? = nil) {
        guard let conversation, pending == nil, let answer else { return }
        let text = (question ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let quote = FollowUpConversation.normalizedQuote(self.quote)
        let prompt = conversation.prompt(question: text, quote: quote)
        if question == nil { input = "" }
        self.quote = nil
        errorMessage = nil
        draft = ""
        pending = Pending(question: text, quote: quote)
        generation &+= 1
        let current = generation
        task = Task { [weak self] in
            do {
                let reply = try await answer(prompt) { partial in
                    Task { @MainActor in self?.receive(partial, generation: current) }
                }
                self?.finish(reply, generation: current)
            } catch {
                self?.fail(error, generation: current)
            }
        }
    }

    /// Stops the answer and puts its question back in the field.
    func stop() {
        guard let pending else { return }
        cancelAnswer()
        if input.isEmpty { input = pending.question }
        if quote == nil { quote = pending.quote }
    }

    private func cancelAnswer() {
        generation &+= 1
        task?.cancel()
        task = nil
        pending = nil
        draft = ""
    }

    private func receive(_ partial: String, generation: UInt64) {
        guard generation == self.generation, pending != nil else { return }
        draft = partial
    }

    private func finish(_ reply: String, generation: UInt64) {
        guard generation == self.generation, let pending else { return }
        conversation?.append(question: pending.question, quote: pending.quote,
                             answer: reply.trimmingCharacters(in: .whitespacesAndNewlines))
        self.pending = nil
        draft = ""
        task = nil
    }

    private func fail(_ error: Error, generation: UInt64) {
        guard generation == self.generation, let pending else { return }
        self.pending = nil
        draft = ""
        task = nil
        if error is CancellationError { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        // The question is not lost: it waits in the field to be sent again.
        if input.isEmpty { input = pending.question }
        if quote == nil { quote = pending.quote }
    }
}
