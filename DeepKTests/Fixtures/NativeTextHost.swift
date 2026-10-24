import AppKit
import Darwin
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
 var window: NSWindow!
 private let runnerPID = getppid()
 private let startedAt = ProcessInfo.processInfo.systemUptime
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
 func applicationDidFinishLaunching(_ notification: Notification) {
  Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [runnerPID, startedAt] _ in
   if getppid() != runnerPID || ProcessInfo.processInfo.systemUptime - startedAt > 30 {
    MainActor.assumeIsolated { NSApp.terminate(nil) }
   }
  }
  let mainMenu = NSMenu()
  let applicationMenuItem = NSMenuItem()
  let applicationMenu = NSMenu()
  applicationMenuItem.submenu = applicationMenu
  applicationMenu.addItem(
   NSMenuItem(
    title: "Quit deepK verification fixture",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
   )
  )
  mainMenu.addItem(applicationMenuItem)

  let editMenuItem = NSMenuItem()
  let editMenu = NSMenu(title: "Edit")
  editMenuItem.submenu = editMenu
  let copyItem = NSMenuItem(
   title: "Copy",
   action: #selector(NSText.copy(_:)),
   keyEquivalent: "c"
  )
  copyItem.keyEquivalentModifierMask = [.command]
  editMenu.addItem(copyItem)
  mainMenu.addItem(editMenuItem)
  NSApp.mainMenu = mainMenu

  window=NSWindow(contentRect:NSRect(x:100,y:100,width:420,height:100),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
  window.title="deepK 수동 검증 · 30초 후 자동 종료"
  let view=NSTextView(frame:NSRect(x:12,y:12,width:396,height:76))
  view.isRichText=false
  view.string="Please keep the original window open."
  view.font = .systemFont(ofSize:18)
  view.setAccessibilityLabel("verification source")
  window.contentView?.addSubview(view)
  window.makeKeyAndOrderFront(nil)
  window.makeFirstResponder(view)
  view.setSelectedRange(NSRange(location:0,length:(view.string as NSString).length))
  NSApp.activate(ignoringOtherApps:true)
 }
}
guard ProcessInfo.processInfo.environment["DEEPK_RUN_GUI_TESTS"] == "1",
      CommandLine.arguments.contains("--verification-fixture"), getppid() > 1 else {
 fputs("This is a verification fixture, not the deepK app. Use the opt-in test runner.\n", stderr)
 exit(64)
}
let app=NSApplication.shared
let delegate=Delegate()
app.setActivationPolicy(.regular)
app.delegate=delegate
app.run()
