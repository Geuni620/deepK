import AppKit
@main struct SessionSmoke {
 @MainActor static func main() {
  let identifier = ProcessInfo.processInfo.environment["DEEPK_SESSION_TEST_APP_IDENTIFIER"] ?? "com.deepk.app.dev"
  guard ["com.deepk.app.dev", "com.deepk.app"].contains(identifier) else { print("Unsupported session test app identifier"); exit(2) }
  if CommandLine.arguments.contains("--print-target") { print(identifier); return }
  let app = NSApplication.shared
  Task { @MainActor in await run(identifier: identifier); exit(0) }
  app.run()
 }
 @MainActor static func run(identifier: String) async {
  guard let host = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "deepk-test-host" }) else { print("Fixture missing"); exit(1) }
  host.activate(options: [.activateAllWindows])
  try? await Task.sleep(for: .milliseconds(500))
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier else { print("Fixture activation failed"); exit(1) }
  let capture = InvocationSession.capture()
  switch capture {
  case .failure(let error): print("Capture failed: \(error)"); exit(1)
  case .success(let session):
   print("Captured fixture: \(session.application.name), readable value: \(session.capturedValue != nil)")
   print("Captured original selection: \(session.selectedText == "Please keep the original window open.")")
   guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first else { print("Launch \(identifier) before this integration test"); exit(1) }
   app.activate(options: [.activateAllWindows])
   try? await Task.sleep(for:.milliseconds(250))
   guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { print("deepK activation failed"); exit(1) }
   guard session.selectedText == "Please keep the original window open." else { exit(1) }
   guard case .success = await session.restoreFocus() else { print("Restore failed"); exit(1) }
   guard case .success(let receipt) = session.insert("원래 창을 열어 두세요.") else { print("Insertion failed"); exit(1) }
   guard receipt.resultingValue == "원래 창을 열어 두세요." else { exit(1) }
   guard case .failure = session.insert("duplicate") else { print("Duplicate insertion allowed"); exit(1) }
   print("PASS: capture, restore, verified insertion and duplicate rejection")
  }
 }
}
