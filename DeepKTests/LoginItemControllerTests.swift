import Foundation

@main
@MainActor
struct LoginItemControllerTests {
    static func main() {
        statusRefreshesFromTheService()
        enablingAndDisablingFollowTheActualServiceStatus()
        failuresAreVisibleUntilTheNextRefresh()
        busyStatePreventsReentrantToggle()
        settingsOpeningIsDelegated()
        pendingApprovalCanBeCancelledWithoutRegisteringAgain()
        failedDisableKeepsActualRegistrationVisible()
        print("LoginItemController tests passed")
    }

    private static func statusRefreshesFromTheService() {
        let service = FakeLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)

        require(controller.status == .disabled, "not registered must be represented as disabled")
        require(!controller.isEnabled, "disabled login item must not be enabled")
        require(!controller.requiresApproval, "disabled login item does not require approval")

        service.status = .requiresApproval
        controller.refresh()
        require(controller.status == .requiresApproval, "approval state must come from ServiceManagement")
        require(controller.requiresApproval, "approval state must be exposed to the settings UI")
        require(controller.statusText == "시스템 설정에서 승인 필요", "approval guidance must be visible")

        service.status = .notFound
        controller.refresh()
        require(controller.status == .notFound, "missing service must be represented as not found")
        require(controller.statusText == "로그인 항목을 찾을 수 없음", "missing-service guidance must be visible")

        service.status = .enabled
        controller.refresh()
        require(controller.isEnabled, "enabled service status must turn the setting on")
        require(controller.statusText == "로그인 시 자동 실행 켜짐", "enabled status must be visible")
    }

    private static func enablingAndDisablingFollowTheActualServiceStatus() {
        let service = FakeLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)

        controller.setEnabled(true)
        require(service.registerCount == 1, "enabling must register once")
        require(controller.status == .enabled, "a successful registration must read back enabled")
        require(controller.isEnabled, "a successful registration must expose enabled")
        require(!controller.isBusy, "the controller must leave the loading state")

        controller.setEnabled(false)
        require(service.unregisterCount == 1, "disabling must unregister once")
        require(controller.status == .disabled, "a successful unregistration must read back disabled")
        require(!controller.isEnabled, "a successful unregistration must expose disabled")
    }

    private static func failuresAreVisibleUntilTheNextRefresh() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = TestError.message("등록할 수 없습니다")
        let controller = LoginItemController(service: service)

        controller.setEnabled(true)
        require(controller.status == .failure, "a registration error must be represented as failure")
        require(controller.error == "등록할 수 없습니다", "the registration error must be exposed")
        require(controller.statusText.contains("등록할 수 없습니다"), "failure text must include recovery context")
        require(!controller.isBusy, "a failed operation must leave the loading state")

        service.registerError = nil
        controller.refresh()
        require(controller.status == .disabled, "refresh must recover the actual service state")
        require(controller.error == nil, "refresh must clear a resolved error")
    }

    private static func busyStatePreventsReentrantToggle() {
        let service = FakeLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)
        service.onRegister = {
            // register()가 실행 중일 때 발생한 두 번째 토글은 무시해야 한다.
            controller.setEnabled(false)
        }

        controller.setEnabled(true)
        require(service.registerCount == 1, "the first toggle must be registered")
        require(service.unregisterCount == 0, "a reentrant toggle must not unregister")
        require(controller.status == .enabled, "the first operation must determine the final state")
    }

    private static func settingsOpeningIsDelegated() {
        let service = FakeLoginItemService(status: .notRegistered)
        let controller = LoginItemController(service: service)

        controller.openSettings()
        require(service.openSettingsCount == 1, "settings navigation must be delegated")
    }

    private static func pendingApprovalCanBeCancelledWithoutRegisteringAgain() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        require(service.registerCount == 0, "승인 대기 중에는 중복 등록하지 않는다")
        controller.setEnabled(false)
        require(service.unregisterCount == 1, "승인 대기 중인 등록도 취소할 수 있다")
        require(controller.status == .disabled, "취소 후 실제 해제 상태를 표시한다")
    }

    private static func failedDisableKeepsActualRegistrationVisible() {
        let service = FakeLoginItemService(status: .enabled)
        service.unregisterError = TestError.message("해제 실패")
        let controller = LoginItemController(service: service)
        controller.setEnabled(false)
        require(controller.error != nil, "해제 실패를 안내한다")
        require(controller.isEnabled, "해제가 실패하면 실제 켜짐 상태를 유지한다")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServiceAdapter {
    var status: LoginItemServiceStatus
    var registerCount = 0
    var unregisterCount = 0
    var openSettingsCount = 0
    var registerError: Error?
    var unregisterError: Error?
    var onRegister: (() -> Void)?

    init(status: LoginItemServiceStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        onRegister?()
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSettings() {
        openSettingsCount += 1
    }
}

private enum TestError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(value):
            return value
        }
    }
}
