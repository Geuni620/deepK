import CoreGraphics

/// 시스템 설정 창 옆에 붙이는 권한 안내 창의 위치를 계산한다.
enum PermissionGuideLayout {
    /// 안내를 붙일 설정 창으로 보기에 너무 작은 창(시트·팝오버)은 제외한다.
    static let minimumSettingsWindowSize = CGSize(width: 320, height: 240)

    /// CGWindowList 창 목록에서 일반 레이어의 충분히 큰 창 중 가장 큰 창을 고른다.
    static func mainWindowBounds(_ windows: [(layer: Int, bounds: CGRect)]) -> CGRect? {
        windows
            .filter {
                $0.layer == 0
                    && $0.bounds.width > minimumSettingsWindowSize.width
                    && $0.bounds.height > minimumSettingsWindowSize.height
            }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?
            .bounds
    }

    /// CGWindowList 좌표(주 화면 왼쪽 위 원점)를 AppKit 좌표(주 화면 왼쪽 아래 원점)로 바꾼다.
    static func appKitFrame(fromWindowBounds bounds: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: primaryScreenHeight - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    /// 설정 창 바로 아래 가운데에 붙인다. 아래 공간이 없으면 설정 창 아래쪽 안으로 올리고,
    /// 어느 경우든 화면의 보이는 영역 밖으로 나가지 않게 맞춘다.
    static func panelFrame(
        size: CGSize,
        settingsFrame: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 12
    ) -> CGRect {
        var x = settingsFrame.midX - size.width / 2
        var y = settingsFrame.minY - gap - size.height
        if y < visibleFrame.minY + gap {
            y = settingsFrame.minY + gap
        }
        x = min(max(x, visibleFrame.minX + gap), visibleFrame.maxX - size.width - gap)
        y = min(max(y, visibleFrame.minY + gap), visibleFrame.maxY - size.height - gap)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
