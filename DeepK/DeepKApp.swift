import AppKit

/// AppKit이 백그라운드 실행을 관리하고, SwiftUI 화면은 필요할 때만 생성한다.
@main
@MainActor
enum DeepKApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = DeepKApplicationDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class DeepKApplicationDelegate: NSObject, NSApplicationDelegate {
    private var terminating = false
    private var terminationReplied = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()
        AppModel.shared.start()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.showSettings = false
        // 설정 시트를 먼저 닫아 종료 대기 중에도 메인 액터의 정리가 진행되게 한다.
        for window in sender.windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
                sheet.orderOut(nil)
            }
        }
        guard !terminating else { return .terminateLater }
        terminating = true
        Task { @MainActor in
            await AppModel.shared.shutdown()
            finishTermination(sender)
        }
        // 외부 CLI 정리가 지연돼도 앱 종료가 무기한 멈추지 않게 한다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            finishTermination(sender)
        }
        return .terminateLater
    }

    private func finishTermination(_ sender: NSApplication) {
        guard !terminationReplied else { return }
        terminationReplied = true
        sender.reply(toApplicationShouldTerminate: true)
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationItem.submenu = applicationMenu
        let settings = NSMenuItem(title: "설정…", action: #selector(AppModel.openSettings), keyEquivalent: ",")
        settings.target = AppModel.shared
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(NSMenuItem(title: "deepK 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "파일")
        fileItem.submenu = fileMenu
        let closeWindow = NSMenuItem(title: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindow.keyEquivalentModifierMask = .command
        fileMenu.addItem(closeWindow)
        main.addItem(fileItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "보기")
        viewItem.submenu = viewMenu
        let size = NSMenuItem(title: "창 크기 전환", action: #selector(AppModel.toggleWindowSize), keyEquivalent: "e")
        size.keyEquivalentModifierMask = [.command, .shift]
        size.target = AppModel.shared
        viewMenu.addItem(size)
        main.addItem(viewItem)


        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        editItem.submenu = edit
        for (title, action, key) in [
            ("실행 취소", NSSelectorFromString("undo:"), "z"),
            ("잘라내기", #selector(NSText.cut(_:)), "x"),
            ("복사", #selector(NSText.copy(_:)), "c"),
            ("붙여넣기", #selector(NSText.paste(_:)), "v"),
            ("전체 선택", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        // ⌘↩: 번역 창이 key이면 포커스와 상관없이 원문 끝에 `---` 경계를 덧붙인다.
        edit.addItem(.separator())
        edit.addItem(AppModel.shared.sourceEditor.makeMenuItem())
        // ⌘L: 번역이 끝났을 때 옆 창에서 그 번역에 대해 묻는다.
        if AppModel.shared.followUpEnabled {
            let ask = NSMenuItem(title: "번역에 대해 묻기", action: #selector(AppModel.openFollowUpFromMenu), keyEquivalent: "l")
            ask.target = AppModel.shared
            edit.addItem(ask)
        }
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
