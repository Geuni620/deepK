import AppKit
import ApplicationServices

enum PermissionGuideKind {
    case inputMonitoring
    case accessibility

    var title: String {
        switch self {
        case .inputMonitoring: "입력 모니터링"
        case .accessibility: "손쉬운 사용"
        }
    }

    var settingsURL: URL {
        switch self {
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }

    /// 현재 프로세스의 허용 여부. 시스템 설정 스위치를 켜면 바뀐다.
    var isGranted: Bool {
        switch self {
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }
}

/// 시스템 설정의 권한 화면을 열고, 설정 창 아래에 앱 아이콘을 끌어다 놓는 안내 창을 붙인다.
/// 권한이 허용되거나 설정 창이 닫히면 안내를 끝낸다.
@MainActor
final class PermissionGuideController {
    private static let settingsBundleIdentifier = "com.apple.systempreferences"
    private static let panelSize = CGSize(width: 340, height: 142)
    /// 설정 창이 한 번도 보이지 않으면 이 시간 뒤에 안내를 끝낸다.
    private static let settingsAppearTimeout: TimeInterval = 15

    private var panel: NSPanel?
    private var timer: Timer?
    private var kind: PermissionGuideKind?
    private var onGranted: ((PermissionGuideKind) -> Void)?
    private var startedAt = Date.distantPast
    private var sawSettingsWindow = false

    func present(_ kind: PermissionGuideKind, onGranted: @escaping (PermissionGuideKind) -> Void) {
        dismiss()
        self.kind = kind
        self.onGranted = onGranted
        startedAt = Date()
        sawSettingsWindow = false
        panel = makePanel(for: kind)
        NSWorkspace.shared.open(kind.settingsURL)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        kind = nil
        onGranted = nil
    }

    private func tick() {
        guard let kind, let panel else { return }
        if kind.isGranted {
            let callback = onGranted
            dismiss()
            callback?(kind)
            return
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleIdentifier).first != nil
        else {
            if sawSettingsWindow || Date().timeIntervalSince(startedAt) > Self.settingsAppearTimeout { dismiss() }
            return
        }
        guard let settingsFrame = Self.frontmostSettingsWindowFrame() else {
            // 다른 앱으로 옮겨 가면 안내만 숨기고, 설정으로 돌아오면 다시 보인다.
            panel.orderOut(nil)
            if !sawSettingsWindow, Date().timeIntervalSince(startedAt) > Self.settingsAppearTimeout { dismiss() }
            return
        }
        sawSettingsWindow = true
        let center = CGPoint(x: settingsFrame.midX, y: settingsFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        let target = PermissionGuideLayout.panelFrame(
            size: Self.panelSize,
            settingsFrame: settingsFrame,
            visibleFrame: screen?.visibleFrame ?? settingsFrame
        )
        if panel.frame != target { panel.setFrame(target, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// 앞에 있는 시스템 설정 창의 AppKit 좌표. 창 경계는 화면 기록 권한 없이 조회된다.
    private static func frontmostSettingsWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == settingsBundleIdentifier,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryScreen = NSScreen.screens.first
        else { return nil }
        let windows = info.compactMap { window -> (layer: Int, bounds: CGRect)? in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return nil }
            return (layer, bounds)
        }
        guard let bounds = PermissionGuideLayout.mainWindowBounds(windows) else { return nil }
        return PermissionGuideLayout.appKitFrame(fromWindowBounds: bounds, primaryScreenHeight: primaryScreen.frame.height)
    }

    private func makePanel(for kind: PermissionGuideKind) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = PermissionGuideView(kind: kind) { [weak self] in self?.dismiss() }
        return panel
    }
}

/// 안내 문구, 끌어 놓을 앱 아이콘, 닫기 버튼.
private final class PermissionGuideView: NSVisualEffectView {
    private let onClose: () -> Void

    init(kind: PermissionGuideKind, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true

        let title = NSTextField(labelWithString: "deepK를 \(kind.title) 목록으로 끌어다 놓으세요")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "아래 아이콘을 시스템 설정 목록에 놓고 스위치를 켜 주세요. 목록에 이미 있으면 스위치만 켜면 됩니다.")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let dragSource = AppDragSourceView()
        let close = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "권한 안내 닫기")!,
            target: nil,
            action: nil
        )
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.target = self
        close.action = #selector(closeGuide)

        for view in [title, detail, dragSource, close] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dragSource.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 12),
            dragSource.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            dragSource.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dragSource.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func closeGuide() { onClose() }
}

/// 앱 번들의 파일 URL을 끌어 놓을 수 있는 행. 시스템 설정 권한 목록이 받아 앱을 추가한다.
private final class AppDragSourceView: NSView, NSDraggingSource {
    private let appURL = Bundle.main.bundleURL

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor

        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: appURL.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: FileManager.default.displayName(atPath: appURL.path))
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let hint = NSImageView(
            image: NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)!
        )
        hint.contentTintColor = .tertiaryLabelColor
        for view in [icon, name, hint] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityLabel("deepK 앱 아이콘. 시스템 설정 목록으로 끌어다 놓으세요")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: location.x - 24, y: location.y - 24, width: 48, height: 48), contents: image)
        beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
