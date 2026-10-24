import Foundation
final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<String, Error>?
    private var time: UInt64?
    func install(_ task: Task<String, Error>) { lock.lock(); self.task = task; lock.unlock() }
    func cancel() { lock.lock(); time = DispatchTime.now().uptimeNanoseconds; let task = self.task; lock.unlock(); task?.cancel() }
    func cancelledAt() -> UInt64? { lock.lock(); defer { lock.unlock() }; return time }
}
@main enum BoundaryProbe {
    static func marker(_ file: URL, limit: Int = 1000) async -> Bool {
        for _ in 0..<limit {
            if FileManager.default.fileExists(atPath: file.path) { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }
    static func ms(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000 }
    static func main() async {
        let kind = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "pending"
        var reports: [[String: Any]] = []
        for index in 1...3 {
            let root = FileManager.default.temporaryDirectory
            let tag = UUID().uuidString
            let started = root.appendingPathComponent("ready-"+tag)
            let release = root.appendingPathComponent("release-"+tag)
            let interrupted = root.appendingPathComponent("interrupt-"+tag)
            let calls = root.appendingPathComponent("calls-"+tag)
            let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("DeepKTests/Fixtures/codex-fake-server.py")
            var env = ["DEEPK_INTERRUPT_MARKER": interrupted.path, "DEEPK_CALL_COUNT_FILE": calls.path]
            if kind == "pending" { env["DEEPK_TURN_START_MARKER"] = started.path; env["DEEPK_TURN_START_RELEASE"] = release.path }
            let client = CodexTranslationClient(configuration: .init(executableURL: fixture, arguments: [kind == "pending" ? "cancel-start-gated" : "cancel"], environment: env, requestTimeout: 2, translationTimeout: 5))
            let box = CancelBox()
            #if HANDOFF_PROBE
            if kind == "handoff" { await client.setTurnResponseTestHook { box.cancel() } }
            #endif
            let task = Task { try await client.translate(text: "Hello", source: "en", target: "ko", model: "fixture-model") }
            box.install(task)
            if kind == "pending" { guard await marker(started) else { fatalError("no gated turn") } }
            let cancelledAt = DispatchTime.now().uptimeNanoseconds
            if kind == "pending" { box.cancel() }
            var cancellation = false
            do { _ = try await task.value } catch is CancellationError { cancellation = true } catch {}
            let caller = ms(box.cancelledAt() ?? cancelledAt)
            let releasedAt = DispatchTime.now().uptimeNanoseconds
            if kind == "pending" { try! Data("release".utf8).write(to: release) }
            let observed = await marker(interrupted)
            let wait = ms(releasedAt)
            let log = (try? String(contentsOf: calls, encoding: .utf8)) ?? ""
            reports.append(["case": kind, "run": index, "cancellationError": cancellation, "callerReturnMilliseconds": caller, "interruptObserved": observed, "releaseToInterruptObservedMilliseconds": observed ? wait : NSNull(), "observationWindowMilliseconds": wait, "calls": log])
            await client.disconnect()
        }
        let data = try! JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
