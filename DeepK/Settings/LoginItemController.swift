import Observation
import ServiceManagement

/// 로그인 시 자동 실행 항목을 테스트 가능한 형태로 감싼다.
@MainActor
public protocol LoginItemServiceAdapter: AnyObject {
    var status: LoginItemServiceStatus { get }

    func register() throws
    func unregister() throws
    func openSettings()
}

/// SMAppService가 반환하는 상태 중 앱에서 보여 줄 상태만 표현한다.
public enum LoginItemServiceStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum LoginItemStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case notFound
    case failure
}

/// deepK의 메인 앱을 macOS 로그인 항목으로 등록·해제한다.
@MainActor
@Observable
public final class LoginItemController {
    public private(set) var status: LoginItemStatus = .disabled
    public private(set) var isBusy = false
    public private(set) var error: String?

    private var serviceStatus: LoginItemServiceStatus = .notRegistered
    public var isEnabled: Bool { serviceStatus == .enabled }
    public var requiresApproval: Bool { serviceStatus == .requiresApproval }
    public var isRegistered: Bool { isEnabled || requiresApproval }

    public var statusText: String {
        switch status {
        case .disabled:
            return "로그인 시 자동 실행 꺼짐"
        case .enabled:
            return "로그인 시 자동 실행 켜짐"
        case .requiresApproval:
            return "시스템 설정에서 승인 필요"
        case .notFound:
            return "로그인 항목을 찾을 수 없음"
        case .failure:
            return error.map { "자동 실행 설정 실패: \($0)" } ?? "자동 실행 설정 실패"
        }
    }

    @ObservationIgnored
    private let service: any LoginItemServiceAdapter

    public init(service: (any LoginItemServiceAdapter)? = nil) {
        self.service = service ?? SystemLoginItemServiceAdapter()
        refresh()
    }

    /// 현재 ServiceManagement 상태를 다시 읽어 화면 상태를 실제 등록 상태와 맞춘다.
    public func refresh() {
        guard !isBusy else { return }
        apply(service.status)
        error = nil
    }

    /// 사용자가 토글한 값을 macOS에 반영한다. 진행 중인 요청은 중복 실행하지 않는다.
    public func setEnabled(_ enabled: Bool) {
        guard !isBusy else { return }
        guard status == .failure || enabled != isRegistered else { return }

        isBusy = true
        error = nil
        defer { isBusy = false }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            // 성공 여부만으로 토글을 확정하지 않고, macOS가 보고한 상태를 다시 읽는다.
            apply(service.status)
        } catch {
            serviceStatus = service.status
            status = .failure
            self.error = error.localizedDescription
        }
    }

    /// macOS 시스템 설정의 로그인 항목 화면을 연다.
    public func openSettings() {
        service.openSettings()
    }

    private func apply(_ serviceStatus: LoginItemServiceStatus) {
        self.serviceStatus = serviceStatus
        switch serviceStatus {
        case .notRegistered:
            status = .disabled
        case .enabled:
            status = .enabled
        case .requiresApproval:
            status = .requiresApproval
        case .notFound:
            status = .notFound
        }
    }
}

/// 실제 앱에서만 SMAppService.mainApp를 사용한다. 테스트는 위 어댑터를 주입한다.
@MainActor
private final class SystemLoginItemServiceAdapter: LoginItemServiceAdapter {
    private let service = SMAppService.mainApp

    var status: LoginItemServiceStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
