import AppKit
import SwiftUI

/// A nonactivating update notice does not take focus from the text being read.
@MainActor
final class AppUpdateNotice: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    @discardableResult
    func present(_ release: AppRelease, currentVersion: AppVersion, near anchor: CGRect?) -> Bool {
        dismiss()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 168),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = DKLocalized("deepK 업데이트")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .aqua)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: AppUpdateNoticeView(release: release, currentVersion: currentVersion,
            onLater: { [weak self] in self?.dismiss() },
            onOpen: { [weak self] in
                self?.dismiss()
                NSWorkspace.shared.open(release.pageURL)
            }))
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
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text(DKLocalized("새 버전이 있습니다"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(DKFormat("deepK %1$@ 사용 가능 · 현재 %2$@", release.version, currentVersion))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Text(DKLocalized("지금 업데이트하지 않아도 현재 버전으로 계속 사용할 수 있습니다."))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(DKLocalized("계속 사용"), action: onLater)
                Spacer()
                Button(DKLocalized("업데이트 안내 열기"), action: onOpen)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
