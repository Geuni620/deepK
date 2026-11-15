import Foundation
import Observation

@MainActor
@Observable
final class AppUpdateController {
    enum CheckResult: Equatable { case skipped, checked, failed, cancelled }

    private enum Key {
        static let automatic = "automaticallyChecksForUpdates"
        static let lastAttempt = "updateLastAttempt"
        static let lastSucceeded = "updateLastSucceeded"
        static let cachedTag = "updateAvailableTag"
        static let notifiedVersion = "updateNotifiedVersion"
    }

    let currentVersion: AppVersion?
    private(set) var automaticallyChecks: Bool
    private(set) var availableRelease: AppRelease?
    private(set) var isChecking = false
    private(set) var statusMessage = DKLocalized("업데이트 확인 전")

    @ObservationIgnored var onStateChange: (() -> Void)?
    /// Return true only when a notice was actually shown. Busy UI can defer it.
    @ObservationIgnored var onUpdateAvailable: ((AppRelease) -> Bool)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: @Sendable () async throws -> AppRelease?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0

    init(
        currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        defaults: UserDefaults = .standard,
        automaticallyChecksByDefault: Bool = Bundle.main.bundleIdentifier == "com.deepk.app",
        now: @escaping () -> Date = Date.init,
        fetch: @escaping @Sendable () async throws -> AppRelease? = { try await AppReleaseClient().latestRelease() }
    ) {
        self.currentVersion = currentVersion.flatMap(AppVersion.init)
        self.defaults = defaults
        self.fetch = fetch
        self.now = now
        automaticallyChecks = defaults.object(forKey: Key.automatic) as? Bool ?? automaticallyChecksByDefault
        if let tag = defaults.string(forKey: Key.cachedTag), let cached = AppRelease(tag: tag),
           let current = self.currentVersion, cached.version > current {
            availableRelease = cached
            statusMessage = DKFormat("새 버전 %1$@을 사용할 수 있습니다", cached.version)
        } else if self.currentVersion == nil {
            statusMessage = DKLocalized("앱 버전 정보를 확인할 수 없습니다")
        }
    }

    func start() {
        guard automaticallyChecks, currentVersion != nil, pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                do { try await Task.sleep(for: .seconds(3_600)) }
                catch { break }
            }
        }
    }

    deinit { pollingTask?.cancel() }

    func stop() {
        generation &+= 1
        pollingTask?.cancel()
        pollingTask = nil
        if isChecking {
            statusMessage = availableRelease.map { DKFormat("새 버전 %1$@을 사용할 수 있습니다", $0.version) } ?? DKLocalized("업데이트 확인 전")
        }
        isChecking = false
        onStateChange?()
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        automaticallyChecks = enabled
        defaults.set(enabled, forKey: Key.automatic)
        if enabled {
            start()
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
        onStateChange?()
    }

    @discardableResult
    func check(manual: Bool = false) async -> CheckResult {
        guard !isChecking, let currentVersion else { return .skipped }
        if !manual {
            guard automaticallyChecks else { return .skipped }
            notifyIfNeeded()
            if let lastAttempt = defaults.object(forKey: Key.lastAttempt) as? Date {
                let elapsed = now().timeIntervalSince(lastAttempt)
                let interval: TimeInterval = defaults.bool(forKey: Key.lastSucceeded) ? 86_400 : 3_600
                if elapsed >= 0 && elapsed < interval { return .skipped }
            }
        }

        let requestGeneration = generation
        let previousStatus = statusMessage
        isChecking = true
        statusMessage = DKLocalized("업데이트 확인 중…")
        onStateChange?()
        defer {
            if generation == requestGeneration {
                isChecking = false
                onStateChange?()
            }
        }
        do {
            let release = try await fetch()
            guard !Task.isCancelled, generation == requestGeneration else {
                if generation == requestGeneration { statusMessage = previousStatus }
                return .cancelled
            }
            defaults.set(now(), forKey: Key.lastAttempt)
            defaults.set(true, forKey: Key.lastSucceeded)
            if let release, release.version > currentVersion {
                availableRelease = release
                defaults.set(release.tag, forKey: Key.cachedTag)
                statusMessage = DKFormat("새 버전 %1$@을 사용할 수 있습니다", release.version)
                if !manual { notifyIfNeeded() }
            } else {
                availableRelease = nil
                defaults.removeObject(forKey: Key.cachedTag)
                statusMessage = release == nil ? DKLocalized("공개 업데이트 정보를 찾지 못했습니다") : DKLocalized("현재 버전보다 새로운 업데이트가 없습니다")
            }
            return .checked
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else {
                if generation == requestGeneration { statusMessage = previousStatus }
                return .cancelled
            }
            defaults.set(now(), forKey: Key.lastAttempt)
            defaults.set(false, forKey: Key.lastSucceeded)
            statusMessage = (error as? AppReleaseClient.Failure) == .rateLimited
                ? DKLocalized("업데이트 서버가 바쁩니다. 잠시 후 다시 확인해 주세요")
                : DKLocalized("업데이트를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요")
            return .failed
        }
    }

    func didPresent(_ release: AppRelease) {
        guard release.version == availableRelease?.version else { return }
        defaults.set(release.version.description, forKey: Key.notifiedVersion)
    }

    private func notifyIfNeeded() {
        guard automaticallyChecks, let release = availableRelease,
              defaults.string(forKey: Key.notifiedVersion) != release.version.description,
              onUpdateAvailable?(release) == true else { return }
        didPresent(release)
    }
}
