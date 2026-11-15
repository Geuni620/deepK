import Foundation

/// Public releases use stable major.minor.patch tags. Compare numbers, not strings.
struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
            numbers.append(number)
        }
        major = numbers[0]; minor = numbers[1]; patch = numbers[2]
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct AppRelease: Equatable, Sendable {
    let tag: String
    let version: AppVersion

    init?(tag: String) {
        guard let version = AppVersion(tag) else { return nil }
        self.tag = tag
        self.version = version
    }

    /// Construct the destination locally rather than opening a URL from the API response.
    var pageURL: URL { URL(string: "https://github.com/Geuni620/deepK/releases/tag/\(tag)")! }
}

struct AppReleaseClient: Sendable {
    static let endpoint = URL(string: "https://api.github.com/repos/Geuni620/deepK/releases/latest")!

    enum Failure: Error, Equatable {
        case response
        case rateLimited
        case invalidRelease
    }

    private let session: URLSession

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    func latestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("deepK-update-checker", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw Failure.response }
        if response.statusCode == 404 { return nil }
        if response.statusCode == 403 || response.statusCode == 429 { throw Failure.rateLimited }
        guard response.statusCode == 200 else { throw Failure.response }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> AppRelease? {
        guard data.count <= 1_048_576 else { throw Failure.invalidRelease }
        struct Payload: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: String }
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw Failure.invalidRelease }
        guard !payload.draft, !payload.prerelease else { return nil }
        guard let release = AppRelease(tag: payload.tag_name) else { throw Failure.invalidRelease }
        let prefix = "deepK-distribution-\(release.version)-arm64-"
        // A published tag without its installable app is not an available update.
        guard payload.assets.contains(where: { asset in
            guard asset.name.hasPrefix(prefix), asset.name.hasSuffix(".zip") else { return false }
            return asset.browser_download_url == "https://github.com/Geuni620/deepK/releases/download/\(release.tag)/\(asset.name)"
        }) else { return nil }
        return release
    }
}
