#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import AppKit

/// One input session, one existing panel. Text and each image may finish independently.
@MainActor final class ImagePOCIntegration: NSObject {
    static let shared = ImagePOCIntegration()
    @objc func show() { AppModel.shared.showWindow() }
    @objc func scan() {
        #if DEEPK_IMAGE_TRANSLATION_POC
        guard !POCSyntheticDemo.armed else { return }
        #endif
        let app = AppModel.shared
        app.imageInput.scanner.start { image in app.acceptScannedImage(image) }
    }
    @objc func rescan() {
        #if DEEPK_IMAGE_TRANSLATION_POC
        guard !POCSyntheticDemo.armed else { return }
        #endif
        let app = AppModel.shared
        app.imageInput.scanner.start(repeatLast:true) { image in app.acceptScannedImage(image) }
    }
    func cancelImport() { AppModel.shared.imageInput.cancel() }
    @discardableResult func accept(plain:String,html:String?,sourceURL:URL? = nil) -> Bool {
        guard let html else { return false }
        let selection = ClipboardImageSelection.parse(html,sourceURL:sourceURL)
        guard selection.containsImages else { return false }
        let text = selection.documentText(from:plain), app = AppModel.shared
        app.beginImageImport(plain:text,expand:selection.items.contains { $0.inlineSize == nil } || selection.overflow > 0)
        app.imageInput.loadSelection(selection,plain:text,direction:app.store.direction)
        return true
    }
    func retryImport() { AppModel.shared.imageInput.retry(direction:AppModel.shared.store.direction) }

    /// Only use origin metadata from the same stable, non-sensitive clipboard HTML snapshot.
    static func sourceURL(for html:String,board:NSPasteboard = .general) -> URL? {
        guard !POCImage.isConcealed(board) else { return nil }
        let version = board.changeCount
        guard let actual = board.string(forType:.html),actual == html,
              let text = board.string(forType:.init("org.chromium.source-url")),text.utf8.count <= 8192,
              let url = URL(string:text),url.scheme?.lowercased() == "https",url.user == nil,url.password == nil,
              board.changeCount == version,!POCImage.isConcealed(board) else { return nil }
        return url
    }
    @discardableResult func paste(_ board:NSPasteboard = .general) -> Bool {
        guard !POCImage.isConcealed(board) else { return false }
        #if DEEPK_IMAGE_TRANSLATION_POC
        if POCSyntheticDemo.armed && !POCSyntheticDemo.accepts(plain:board.string(forType:.string) ?? "",html:board.string(forType:.html)) { return false }
        #endif
        let version = board.changeCount
        if let data = board.data(forType:.html),data.count <= 1 << 20,let html = String(data:data,encoding:.utf8) {
            let plain = board.string(forType:.string) ?? "", source = Self.sourceURL(for:html,board:board)
            if version == board.changeCount,!POCImage.isConcealed(board),accept(plain:plain,html:html,sourceURL:source) { return true }
        }
        guard let image = try? POCImage.clipboard(board),version == board.changeCount,!POCImage.isConcealed(board) else { return false }
        cancelImport();AppModel.shared.acceptInputImage(image);return true
    }
    @objc func pasteFromMenu() {
        if !paste() { NSApp.sendAction(#selector(NSText.paste(_:)),to:nil,from:nil) }
    }
    func shutdown() async { cancelImport();AppModel.shared.imageInput.clear() }
}
#endif
