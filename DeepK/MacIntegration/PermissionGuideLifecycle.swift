/// 설정 창 닫기와 다른 앱으로 이동하기를 구분해 안내의 수명을 관리한다.
struct PermissionGuideLifecycle {
    enum Action: Equatable {
        case show
        case hide
        case dismiss
    }

    private var sawSettingsWindow = false

    mutating func update(
        hasSettingsWindow: Bool,
        isSettingsWindowVisible: Bool,
        waitExpired: Bool
    ) -> Action {
        guard hasSettingsWindow else {
            return sawSettingsWindow || waitExpired ? .dismiss : .hide
        }
        sawSettingsWindow = true
        return isSettingsWindowVisible ? .show : .hide
    }
}
