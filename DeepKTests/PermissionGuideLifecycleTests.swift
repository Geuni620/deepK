@main
struct PermissionGuideLifecycleTests {
    static func main() {
        var guide = PermissionGuideLifecycle()
        precondition(guide.update(hasSettingsWindow: false, isSettingsWindowVisible: false, waitExpired: false) == .hide,
                     "wait for the settings window to open")
        precondition(guide.update(hasSettingsWindow: true, isSettingsWindowVisible: true, waitExpired: false) == .show)
        precondition(guide.update(hasSettingsWindow: true, isSettingsWindowVisible: false, waitExpired: true) == .hide,
                     "switching apps, Spaces or minimizing hides without ending the guide")
        precondition(guide.update(hasSettingsWindow: true, isSettingsWindowVisible: true, waitExpired: true) == .show,
                     "returning to the existing settings window restores the guide")
        precondition(guide.update(hasSettingsWindow: false, isSettingsWindowVisible: false, waitExpired: false) == .dismiss,
                     "closing an observed settings window ends the timer even if Settings is still running")

        var unopened = PermissionGuideLifecycle()
        precondition(unopened.update(hasSettingsWindow: false, isSettingsWindowVisible: false, waitExpired: true) == .dismiss,
                     "a settings window that never appears times out")
        var background = PermissionGuideLifecycle()
        precondition(background.update(hasSettingsWindow: true, isSettingsWindowVisible: false, waitExpired: false) == .hide)
        precondition(background.update(hasSettingsWindow: false, isSettingsWindowVisible: false, waitExpired: false) == .dismiss,
                     "closing a background window also ends the guide")
        print("Permission guide lifecycle checks passed")
    }
}
