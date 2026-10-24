import AppKit
import Observation

@MainActor
@Observable
/// 창 표시 정책은 번역 상태와 분리하고 실제 리사이즈는 AppModel의 위임을 통해 받는다.
final class WindowPresentation {
    enum Preset: String, CaseIterable, Identifiable {
        case last
        case small
        case large

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .last: "마지막 크기"
            case .small: "항상 작게"
            case .large: "항상 크게"
            }
        }
    }

    typealias OpeningPreference = Preset

    enum SizeMode: Equatable {
        case small
        case large
        case custom

        var displayName: String {
            switch self {
            case .small: "작게"
            case .large: "크게"
            case .custom: "사용자 크기"
            }
        }
    }

    static let smallSize = CGSize(width: 420, height: 296)
    static let largeSize = CGSize(width: 880, height: 600)
    static let expandedWidthThreshold: CGFloat = 720

    static let presetDefaultsKey = "deepK.windowPresentation.openPreset"
    static let lastSizeDefaultsKey = "deepK.windowPresentation.lastSize"

    var openPreset: Preset {
        didSet {
            defaults.set(openPreset.rawValue, forKey: Self.presetDefaultsKey)
        }
    }

    var openingPreference: OpeningPreference {
        get { openPreset }
        set { setOpeningPreference(newValue) }
    }

    private(set) var lastSize: CGSize

    private(set) var currentFrame: NSRect?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reduceMotion: () -> Bool
    @ObservationIgnored private weak var window: NSWindow?

    init(
        defaults: UserDefaults = .standard,
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.defaults = defaults
        self.reduceMotion = reduceMotion
        self.openPreset = Self.loadPreset(from: defaults)
        self.lastSize = Self.loadSize(from: defaults) ?? Self.smallSize
    }

    convenience init(
        userDefaults: UserDefaults,
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.init(defaults: userDefaults, reduceMotion: reduceMotion)
    }

    var smallWindowSize: CGSize { Self.smallSize }
    var largeWindowSize: CGSize { Self.largeSize }

    var openingSize: CGSize {
        switch openPreset {
        case .last: lastSize
        case .small: Self.smallSize
        case .large: Self.largeSize
        }
    }

    var currentSize: CGSize {
        currentFrame?.size ?? window?.frame.size ?? Self.smallSize
    }

    var sizeMode: SizeMode { Self.sizeMode(for: currentSize) }
    var displayName: String { sizeMode.displayName }
    var currentSizeLabel: String { displayName }
    var isExpanded: Bool { Self.isExpanded(width: currentSize.width) }

    func attach(_ window: NSWindow) {
        self.window = window
        currentFrame = window.frame
    }

    @discardableResult
    func applyOnOpen() -> CGSize {
        let size = openingSize
        guard let window else { return size }
        resize(window, to: size)
        return size
    }

    @discardableResult
    func preview() -> CGSize {
        currentFrame?.size ?? window?.frame.size ?? Self.smallSize
    }

    @discardableResult
    func toggleSize() -> CGSize {
        let next = isExpanded ? Self.smallSize : Self.largeSize
        if let window {
            resize(window, to: next)
        } else {
            recordSize(next, frame: frame(for: next, basedOn: currentFrame))
        }
        return next
    }

    func setCurrentSize(_ mode: SizeMode) {
        guard mode != .custom else { return }
        let next = mode == .small ? Self.smallSize : Self.largeSize
        if let window { resize(window, to: next) }
        else { recordSize(next, frame: frame(for: next, basedOn: currentFrame)) }
    }

    func setPreset(_ preset: Preset) {
        openPreset = preset
    }

    func setOpeningPreference(_ preference: OpeningPreference) {
        setPreset(preference)
    }

    func didResize(_ window: NSWindow) {
        guard self.window === window else {
            return
        }
        let visibleFrame = window.screen?.visibleFrame
        didResize(window.frame, visibleFrame: visibleFrame, applyingTo: window)
    }

    func didResize(_ frame: NSRect) {
        didResize(frame, visibleFrame: nil, applyingTo: nil)
    }

    func didResize(_ frame: NSRect, within visibleFrame: NSRect) {
        didResize(frame, visibleFrame: visibleFrame, applyingTo: nil)
    }

    static func isExpanded(width: CGFloat) -> Bool {
        width >= expandedWidthThreshold
    }

    static func sizeMode(for size: CGSize) -> SizeMode {
        if approximatelyEqual(size, Self.smallSize) { return .small }
        if approximatelyEqual(size, Self.largeSize) { return .large }
        return .custom
    }

    // AppKit 좌표의 아래쪽 원점 대신 창 왼쪽 위를 기준으로 화면 안에 맞춘다.
    static func clampedFrame(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        guard frame.width.isFinite, frame.height.isFinite,
              visibleFrame.width.isFinite, visibleFrame.height.isFinite,
              visibleFrame.width > 0, visibleFrame.height > 0 else {
            return frame
        }

        let width = min(max(frame.width, 0), visibleFrame.width)
        let height = min(max(frame.height, 0), visibleFrame.height)

        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let top = min(max(frame.maxY, visibleFrame.minY + height), visibleFrame.maxY)
        let y = top - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func didResize(
        _ frame: NSRect,
        visibleFrame: NSRect?,
        applyingTo window: NSWindow?
    ) {
        let clamped = visibleFrame.map { Self.clampedFrame(frame, within: $0) } ?? frame
        if let window, clamped != frame {
            window.setFrame(clamped, display: true)
        }
        guard clamped.width > 0, clamped.height > 0,
              clamped.width.isFinite, clamped.height.isFinite else { return }
        recordSize(clamped.size, frame: clamped)
    }

    private func resize(_ window: NSWindow, to size: CGSize) {
        guard size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else { return }
        let proposed = frame(for: size, basedOn: window.frame)
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        let target = visibleFrame.map { Self.clampedFrame(proposed, within: $0) } ?? proposed
        window.setFrame(target, display: true, animate: !reduceMotion())
        recordSize(target.size, frame: target)
    }

    private func frame(for size: CGSize, basedOn frame: NSRect?) -> NSRect {
        let base = frame ?? NSRect(origin: .zero, size: currentSize)
        return NSRect(x: base.minX, y: base.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func recordSize(_ size: CGSize, frame: NSRect?) {
        guard size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else { return }
        lastSize = size
        defaults.set([Double(size.width), Double(size.height)], forKey: Self.lastSizeDefaultsKey)
        currentFrame = frame ?? NSRect(origin: .zero, size: size)
    }

    private static func loadPreset(from defaults: UserDefaults) -> Preset {
        guard let raw = defaults.string(forKey: Self.presetDefaultsKey),
              let preset = Preset(rawValue: raw) else { return .last }
        return preset
    }

    private static func loadSize(from defaults: UserDefaults) -> CGSize? {
        guard let values = defaults.array(forKey: Self.lastSizeDefaultsKey),
              values.count == 2,
              let width = (values[0] as? NSNumber)?.doubleValue,
              let height = (values[1] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: max(width, Self.smallSize.width), height: max(height, Self.smallSize.height))
    }

    private static func approximatelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
    }
}


// An ordinary window activates on click and participates in normal window ordering.
// Unlike an auxiliary panel, it remains visible when another app becomes active.
final class TranslationPanel: NSWindow {
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.25 }
}
