import Foundation

/// 개발·배포 빌드는 별도 macOS 앱으로 권한과 설정을 보관한다.
enum AppIdentity {
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.deepk.app" }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "deepK"
    }
}
