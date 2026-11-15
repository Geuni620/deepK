import Foundation

@main
@MainActor
struct AppUpdateTests {
    static func main() async throws {
        if CommandLine.arguments.contains("--live-check") {
            let release = try await AppReleaseClient().latestRelease()
            print("Live public release: \(release?.version.description ?? "none"); no app launched or installed")
            return
        }
        try versionsAndShippingAssets()
        try await transport()
        try await dailyChecksAndCachedNotices()
        try await failureRetryAndOptOut()
        try await deferredNoticeIsNotLost()
        await keepingCurrentVersionDoesNotRepeatTheNotice()
        await singleFlightAndLateCancellation()
        print("App update checks passed: numeric versions, published assets, transport, daily checks, cache, notices, opt-out and cancellation")
    }

    private static func payload(tag: String = "v0.2.1", draft: Bool = false, prerelease: Bool = false,
                                assets: Bool = true, externalAsset: Bool = false) throws -> Data {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let name = "deepK-distribution-\(version)-arm64-abc123456789.zip"
        return try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": "https://example.invalid/do-not-open-this",
            "assets": assets ? [["name": name, "browser_download_url": externalAsset ? "https://example.invalid/app.zip" :
                "https://github.com/Geuni620/deepK/releases/download/\(tag)/\(name)"]] : [],
        ])
    }

    private static func versionsAndShippingAssets() throws {
        precondition(AppVersion("0.9.9")! < AppVersion("0.10.0")!)
        precondition(AppVersion("v0.2.1") == AppVersion("0.2.1"))
        precondition(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        for invalid in ["", "0.2", "0.2.1.0", "01.2.0", "0.2.-1", "0.2.1-beta", "0.2.1+meta", " 0.2.1", "0.2.١", "999999999999999999999999.0.0"] {
            precondition(AppVersion(invalid) == nil, "reject unsupported version: \(invalid)")
        }
        let release = try AppReleaseClient.decode(payload())!
        precondition(release.pageURL.absoluteString == "https://github.com/Geuni620/deepK/releases/tag/v0.2.1",
                     "the response cannot choose an external update page")
        let draft = try AppReleaseClient.decode(payload(draft: true))
        let prerelease = try AppReleaseClient.decode(payload(prerelease: true))
        let sourceOnly = try AppReleaseClient.decode(payload(assets: false))
        let externalAsset = try AppReleaseClient.decode(payload(externalAsset: true))
        precondition(draft == nil && prerelease == nil)
        precondition(sourceOnly == nil, "source-only releases are not installable updates")
        precondition(externalAsset == nil)
        do {
            _ = try AppReleaseClient.decode(Data("{}".utf8))
            preconditionFailure("incomplete responses must fail")
        } catch AppReleaseClient.Failure.invalidRelease {}
        do {
            _ = try AppReleaseClient.decode(Data(repeating: 32, count: 1_048_577))
            preconditionFailure("oversized responses must fail")
        } catch AppReleaseClient.Failure.invalidRelease {}
    }

    private static func transport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = AppReleaseClient(session: session)
        UpdateURLProtocol.stub.set(status: 200, data: try payload())
        let release = try await client.latestRelease()
        precondition(release?.version == AppVersion("0.2.1"))
        let request = UpdateURLProtocol.stub.lastRequest!
        precondition(request.url == AppReleaseClient.endpoint && request.url?.query == nil)
        precondition(request.httpBody == nil && request.httpMethod == "GET")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
        precondition(request.value(forHTTPHeaderField: "User-Agent") == "deepK-update-checker")
        precondition(request.cachePolicy == .reloadIgnoringLocalCacheData && request.timeoutInterval == 10)
        UpdateURLProtocol.stub.set(status: 404, data: Data())
        let missing = try await client.latestRelease()
        precondition(missing == nil)
        for status in [403, 429, 500] {
            UpdateURLProtocol.stub.set(status: status, data: Data())
            do {
                _ = try await client.latestRelease()
                preconditionFailure("HTTP failures must not become up-to-date results")
            } catch let error as AppReleaseClient.Failure {
                precondition(error == (status == 500 ? .response : .rateLimited))
            }
        }
    }

    private static func dailyChecksAndCachedNotices() async throws {
        let suite = "com.deepk.tests.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = UpdateClock()
        let fetcher = UpdateFetcher(release: AppRelease(tag: "v0.2.1")!)
        let controller = makeController(defaults, clock: clock, fetcher: fetcher)
        var notices = 0
        controller.onUpdateAvailable = { _ in notices += 1; return true }
        let first = await controller.check()
        precondition(first == .checked && controller.availableRelease?.version == AppVersion("0.2.1"))
        precondition(notices == 1 && !controller.isChecking)
        let second = await controller.check()
        let count = await fetcher.count
        precondition(second == .skipped && count == 1 && notices == 1)

        let reopened = makeController(defaults, clock: clock, fetcher: fetcher)
        reopened.onUpdateAvailable = { _ in notices += 1; return true }
        precondition(reopened.availableRelease != nil, "a known update must survive a restart during the daily throttle")
        let reopenedResult = await reopened.check()
        precondition(reopenedResult == .skipped && notices == 1, "one automatic notice per version across restarts")

        clock.date.addTimeInterval(86_401)
        await fetcher.set(release: AppRelease(tag: "v0.2.2")!)
        let next = await reopened.check()
        precondition(next == .checked && notices == 2)
        let manual = await reopened.check(manual: true)
        precondition(manual == .checked && notices == 2, "manual checks bypass the interval and let the caller present the result")

        let installedNewVersion = AppUpdateController(currentVersion: "0.2.2", defaults: defaults,
            automaticallyChecksByDefault: true, now: { clock.date }, fetch: { try await fetcher.next() })
        precondition(installedNewVersion.availableRelease == nil, "installed versions must not retain an old update badge")
    }

    private static func failureRetryAndOptOut() async throws {
        let suite = "com.deepk.tests.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = UpdateClock()
        let fetcher = UpdateFetcher(release: AppRelease(tag: "v0.2.1")!)
        let controller = makeController(defaults, clock: clock, fetcher: fetcher)
        _ = await controller.check()
        await fetcher.set(failing: true)
        let failed = await controller.check(manual: true)
        precondition(failed == .failed && controller.availableRelease != nil, "network failure must not erase a known update")
        clock.date.addTimeInterval(3_599)
        let early = await controller.check()
        precondition(early == .skipped)
        clock.date.addTimeInterval(2)
        let retry = await controller.check()
        precondition(retry == .failed, "failed automatic checks retry after an hour")
        controller.setAutomaticallyChecks(false)
        let before = await fetcher.count
        clock.date.addTimeInterval(86_401)
        let disabled = await controller.check()
        let after = await fetcher.count
        precondition(disabled == .skipped && after == before)
        await fetcher.set(failing: false)
        let manual = await controller.check(manual: true)
        precondition(manual == .checked, "opting out of automatic checks keeps manual checks usable")

        let reopened = makeController(defaults, clock: clock, fetcher: fetcher)
        precondition(!reopened.automaticallyChecks, "the preference persists")
        let older = AppUpdateController(currentVersion: "0.3.0", defaults: defaults,
            automaticallyChecksByDefault: false, now: { clock.date }, fetch: { try await fetcher.next() })
        let result = await older.check(manual: true)
        precondition(result == .checked && older.availableRelease == nil, "never offer a downgrade")
    }

    private static func deferredNoticeIsNotLost() async throws {
        let suite = "com.deepk.tests.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = UpdateClock()
        let fetcher = UpdateFetcher(release: AppRelease(tag: "v0.2.1")!)
        let controller = makeController(defaults, clock: clock, fetcher: fetcher)
        var canPresent = false
        var shown = 0
        controller.onUpdateAvailable = { _ in
            guard canPresent else { return false }
            shown += 1
            return true
        }
        _ = await controller.check()
        precondition(shown == 0)
        canPresent = true
        let result = await controller.check()
        let count = await fetcher.count
        precondition(result == .skipped && shown == 1 && count == 1,
                     "deferred UI can present the cached update without another network request")
    }

    private static func singleFlightAndLateCancellation() async {
        let suite = "com.deepk.tests.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = UpdateGate()
        let controller = AppUpdateController(currentVersion: "0.2.0", defaults: defaults,
            automaticallyChecksByDefault: true, fetch: { await gate.fetch() })
        var shown = 0
        controller.onUpdateAvailable = { _ in shown += 1; return true }
        let pending = Task { await controller.check() }
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await gate.isWaiting) {
            precondition(ContinuousClock.now < deadline, "the request must start")
            await Task.yield()
        }
        let duplicate = await controller.check(manual: true)
        precondition(duplicate == .skipped && controller.isChecking)
        controller.stop()
        await gate.finish(AppRelease(tag: "v0.9.0")!)
        let result = await pending.value
        precondition(result == .cancelled && controller.availableRelease == nil && !controller.isChecking && shown == 0,
                     "a late response after shutdown cannot notify or update the cache")
        precondition(defaults.object(forKey: "updateLastAttempt") == nil)
    }

    private static func keepingCurrentVersionDoesNotRepeatTheNotice() async {
        let suite = "com.deepk.tests.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = UpdateClock()
        let fetcher = UpdateFetcher(release: AppRelease(tag: "v0.2.1")!)
        let controller = makeController(defaults, clock: clock, fetcher: fetcher)
        var notices = 0
        controller.onUpdateAvailable = { _ in notices += 1; return true }
        _ = await controller.check()
        // The user closes the advisory and keeps the installed version. The UI
        // dismissal changes neither the installed version nor this controller.
        clock.date.addTimeInterval(86_401)
        let sameRelease = await controller.check()
        precondition(sameRelease == .checked && notices == 1,
                     "keeping the current version must not produce the same advisory every day")
        precondition(controller.currentVersion == AppVersion("0.2.0") && controller.automaticallyChecks)
        precondition(controller.availableRelease?.version == AppVersion("0.2.1"),
                     "the update remains accessible from the menu when the user wants it")

        let reopened = makeController(defaults, clock: clock, fetcher: fetcher)
        reopened.onUpdateAvailable = { _ in notices += 1; return true }
        _ = await reopened.check()
        precondition(notices == 1 && reopened.currentVersion == AppVersion("0.2.0"))
        await fetcher.set(release: AppRelease(tag: "v0.2.2")!)
        clock.date.addTimeInterval(86_401)
        _ = await reopened.check()
        precondition(notices == 2, "a later release can still be announced after declining the earlier one")
    }

    private static func makeController(_ defaults: UserDefaults, clock: UpdateClock, fetcher: UpdateFetcher) -> AppUpdateController {
        AppUpdateController(currentVersion: "0.2.0", defaults: defaults, automaticallyChecksByDefault: true,
                            now: { clock.date }, fetch: { try await fetcher.next() })
    }
}

@MainActor private final class UpdateClock { var date = Date(timeIntervalSince1970: 1_800_000_000) }

private actor UpdateFetcher {
    var count = 0
    var release: AppRelease?
    var failing = false
    init(release: AppRelease?) { self.release = release }
    func set(release: AppRelease?) { self.release = release }
    func set(failing: Bool) { self.failing = failing }
    func next() throws -> AppRelease? {
        count += 1
        if failing { throw AppReleaseClient.Failure.response }
        return release
    }
}

private actor UpdateGate {
    var continuation: CheckedContinuation<AppRelease?, Never>?
    var isWaiting: Bool { continuation != nil }
    func fetch() async -> AppRelease? { await withCheckedContinuation { continuation = $0 } }
    func finish(_ release: AppRelease) { continuation?.resume(returning: release); continuation = nil }
}

private final class UpdateHTTPStub: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var data = Data()
    private var request: URLRequest?
    var lastRequest: URLRequest? { lock.withLock { request } }
    func set(status: Int, data: Data) { lock.withLock { self.status = status; self.data = data } }
    func response(to request: URLRequest) -> (Int, Data) {
        lock.withLock { self.request = request; return (status, data) }
    }
}

private final class UpdateURLProtocol: URLProtocol, @unchecked Sendable {
    static let stub = UpdateHTTPStub()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.stub.response(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
