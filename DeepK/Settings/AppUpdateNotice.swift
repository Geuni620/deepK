import AppKit
import SwiftUI

/// A nonactivating update notice does not take focus from the text being read.
@MainActor
final class AppUpdateNotice: NSObject, NSWindowDelegate {
    /// The notice has a fixed width; its height always comes from the content.
    static let contentWidth: CGFloat = 340

    private var panel: NSPanel?

    @discardableResult
    func present(_ release: AppRelease, currentVersion: AppVersion, near anchor: CGRect?) -> Bool {
        dismiss()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 120),
                            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // The title stays for VoiceOver and Mission Control; the heading inside says the same thing.
        panel.title = DKLocalized("deepK 업데이트")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .aqua)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let hostingView = NSHostingView(rootView: AppUpdateNoticeView(release: release, currentVersion: currentVersion,
            onLater: { [weak self] in self?.dismiss() },
            onOpen: { [weak self] in
                self?.dismiss()
                NSWorkspace.shared.open(release.pageURL)
            }))
        // The default options also push SwiftUI's minimum size onto the window. That minimum is measured at a
        // narrow width, so wrapped text made the old panel 500-800pt tall. Report only the content's own size,
        // and pin the window to it.
        hostingView.sizingOptions = [.intrinsicContentSize]
        let size = hostingView.fittingSize
        panel.contentView = hostingView
        panel.setContentSize(size)
        panel.contentMinSize = size
        panel.contentMaxSize = size

        if let screen = anchor.flatMap({ frame in NSScreen.screens.first { $0.frame.intersects(frame) } }) ?? NSScreen.main {
            let bounds = screen.visibleFrame
            let desiredX = (anchor?.maxX ?? bounds.maxX) - panel.frame.width
            let x = min(max(desiredX, bounds.minX + 12), max(bounds.minX + 12, bounds.maxX - panel.frame.width - 12))
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: min(anchor?.minY ?? bounds.maxY, bounds.maxY) - 8))
        } else {
            panel.center()
        }
        self.panel = panel
        NSApp.unhideWithoutActivation()
        panel.orderFrontRegardless()
        return true
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    func windowWillClose(_ notification: Notification) { panel = nil }
}

private struct AppUpdateNoticeView: View {
    let release: AppRelease
    let currentVersion: AppVersion
    let onLater: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(DKLocalized("새 버전이 있습니다"))
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    versionChange
                    Text(DKLocalized("지금 업데이트하지 않아도 현재 버전으로 계속 사용할 수 있습니다."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Long labels stack instead of truncating; the height still follows the content.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    laterButton
                    openButton
                }
                VStack(alignment: .trailing, spacing: 8) {
                    openButton
                    laterButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .controlSize(.regular)
        }
        // Top inset clears the transparent title bar's close button.
        .padding(EdgeInsets(top: 30, leading: 18, bottom: 16, trailing: 18))
        .frame(width: AppUpdateNotice.contentWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .ignoresSafeArea()
    }

    private var laterButton: some View {
        Button(DKLocalized("계속 사용"), action: onLater)
            .keyboardShortcut(.cancelAction)
    }

    /// A nonactivating panel is rarely key, so AppKit draws this gray; order and label carry the emphasis.
    private var openButton: some View {
        Button(DKLocalized("업데이트 안내 열기"), action: onOpen)
            .buttonStyle(.borderedProminent)
    }

    /// Numbers only, so the row needs no translation; the localized sentence is read aloud instead.
    private var versionChange: some View {
        HStack(spacing: 6) {
            Text(currentVersion.description)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(release.version.description)
                .fontWeight(.semibold)
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DKFormat("deepK %1$@ 사용 가능 · 현재 %2$@", release.version, currentVersion))
    }
}
