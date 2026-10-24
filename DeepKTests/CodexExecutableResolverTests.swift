// 임시 디렉터리의 가짜 실행 파일만 실행한다. 실제 /Applications, ~/.nvm의 Codex나 Codex 서버를 쓰지 않는다.
import Foundation

private final class ProbeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []
    func record(_ timeout: TimeInterval) { lock.lock(); defer { lock.unlock() }; values.append(timeout) }
    func timeouts() -> [TimeInterval] { lock.lock(); defer { lock.unlock() }; return values }
}

private final class SlowProbeSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isOn: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ on: Bool) { lock.lock(); defer { lock.unlock() }; value = on }
}

private final class UserPathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func set(_ path: String?) { lock.lock(); defer { lock.unlock() }; value = path }
    func get() -> String? { lock.lock(); defer { lock.unlock() }; return value }
}

/// 테스트 하나가 쓰는 임시 루트다. 홈·설치 위치·PATH·앱 번들을 모두 이 아래에 만든다.
private struct ResolverSandbox {
    typealias Resolver = CodexTranslationClient.ExecutableResolver

    let root: URL
    var home: URL { root.appendingPathComponent("home", isDirectory: true) }
    var probeLog: URL { root.appendingPathComponent("probes.log") }

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("deepk-codex-resolver-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
    }

    func path(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    /// `--version`에 `codex-cli <version>`을 출력하는 가짜 Codex다. 호출할 때마다 probes.log에 경로를 남긴다.
    @discardableResult
    func makeCodex(_ relative: String, version: String?, versionOutput: String? = nil, otherwise: String = "exit 0") -> URL {
        let url = path(relative)
        let output = versionOutput ?? version.map { "codex-cli \($0)" } ?? ""
        write(url, """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "$0" >> '\(probeLog.path)'
          echo '\(output)'
          exit 0
        fi
        \(otherwise)
        """)
        return url
    }

    func write(_ url: URL, _ content: String, executable: Bool = true) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        if executable { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }

    func symlink(_ relative: String, to destination: String) {
        let url = path(relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    /// 앱 번들의 `codex-package.json` 배치를 만든다.
    func makeBundle(_ relative: String, version: String, layoutVersion: Int = 1) -> URL {
        let app = path(relative)
        let package = app.appendingPathComponent("Contents/Resources/codex-cli")
        write(package.appendingPathComponent("codex-package.json"), """
        {"layoutVersion": \(layoutVersion), "version": "\(version)", "entrypoint": "bin/codex", "resourcesDir": "codex-resources"}
        """, executable: false)
        makeCodex("\(relative)/Contents/Resources/codex-cli/bin/codex", version: version)
        return app
    }

    func inputs(
        installDirectories: [String] = [],
        environment: [String: String] = [:],
        userPath: (@Sendable () -> String?)? = nil,
        applications: [URL] = [],
        probeTimeout: TimeInterval = 3,
        retryTimeout: TimeInterval = 10,
        probe: (@Sendable (URL, TimeInterval) async -> Resolver.ProbeOutcome)? = nil
    ) -> Resolver.Inputs {
        // 가짜 실행 파일은 셸 내장 명령만 쓰므로 실제 PATH를 넘기지 않는다.
        let probeEnvironment = ["PATH": environment["PATH"] ?? ""]
        return Resolver.Inputs(
            homeDirectory: home.path,
            installDirectories: installDirectories.map { path($0).path },
            environment: environment,
            userExecutablePath: userPath ?? { nil },
            applicationURLs: { identifier in identifier == "com.openai.codex" ? applications : [] },
            probeVersion: probe ?? { executable, timeout in
                await Resolver.runVersionProbe(executable, environment: probeEnvironment, timeout: timeout)
            },
            probeTimeout: probeTimeout,
            retryTimeout: retryTimeout
        )
    }

    func probedPaths() -> [String] {
        ((try? String(contentsOf: probeLog, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).map(String.init)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

enum CodexExecutableResolverTests {
    typealias Resolver = CodexTranslationClient.ExecutableResolver
    typealias ClientError = CodexTranslationClient.ClientError

    static func runAll() async {
        print("Codex test: executable version parsing"); fflush(nil)
        versionParsingAndOrdering()
        print("Codex test: executable discovery order"); fflush(nil)
        await discoveryFollowsSourceOrder()
        await configuredPathNeverFallsBack()
        await minimumVersionAndHighestInGroup()
        await appBundleUsesPackageEntrypoint()
        await npmWrappersRunNativeBinary()
        print("Codex test: executable probe timeouts"); fflush(nil)
        await probeTimeoutsAreRetriedOnce()
        print("Codex test: executable cache and rediscovery"); fflush(nil)
        await immediateExitDoesNotRaiseSIGPIPE()
        await failedLaunchRediscoversAndCacheIsRevalidated()
        print("Codex test: executable discovery cancellation"); fflush(nil)
        await cancelledProbeDoesNotLaunch()
        await cancellationStopsDiscovery()
        await cancellationKeepsCachedExecutable()
        print("Codex test: overlapping connections share one start"); fflush(nil)
        await overlappingConnectionsShareOneStart()
    }

    private static func versionParsingAndOrdering() {
        func parse(_ output: String) -> Resolver.Version? { Resolver.Version(versionOutput: output) }
        require(parse("codex-cli 0.160.1\n")?.description == "0.160.1", "release version is parsed")
        require(parse("warning: something\ncodex-cli 0.161.0-alpha.2")?.description == "0.161.0-alpha.2", "prerelease version is parsed from any line")
        require(parse("codex-cli 0.160") == nil && parse("node: not found") == nil && parse("") == nil, "malformed output is rejected")
        require(parse("codex-cli 0.0.0")?.isSourceBuild == true, "0.0.0 is a source build")
        let alpha2 = Resolver.Version("0.161.0-alpha.2")!, alpha10 = Resolver.Version("0.161.0-alpha.10")!
        let beta = Resolver.Version("0.161.0-beta")!, release = Resolver.Version("0.161.0")!
        require(alpha2 < alpha10 && alpha10 < beta && beta < release, "prereleases sort below the same release")
        require(Resolver.Version("0.160.1")! < alpha2, "a prerelease of a newer version is still newer")
        require(Resolver.Version("0.155.0-rc.1")! < Resolver.minimumVersion, "a prerelease of the minimum is below the minimum")
        require(Resolver.minimumVersion.description == CodexTranslationClient.minimumCodexVersion, "minimum version constant parses")
        require(Resolver.testedVersion.description == CodexTranslationClient.testedCodexVersion, "tested version constant parses")
        require(Resolver.displayPath("/Users/me/.nvm/codex", home: "/Users/me") == "~/.nvm/codex", "home is abbreviated")
        require(Resolver.displayPath("/Users/meme/codex", home: "/Users/me") == "/Users/meme/codex", "only the home directory prefix is abbreviated")
    }

    private static func discoveryFollowsSourceOrder() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        box.makeCodex("home/custom/codex", version: "0.157.0")
        box.makeCodex("env/codex", version: "0.158.0")
        box.makeCodex("opt/bin/codex", version: "0.156.0")
        box.makeCodex("pathdir/codex", version: "0.159.0")
        let app = box.makeBundle("Apps/ChatGPT.app", version: "0.161.0")
        let fullEnvironment = ["CODEX_EXECUTABLE": box.path("env/codex").path, "PATH": "relative/bin:\(box.path("pathdir").path)"]
        let user: @Sendable () -> String? = { "~/custom/codex" }

        let userResolution = await resolve(box.inputs(installDirectories: ["opt/bin"], environment: fullEnvironment, userPath: user, applications: [app]))
        require(userResolution?.source == .userSpecified && userResolution?.version.description == "0.157.0", "the configured path wins over every other source")
        if let userResolution {
            let info = Resolver(inputs: box.inputs()).info(for: userResolution)
            require(info.displayPath == "~/custom/codex" && info.version == "0.157.0" && !info.isNewerThanTested, "info abbreviates home and reports the version")
        }

        let environmentResolution = await resolve(box.inputs(installDirectories: ["opt/bin"], environment: fullEnvironment, applications: [app]))
        require(environmentResolution?.source == .environment, "CODEX_EXECUTABLE is next")

        var noVariable = fullEnvironment
        noVariable["CODEX_EXECUTABLE"] = nil
        let installResolution = await resolve(box.inputs(installDirectories: ["opt/bin"], environment: noVariable, applications: [app]))
        require(installResolution?.source == .installLocation && installResolution?.version.description == "0.156.0",
                "install locations come before PATH even when PATH has a newer version")

        let pathResolution = await resolve(box.inputs(environment: noVariable, applications: [app]))
        require(pathResolution?.source == .pathDirectory && pathResolution?.entrypoint.path == box.path("pathdir/codex").path,
                "PATH directories are scanned directly without /usr/bin/env")

        let bundleResolution = await resolve(box.inputs(environment: ["PATH": ""], applications: [app]))
        require(bundleResolution?.source == .appBundle, "the app bundle is the last source")
        if let bundleResolution {
            let info = Resolver(inputs: box.inputs()).info(for: bundleResolution)
            require(info.isNewerThanTested, "versions above the tested range are selected and flagged")
        }

        await expectError(box.inputs(environment: ["PATH": ""]), "no candidate reports not found") { $0 == .executableNotFound }
    }

    private static func configuredPathNeverFallsBack() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        box.makeCodex("opt/bin/codex", version: "0.160.1")
        box.makeCodex("old/codex", version: "0.142.5")
        box.makeCodex("garbage/codex", version: nil, versionOutput: "not codex")
        box.makeCodex("source/codex", version: "0.0.0")
        box.makeCodex("autosource/codex", version: "0.0.0")
        let installs = ["opt/bin"]
        for (path, label) in [
            (box.path("missing/codex").path, "missing file"),
            (box.path("old/codex").path, "old version"),
            (box.path("garbage/codex").path, "unparsable version"),
            ("codex", "relative path")
        ] {
            await expectError(box.inputs(installDirectories: installs, userPath: { path }), "configured \(label) does not fall back") {
                if case .configuredExecutableInvalid = $0 { return true }
                return false
            }
        }
        let source = await resolve(box.inputs(installDirectories: installs, userPath: { box.path("source/codex").path }))
        require(source?.source == .userSpecified && source?.version.isSourceBuild == true, "0.0.0 is allowed for a configured path")
        let blank = await resolve(box.inputs(installDirectories: installs, userPath: { "  " }))
        require(blank?.source == .installLocation, "a blank configured path means automatic discovery")
        await expectError(box.inputs(installDirectories: ["autosource"]), "automatic discovery rejects 0.0.0") {
            if case .executableUnsupported = $0 { return true }
            return false
        }
    }

    private static func minimumVersionAndHighestInGroup() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        box.makeCodex("old/codex", version: "0.142.5")
        box.makeCodex("pathdir/codex", version: "0.156.0")
        let below = await resolve(box.inputs(installDirectories: ["old"], environment: ["PATH": box.path("pathdir").path]))
        require(below?.source == .pathDirectory, "a candidate below the minimum is skipped for the next source")

        box.makeCodex("older/codex", version: "0.150.0")
        await expectError(box.inputs(installDirectories: ["old"], environment: ["PATH": box.path("older").path]),
                          "the highest candidate below the minimum is reported") {
            $0 == .executableUnsupported("\(box.path("older/codex").path) 0.150.0")
        }

        for (node, version) in [("v18.0.0", "0.157.0"), ("v20.11.1", "0.136.0"), ("v22.0.0", "0.142.5"), ("v24.18.0", "0.160.1"), ("v25.0.0", "0.162.0-alpha.1")] {
            box.makeCodex("home/.nvm/versions/node/\(node)/bin/codex", version: version)
        }
        box.makeCodex("home/.local/bin/codex", version: "0.158.0")
        let nvm = await resolve(box.inputs())
        require(nvm?.source == .installLocation && nvm?.version.description == "0.160.1"
                    && nvm?.entrypoint.path.contains("v24.18.0") == true,
                "the highest release among every nvm version and home install wins")

        box.makeCodex("custom-nvm/versions/node/v26.0.0/bin/codex", version: "0.159.0")
        try? FileManager.default.removeItem(at: box.path("home/.local"))
        let custom = await resolve(box.inputs(environment: ["NVM_DIR": box.path("custom-nvm").path]))
        require(custom?.version.description == "0.159.0", "NVM_DIR replaces ~/.nvm")

        box.makeCodex("pre/codex", version: "0.163.0-beta.1")
        let prereleaseOnly = await resolve(box.inputs(installDirectories: ["pre"], environment: ["NVM_DIR": box.path("none").path]))
        require(prereleaseOnly?.version.description == "0.163.0-beta.1", "a prerelease is used when no release is available")
    }

    private static func appBundleUsesPackageEntrypoint() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        let current = box.makeBundle("Apps/ChatGPT.app", version: "0.160.1")
        let older = box.makeBundle("Old/ChatGPT.app", version: "0.156.0")
        let resolution = await resolve(box.inputs(environment: ["PATH": ""], applications: [older, current]))
        require(resolution?.entrypoint.path == current.appendingPathComponent("Contents/Resources/codex-cli/bin/codex").path,
                "codex-package.json entrypoint is executed as-is and the highest bundle wins")

        let legacy = box.path("Legacy/ChatGPT.app")
        box.makeCodex("Legacy/ChatGPT.app/Contents/Resources/codex", version: "0.155.0")
        let legacyResolution = await resolve(box.inputs(environment: ["PATH": ""], applications: [legacy]))
        require(legacyResolution?.entrypoint.path == legacy.appendingPathComponent("Contents/Resources/codex").path,
                "the previous Contents/Resources/codex layout is the fallback")

        let future = box.makeBundle("Future/ChatGPT.app", version: "0.170.0", layoutVersion: 2)
        await expectError(box.inputs(environment: ["PATH": ""], applications: [future]), "unknown package layouts are ignored") {
            $0 == .executableNotFound
        }
    }

    private static func npmWrappersRunNativeBinary() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        #if arch(arm64)
        let platformPackage = "codex-darwin-arm64", triple = "aarch64-apple-darwin"
        #else
        let platformPackage = "codex-darwin-x64", triple = "x86_64-apple-darwin"
        #endif
        // codex.js는 Node가 없는 앱 PATH에서처럼 실패하게 둔다. 네이티브 바이너리로 바뀌어야만 통과한다.
        let failingWrapper = "#!/bin/sh\nexit 127\n"
        for prefix in ["nested", "hoisted", "bare"] {
            box.write(box.path("\(prefix)/lib/node_modules/@openai/codex/bin/codex.js"), failingWrapper)
            box.symlink("\(prefix)/bin/codex", to: "../lib/node_modules/@openai/codex/bin/codex.js")
        }
        let nested = box.makeCodex("nested/lib/node_modules/@openai/codex/node_modules/@openai/\(platformPackage)/vendor/\(triple)/bin/codex", version: "0.160.1")
        let hoisted = box.makeCodex("hoisted/lib/node_modules/@openai/\(platformPackage)/vendor/\(triple)/bin/codex", version: "0.157.0")

        require(Resolver.nativeExecutable(at: box.path("nested/bin/codex")).path == nested.path, "nested npm layout resolves to the vendor binary")
        require(Resolver.nativeExecutable(at: box.path("hoisted/bin/codex")).path == hoisted.path, "hoisted npm layout resolves to the vendor binary")
        require(Resolver.nativeExecutable(at: box.path("bare/bin/codex")).path == box.path("bare/bin/codex").path, "a wrapper without a binary stays unchanged")

        let resolution = await resolve(box.inputs(installDirectories: ["bare/bin", "hoisted/bin", "nested/bin"]))
        require(resolution?.executable.path == nested.path && resolution?.entrypoint.path == box.path("nested/bin/codex").path,
                "the native binary runs while the wrapper path is shown")
        if let resolution {
            let info = Resolver(inputs: box.inputs()).info(for: resolution)
            require(info.path == nested.path && info.displayPath == box.path("nested/bin/codex").path, "info separates executed and shown paths")
        }
        await expectError(box.inputs(installDirectories: ["bare/bin"]), "a wrapper that needs Node is not selected") { $0 == .executableNotFound }
    }

    private static func probeTimeoutsAreRetriedOnce() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        box.makeCodex("slow/codex", version: "0.160.1")
        let recorder = ProbeRecorder()
        let slowOnce = await resolve(box.inputs(installDirectories: ["slow"], probeTimeout: 3, retryTimeout: 10, probe: { _, timeout in
            recorder.record(timeout)
            return timeout < 10 ? .timedOut : .output("codex-cli 0.160.1")
        }))
        require(slowOnce?.version.description == "0.160.1" && recorder.timeouts() == [3, 10], "a timed-out probe is retried once with a longer limit")

        let alwaysSlow = ProbeRecorder()
        await expectError(box.inputs(installDirectories: ["slow"], probe: { _, timeout in
            alwaysSlow.record(timeout)
            return .timedOut
        }), "a candidate that keeps timing out is not selected") { $0 == .executableNotFound }
        require(alwaysSlow.timeouts().count == 2, "timeouts are retried only once")

        let versionRecorder = ProbeRecorder()
        await expectError(box.inputs(installDirectories: ["slow"], probe: { _, timeout in
            versionRecorder.record(timeout)
            return .output("codex-cli 0.150.0")
        }), "a version below the minimum is not retried") {
            if case .executableUnsupported = $0 { return true }
            return false
        }
        require(versionRecorder.timeouts().count == 1, "version failures are distinct from timeouts")

        // 실제 프로세스: 제한 시간을 넘기면 강제로 끝내고, 같은 단계의 다른 후보는 그대로 고른다.
        box.write(box.path("hang/codex"), "#!/bin/sh\n/bin/sleep 10\necho 'codex-cli 0.170.0'\n")
        let fast = box.makeCodex("fast/codex", version: "0.158.0")
        // 새로 만든 실행 파일의 첫 실행은 macOS 검사로 수백 ms 걸릴 수 있으므로 미리 한 번 실행한다.
        _ = await Resolver.runVersionProbe(fast, environment: [:], timeout: 5)
        let start = Date()
        let mixed = await resolve(box.inputs(installDirectories: ["hang", "fast"], probeTimeout: 0.5, retryTimeout: 1))
        let elapsed = Date().timeIntervalSince(start)
        require(mixed?.version.description == "0.158.0", "a hanging candidate does not block the others")
        require(elapsed >= 1.4 && elapsed < 5, "a hanging --version is stopped after the first limit and one longer retry (\(elapsed)s)")
    }

    private static func immediateExitDoesNotRaiseSIGPIPE() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        // initialize에만 응답하기 전에 stdin을 닫고 exit 127로 끝난다. 이어지는 initialized 알림 쓰기는 반드시 EPIPE가 된다.
        box.write(box.path("dead/codex"), #"""
        #!/bin/sh
        IFS= read -r line
        exec 0<&-
        id=$(printf '%s' "$line" | /usr/bin/sed 's/.*"id":"\([^"]*\)".*/\1/')
        printf '{"id":"%s","result":{}}\n' "$id"
        exit 127
        """#)
        let client = CodexTranslationClient(configuration: .init(executableURL: box.path("dead/codex"), arguments: ["app-server"], requestTimeout: 2))
        for _ in 0..<5 {
            do {
                try await client.connect()
                fail("an executable that exits immediately must not connect")
            } catch {
                // SIGPIPE가 났다면 이 테스트 프로세스가 여기까지 오지 못한다.
            }
        }
        let info = await client.executableInfo
        require(info?.source == .fixedConfiguration && info?.version == nil, "a fixed executable skips version checks")
    }

    private static func failedLaunchRediscoversAndCacheIsRevalidated() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("DeepKTests/Fixtures/codex-fake-server.py").path
        let server = "exec '\(fixture)' \"$@\""
        let primary = box.makeCodex("primary/codex", version: "0.160.1", otherwise: "exit 127")
        let backup = box.makeCodex("backup/codex", version: "0.156.0", otherwise: server)
        let userPath = UserPathBox()
        let client = CodexTranslationClient(
            configuration: .init(arguments: ["normal"], requestTimeout: 2),
            executableResolver: Resolver(inputs: box.inputs(installDirectories: ["primary", "backup"], userPath: { userPath.get() }))
        )
        func probes() -> (primary: Int, backup: Int) {
            let paths = box.probedPaths()
            return (paths.filter { $0 == primary.path }.count, paths.filter { $0 == backup.path }.count)
        }
        func connect(forceRefresh: Bool = false) async -> Bool {
            do { try await client.connect(forceRefresh: forceRefresh); return true } catch { return false }
        }

        require(!(await connect()), "exit 127 from app-server fails the connection")
        require(probes() == (1, 1), "first launch probes the whole group")
        require(await client.executableInfo?.displayPath == primary.path, "the attempted executable is still reported after failure")
        require(!(await connect()), "the broken executable still fails")
        require(probes() == (2, 2), "a failed launch drops the cache and rediscovers every candidate")

        box.makeCodex("primary/codex", version: "0.160.1", otherwise: server)
        require(await connect(), "the repaired executable connects")
        require(probes() == (3, 3), "rediscovery after failure")
        await client.disconnect()
        require(await connect(), "reconnect uses the cached executable")
        require(probes() == (4, 3), "a cached executable is re-probed without rediscovery")

        box.makeCodex("primary/codex", version: "0.161.0", otherwise: server)
        await client.disconnect()
        require(await connect(), "an updated cached executable still connects")
        let updated = await client.executableInfo
        require(updated?.version == "0.161.0" && updated?.isNewerThanTested == true && probes() == (5, 3), "a changed version updates the reported info")

        box.makeCodex("primary/codex", version: "0.150.0", otherwise: server)
        await client.disconnect()
        require(await connect(), "a downgraded cache falls back to rediscovery")
        let downgraded = await client.executableInfo
        require(downgraded?.displayPath == backup.path && downgraded?.version == "0.156.0" && probes() == (7, 4),
                "a cached executable below the minimum triggers full rediscovery")

        await client.disconnect()
        require(await connect(forceRefresh: true), "explicit connection check reconnects")
        require(probes() == (8, 5), "an explicit connection check rediscovers")

        userPath.set(primary.path)
        await client.disconnect()
        require(!(await connect()), "a configured path that is too old fails without fallback")
        require(await client.executableInfo == nil, "no executable is reported when the configured path is invalid")
        userPath.set(nil)
        require(await connect(), "clearing the configured path restores discovery")
        require(await client.executableInfo?.displayPath == backup.path, "discovery runs again after the configured path changes")
        await client.disconnect()
    }

    /// 이미 취소된 작업에서는 `--version` 프로세스를 띄우지 않는다.
    private static func cancelledProbeDoesNotLaunch() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        let codex = box.makeCodex("cancelled/codex", version: "0.160.1")
        let outcome = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Resolver.runVersionProbe(codex, environment: [:], timeout: 3)
        }.value
        require(outcome == .failed("cancelled"), "a cancelled probe reports cancellation (\(outcome))")
        try? await Task.sleep(nanoseconds: 200_000_000)
        require(box.probedPaths().isEmpty, "a probe on a cancelled task does not run --version")
    }

    /// 탐색 도중 취소되면 CancellationError로 멈추고, 남은 단계 후보를 실행하지 않는다.
    private static func cancellationStopsDiscovery() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        box.write(box.path("slow/codex"), "#!/bin/sh\n/bin/sleep 5\necho 'codex-cli 0.160.1'\n")
        let later = box.makeCodex("bin/codex", version: "0.160.1")
        let resolver = Resolver(inputs: box.inputs(installDirectories: ["slow"], environment: ["PATH": box.path("bin").path]))
        let task = Task { try await resolver.resolve() }
        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let start = Date()
        do {
            let resolution = try await task.value
            fail("a cancelled discovery resolved \(resolution.entrypoint.path)")
        } catch is CancellationError {
        } catch {
            fail("a cancelled discovery must throw CancellationError, not \(error)")
        }
        require(Date().timeIntervalSince(start) < 2, "cancellation stops the hanging probe promptly")
        try? await Task.sleep(nanoseconds: 200_000_000)
        require(!box.probedPaths().contains(later.path), "later stages are not probed after cancellation")

        let userPath = Resolver(inputs: box.inputs(userPath: { box.path("slow/codex").path }))
        let configured = Task { try await userPath.resolve() }
        try? await Task.sleep(nanoseconds: 150_000_000)
        configured.cancel()
        do {
            _ = try await configured.value
            fail("a cancelled configured path cannot resolve")
        } catch is CancellationError {
        } catch {
            fail("a cancelled configured path must not be reported as invalid: \(error)")
        }
    }

    /// 캐시 경로를 다시 확인하는 중에 연결이 끊겨도 정상인 캐시와 표시는 그대로 남는다.
    private static func cancellationKeepsCachedExecutable() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("DeepKTests/Fixtures/codex-fake-server.py").path
        let server = "exec '\(fixture)' \"$@\""
        let primary = box.makeCodex("primary/codex", version: "0.160.1", otherwise: server)
        let backup = box.makeCodex("backup/codex", version: "0.156.0", otherwise: server)
        let slow = SlowProbeSwitch()
        let probeEnvironment = ["PATH": ""]
        let inputs = box.inputs(installDirectories: ["primary", "backup"], probe: { executable, timeout in
            if slow.isOn { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            return await Resolver.runVersionProbe(executable, environment: probeEnvironment, timeout: timeout)
        })
        let client = CodexTranslationClient(
            configuration: .init(arguments: ["normal"], requestTimeout: 2),
            executableResolver: Resolver(inputs: inputs)
        )
        func count(_ url: URL) -> Int { box.probedPaths().filter { $0 == url.path }.count }

        do { try await client.connect() } catch { fail("initial discovery failed: \(error)") }
        require(count(primary) == 1 && count(backup) == 1, "first launch probes every candidate")
        let info = await client.executableInfo
        await client.disconnect()

        slow.set(true)
        let pending = Task { try await client.connect() }
        try? await Task.sleep(nanoseconds: 200_000_000)
        await client.disconnect()
        do {
            try await pending.value
            fail("a disconnected start cannot connect")
        } catch let error as CodexTranslationClient.ClientError {
            require(error == .notConnected, "a start cancelled by disconnect reports notConnected (\(error))")
        } catch {
            fail("unexpected error after disconnect during revalidation: \(error)")
        }
        require(await client.executableInfo == info, "cancellation keeps the reported executable")

        slow.set(false)
        do { try await client.connect() } catch { fail("reconnect after cancellation failed: \(error)") }
        require(count(primary) == 2 && count(backup) == 1, "the cached executable survives cancellation without rediscovery")
        await client.disconnect()
    }

    /// 탐색 중에 들어온 연결은 실패하지 않고 같은 시작을 기다린다. 기다리던 호출이 취소돼도 시작은 계속된다.
    private static func overlappingConnectionsShareOneStart() async {
        let box = ResolverSandbox()
        defer { box.remove() }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("DeepKTests/Fixtures/codex-fake-server.py").path
        let primary = box.makeCodex("primary/codex", version: "0.160.1", otherwise: "exec '\(fixture)' \"$@\"")
        let probeEnvironment = ["PATH": ""]
        let inputs = box.inputs(installDirectories: ["primary"], probe: { executable, timeout in
            try? await Task.sleep(nanoseconds: 300_000_000)
            return await Resolver.runVersionProbe(executable, environment: probeEnvironment, timeout: timeout)
        })
        let client = CodexTranslationClient(
            configuration: .init(arguments: ["normal"], requestTimeout: 2),
            executableResolver: Resolver(inputs: inputs)
        )

        let first = Task { try await client.connect() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let cancelled = Task { try await client.connect() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let second = Task { try await client.connect(forceRefresh: true) }
        cancelled.cancel()
        do {
            try await cancelled.value
            fail("a cancelled waiter must not report success")
        } catch is CancellationError {
        } catch {
            fail("a cancelled waiter must throw CancellationError, not \(error)")
        }
        do {
            try await first.value
            try await second.value
        } catch {
            fail("overlapping connections must share one start: \(error)")
        }
        require(box.probedPaths().filter { $0 == primary.path }.count == 1, "overlapping connections run discovery once")
        await client.disconnect()
    }

    private static func resolve(_ inputs: Resolver.Inputs) async -> Resolver.Resolution? {
        do {
            return try await Resolver(inputs: inputs).resolve()
        } catch {
            fail("resolution failed unexpectedly: \(error)")
        }
    }

    private static func expectError(
        _ inputs: Resolver.Inputs,
        _ label: String,
        matches: (ClientError) -> Bool
    ) async {
        do {
            let resolution = try await Resolver(inputs: inputs).resolve()
            fail("\(label): resolved \(resolution.entrypoint.path)")
        } catch let error as ClientError {
            require(matches(error), "\(label): unexpected \(error)")
        } catch {
            fail("\(label): unexpected \(error)")
        }
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("CodexExecutableResolverTests failed: \(message)")
    }
}
