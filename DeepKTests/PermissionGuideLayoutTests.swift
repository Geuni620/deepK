import CoreGraphics

@main
struct PermissionGuideLayoutTests {
    static func main() {
        testMainWindowSelection()
        testCoordinateConversion()
        testPanelPlacement()
        print("Permission guide layout checks passed")
    }

    private static func testMainWindowSelection() {
        let settings = CGRect(x: 100, y: 80, width: 715, height: 640)
        let sheet = CGRect(x: 200, y: 120, width: 300, height: 200)
        let overlay = CGRect(x: 0, y: 0, width: 1000, height: 900)
        precondition(
            PermissionGuideLayout.mainWindowBounds([(0, sheet), (0, settings), (25, overlay)]) == settings,
            "the guide follows the largest normal-layer window, not sheets or overlays"
        )
        precondition(PermissionGuideLayout.mainWindowBounds([(0, sheet)]) == nil, "small windows are not targets")
        precondition(PermissionGuideLayout.mainWindowBounds([]) == nil)
    }

    private static func testCoordinateConversion() {
        let bounds = CGRect(x: 100, y: 80, width: 715, height: 640)
        let frame = PermissionGuideLayout.appKitFrame(fromWindowBounds: bounds, primaryScreenHeight: 1692)
        precondition(frame == CGRect(x: 100, y: 1692 - 720, width: 715, height: 640), "top-left origin flips to bottom-left")

        // 주 화면 위쪽에 놓인 보조 화면은 음수 y를 가진다.
        let above = PermissionGuideLayout.appKitFrame(
            fromWindowBounds: CGRect(x: -1500, y: -900, width: 700, height: 600),
            primaryScreenHeight: 1692
        )
        precondition(above.minY == 1692 + 300, "windows on a display above the primary keep their position")
    }

    private static func testPanelPlacement() {
        let size = CGSize(width: 340, height: 142)
        let visible = CGRect(x: 0, y: 0, width: 1680, height: 1025)

        let settings = CGRect(x: 400, y: 400, width: 715, height: 560)
        let below = PermissionGuideLayout.panelFrame(size: size, settingsFrame: settings, visibleFrame: visible)
        precondition(below.midX == settings.midX, "centered under the settings window")
        precondition(below.maxY == settings.minY - 12, "attached just below the settings window")

        // 아래 공간이 없으면 설정 창의 아래쪽 안으로 올린다.
        let low = CGRect(x: 400, y: 40, width: 715, height: 560)
        let inside = PermissionGuideLayout.panelFrame(size: size, settingsFrame: low, visibleFrame: visible)
        precondition(inside.minY == low.minY + 12, "moves inside the bottom of the settings window")
        precondition(visible.contains(inside))

        // 화면 가장자리에 붙은 설정 창에서도 안내가 화면 밖으로 나가지 않는다.
        let edge = CGRect(x: -200, y: 500, width: 400, height: 400)
        let clamped = PermissionGuideLayout.panelFrame(size: size, settingsFrame: edge, visibleFrame: visible)
        precondition(clamped.minX == visible.minX + 12, "clamped to the visible frame")
        precondition(visible.contains(clamped))

        // 보조 화면(음수 x)에서도 그 화면의 보이는 영역 기준으로 맞춘다.
        let secondary = CGRect(x: -1680, y: 642, width: 1680, height: 1025)
        let settingsOnSecondary = CGRect(x: -1600, y: 900, width: 715, height: 560)
        let onSecondary = PermissionGuideLayout.panelFrame(
            size: size, settingsFrame: settingsOnSecondary, visibleFrame: secondary
        )
        precondition(secondary.contains(onSecondary), "stays on the display that shows System Settings")
    }
}
