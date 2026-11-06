#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import CoreVideo
import Observation
import ScreenCaptureKit

struct POCScanDisplay: Sendable, Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let scale: CGFloat
}

struct POCScanRegion: Sendable, Equatable {
    let display: POCScanDisplay
    /// Global AppKit points, lower-left origin. Never persisted or sent to a translation provider.
    let rect: CGRect

    static func selected(from start: CGPoint, to end: CGPoint, on display: POCScanDisplay) -> Self? {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(display.frame)
        guard !rect.isNull, rect.width >= 8, rect.height >= 8 else { return nil }
        return Self(display: display, rect: rect)
    }

    /// ScreenCaptureKit expects display-local top-left coordinates.
    var sourceRect: CGRect {
        CGRect(x: rect.minX - display.frame.minX, y: display.frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    func pixelSize(scale: CGFloat) -> CGSize {
        let factor = min(max(1, scale), 3200 / max(rect.width, rect.height))
        return CGSize(width: max(2, floor(rect.width * factor)), height: max(2, floor(rect.height * factor)))
    }
}

enum POCScreenCapture {
    static func capture(_ region: POCScanRegion) async throws -> POCImage {
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == region.display.id }) else {
            throw ImagePOCError.message("선택한 화면을 찾지 못했습니다. 영역을 다시 골라 주세요.")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let size = region.pixelSize(scale: CGFloat(filter.pointPixelScale))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        // No stream, full-screen snapshot, image file, or clipboard write: capture only the confirmed rectangle once.
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return POCImage(pixels: image, name: "선택한 화면 영역")
    }

}

@MainActor final class POCSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws only a translucent selection UI. It does not read the pixels underneath it.
@MainActor final class POCSelectionView: NSView {
    let display: POCScanDisplay
    var onSelection: ((POCScanRegion?) -> Void)?
    private var start: CGPoint?
    private var end: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(display: POCScanDisplay) {
        self.display = display
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        setAccessibilityLabel("화면 영역 선택. 글과 이미지를 함께 감싸도록 드래그하세요. Escape로 취소합니다.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSelection?(nil) }
    }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil); end = start; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { return }
        end = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        let origin = display.frame.origin
        let selected = POCScanRegion.selected(from: CGPoint(x: start.x + origin.x, y: start.y + origin.y),
                                               to: CGPoint(x: end.x + origin.x, y: end.y + origin.y), on: display)
        if let selected { onSelection?(selected) }
        else { self.start = nil; self.end = nil; needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: 0.25).setFill(); bounds.fill()
        if let start, let end {
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            NSColor.clear.setFill(); rect.fill(using: .copy)
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect); outline.lineWidth = 2; outline.stroke()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        ("번역할 글과 이미지를 함께 감싸세요 · 드래그 후 놓기 · Esc 취소" as NSString)
            .draw(in: CGRect(x: 20, y: bounds.height - 72, width: max(1, bounds.width - 40), height: 40),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }
}

@MainActor final class POCRegionPicker {
    private var panels: [POCSelectionPanel] = []
    private var hiddenWindows: [NSWindow] = []
    private var continuation: CheckedContinuation<POCScanRegion, Error>?

    func pick() async throws -> POCScanRegion {
        guard continuation == nil else { throw ImagePOCError.message("이미 화면 영역을 고르는 중입니다.") }
        hiddenWindows = NSApp.windows.filter(\.isVisible)
        hiddenWindows.forEach { $0.orderOut(nil) }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let display = POCScanDisplay(id: number.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
                let panel = POCSelectionPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
                panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                let view = POCSelectionView(display: display)
                view.onSelection = { [weak self] region in self?.finish(region) }
                panel.contentView = view
                panels.append(panel)
                panel.orderFrontRegardless()
                panel.makeFirstResponder(view)
            }
            guard !panels.isEmpty else { finish(nil); return }
            NSApp.activate(ignoringOtherApps: true)
            let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels[0]
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func cancel() { finish(nil); restoreWindows() }
    func restoreWindows() {
        let windows = hiddenWindows; hiddenWindows = []
        windows.forEach { $0.orderFront(nil) }
    }
    private func finish(_ region: POCScanRegion?) {
        panels.forEach { $0.orderOut(nil); $0.close() }; panels = []
        let pending = continuation; continuation = nil
        if let region { pending?.resume(returning: region) }
        else { pending?.resume(throwing: CancellationError()) }
    }
}

@MainActor @Observable final class POCScreenScanner {
    var permissionAllowed = CGPreflightScreenCaptureAccess()
    var busy = false
    var message: String?
    private(set) var lastRegion: POCScanRegion?
    @ObservationIgnored private let picker = POCRegionPicker()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func refreshPermission() { permissionAllowed = CGPreflightScreenCaptureAccess() }
    func openPermissionSettings() {
        _ = CGRequestScreenCaptureAccess()
        refreshPermission()
        if !permissionAllowed {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        message = "화면 기록에서 ‘deepK Rich POC’를 허용한 뒤 돌아와 화면 스캔을 다시 누르세요. 필요하면 POC를 다시 열어 주세요."
    }
    func showAppLocation() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }

    func start(repeatLast: Bool = false, onImage: @escaping @MainActor (POCImage) -> Void) {
        guard !busy else { return }
        refreshPermission()
        guard permissionAllowed else {
            message = "화면 스캔에는 화면 기록 권한이 필요합니다. ‘화면 기록 허용’을 눌러 설정해 주세요. ⌘C 두 번 권한과는 별개입니다."
            return
        }
        if repeatLast {
            guard let region = lastRegion, NSScreen.screens.contains(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.display.id && $0.frame == region.display.frame
            }) else { lastRegion = nil; message = "화면 배치가 바뀌었습니다. 영역을 다시 골라 주세요."; return }
        }
        generation = UUID(); let token = generation
        busy = true; message = "이미지와 글이 있는 영역을 드래그해 주세요. Esc로 취소할 수 있습니다."
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.picker.restoreWindows()
                if self.generation == token { self.busy = false; self.task = nil }
            }
            do {
                let region: POCScanRegion
                if repeatLast, let previous = self.lastRegion { region = previous }
                else { region = try await self.picker.pick() }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.message = "선택한 화면을 읽는 중…"
                let image = try await POCScreenCapture.capture(region)
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.lastRegion = region
                self.message = "선택한 화면을 가져왔습니다. 원본과 번역을 전환해 확인하세요."
                self.picker.restoreWindows()
                onImage(image)
            } catch is CancellationError {
                if self.generation == token { self.message = "화면 선택을 취소했습니다." }
            } catch {
                guard self.generation == token else { return }
                self.refreshPermission()
                self.message = "화면을 읽지 못했습니다. 화면 기록 권한을 확인하거나 다른 화면 영역에서 다시 시도해 주세요."
            }
        }
    }

    func clear() {
        generation = UUID(); task?.cancel(); task = nil
        picker.cancel(); lastRegion = nil; busy = false; message = nil
    }
}
#endif
