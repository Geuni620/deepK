import AppKit
import SwiftUI

/// 실제 권한 팝오버를 같은 실패 상태로 그린다. OS 권한 허용이나 단축키 성공의 증거가 아니다.
@main
@MainActor
enum PermissionRecoverySnapshot {
    static func main() throws {
        _ = NSApplication.shared
        let app = AppModel.shared
        app.shortcutEnabled = true
        app.shortcutReady = false
        app.inputMonitoringAllowed = false
        app.accessibilityReady = false

        let view = FinalSettingsView().permissionPopover
            .background(Color(nsColor: .windowBackgroundColor))
            .foregroundStyle(Color(nsColor: .labelColor))
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(x: -12000, y: -12000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Native SwiftUI permission snapshot: \(Int(size.width))×\(Int(size.height)), disconnected fixture")
    }
}
