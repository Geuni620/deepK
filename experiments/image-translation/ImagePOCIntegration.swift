#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit

/// Clipboard images enter the existing translation panel. Import state stays in memory.
@MainActor final class ImagePOCIntegration: NSObject {
    static let shared = ImagePOCIntegration()
    private var importTask: Task<Void, Never>?
    private var generation = UUID()
    private var pendingSelection: (selection: ClipboardImageSelection, plain: String)?
    @objc func show() { AppModel.shared.showWindow() }
    @objc func scan() {
        guard !POCSyntheticDemo.armed else { return }
        cancelImport()
        let app = AppModel.shared
        app.imageInput.scanner.start { image in app.acceptInputImage(image) }
    }
    @objc func rescan() {
        guard !POCSyntheticDemo.armed else { return }
        cancelImport()
        let app = AppModel.shared
        app.imageInput.scanner.start(repeatLast: true) { image in app.acceptInputImage(image) }
    }
    func cancelImport() { generation = UUID(); importTask?.cancel(); importTask = nil; pendingSelection = nil }
    @discardableResult func accept(plain: String, html: String?) -> Bool {
        guard let html else { return false }
        let selection = ClipboardImageSelection.parse(html)
        guard selection.containsImages else { return false }
        start(selection, plain: selection.documentText(from: plain))
        return true
    }
    func retryImport() { if let pendingSelection { start(pendingSelection.selection, plain: pendingSelection.plain) } }
    private func start(_ selection: ClipboardImageSelection, plain: String) {
        cancelImport()
        pendingSelection = (selection, plain)
        let token = generation, app = AppModel.shared
        app.beginImageImport(plain: plain)
        importTask = Task { [weak self] in
            do {
                let image = try await selection.load()
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                app.acceptInputImage(image, plain: plain)
                self.importTask = nil; self.pendingSelection = nil
            } catch {
                guard let self, self.generation == token else { return }
                app.imageInput.busy = false
                app.imageInput.status = (error as? ImagePOCError)?.localizedDescription ?? "선택한 이미지를 읽지 못했습니다. 원본 이미지 서버 연결을 확인해 주세요."
                self.importTask = nil
            }
        }
    }
    @discardableResult func paste(_ board: NSPasteboard = .general) -> Bool {
        guard !POCImage.isConcealed(board) else { return false }
        if POCSyntheticDemo.armed && !POCSyntheticDemo.accepts(plain: board.string(forType: .string) ?? "", html: board.string(forType: .html)) { return false }
        let version = board.changeCount
        if let data = board.data(forType: .html), data.count <= 1 << 20, let html = String(data: data, encoding: .utf8) {
            let plain = board.string(forType: .string) ?? ""
            if version == board.changeCount, !POCImage.isConcealed(board), accept(plain: plain, html: html) { return true }
        }
        guard let image = try? POCImage.clipboard(board), version == board.changeCount, !POCImage.isConcealed(board) else { return false }
        cancelImport(); AppModel.shared.acceptInputImage(image); return true
    }
    @objc func pasteFromMenu() {
        if !paste() { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
    }
    func shutdown() async { cancelImport(); AppModel.shared.imageInput.clear() }
}
#endif
