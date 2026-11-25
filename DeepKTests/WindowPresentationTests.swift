import AppKit
import Foundation

@main
struct WindowPresentationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 296),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        precondition(window.level == .normal && !window.hidesOnDeactivate,
                     "translation uses normal ordering and remains visible when inactive")
        precondition(window.canBecomeKey && !window.styleMask.contains(.nonactivatingPanel),
                     "clicking translation must allow keyboard focus and app activation")
        precondition(window.collectionBehavior == [.moveToActiveSpace, .fullScreenNone],
                     "translation belongs to one Space and must not accompany full-screen windows")
        testOpeningResizeDoesNotAnimate()
        testDefaultPolicyAndPersistence()
        testManualResizeAndPreviewPolicy()
        testToggleAndLayoutThreshold()
        testClampingRetainsTopLeft()
        print("Window presentation policy and geometry checks passed")
    }

    private final class ResizeRecordingWindow: NSWindow {
        var resizeAnimationFlags: [Bool] = []

        override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
            resizeAnimationFlags.append(animateFlag)
            super.setFrame(frameRect, display: flag, animate: animateFlag)
        }
    }

    @MainActor
    private static func testOpeningResizeDoesNotAnimate() {
        let suite = "deepK.window-presentation-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let window = ResizeRecordingWindow(
            contentRect: NSRect(origin: .zero, size: WindowPresentation.smallSize),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        precondition(!window.isVisible)
        let presentation = WindowPresentation(defaults: defaults, reduceMotion: { false })
        presentation.attach(window)
        presentation.setPreset(.large)
        presentation.applyOnOpen()
        precondition(window.resizeAnimationFlags == [false], "resize completes before a hidden window is ordered forward")
    }

    @MainActor
    private static func testDefaultPolicyAndPersistence() {
        let suite = "deepK.window-presentation-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let presentation = WindowPresentation(defaults: defaults, reduceMotion: { true })
        precondition(presentation.openPreset == .last)
        precondition(presentation.lastSize == WindowPresentation.smallSize)
        precondition(presentation.openingSize == WindowPresentation.smallSize)
        precondition(presentation.preview() == WindowPresentation.smallSize)

        presentation.setOpeningPreference(.large)
        precondition(presentation.openingPreference == WindowPresentation.OpeningPreference.large)
        precondition(presentation.openingSize == WindowPresentation.largeSize)
        precondition(presentation.currentSizeLabel == "작게")
        precondition(presentation.currentSize == WindowPresentation.smallSize,
                     "Changing the next-open policy must not resize the current window")

        let restored = WindowPresentation(defaults: defaults, reduceMotion: { true })
        precondition(restored.openPreset == .large)
        precondition(restored.lastSize == WindowPresentation.smallSize)
    }

    @MainActor
    private static func testManualResizeAndPreviewPolicy() {
        let suite = "deepK.window-presentation-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let presentation = WindowPresentation(defaults: defaults, reduceMotion: { true })
        presentation.setPreset(.large)
        let custom = NSRect(x: 120, y: 280, width: 610, height: 410)
        presentation.didResize(custom)
        precondition(presentation.lastSize == custom.size)
        precondition(presentation.currentFrame == custom)
        precondition(presentation.preview() == custom.size,
                     "An existing manually sized window is preserved by preview")

        let restored = WindowPresentation(defaults: defaults, reduceMotion: { true })
        precondition(restored.openPreset == .large)
        precondition(restored.lastSize == custom.size,
                     "Manual size is persisted independently of the opening preset")
        precondition(restored.preview() == WindowPresentation.smallSize,
                     "A newly created preview starts small even with always-large opening policy")
    }

    @MainActor
    private static func testToggleAndLayoutThreshold() {
        let suite = "deepK.window-presentation-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let presentation = WindowPresentation(defaults: defaults, reduceMotion: { true })
        precondition(!presentation.isExpanded)
        precondition(presentation.toggleSize() == WindowPresentation.largeSize)
        precondition(presentation.isExpanded)
        precondition(presentation.lastSize == WindowPresentation.largeSize)
        precondition(presentation.toggleSize() == WindowPresentation.smallSize)
        precondition(!presentation.isExpanded)

        precondition(!WindowPresentation.isExpanded(width: 719))
        precondition(WindowPresentation.isExpanded(width: 720))
        precondition(WindowPresentation.isExpanded(width: 721))
        precondition(WindowPresentation.sizeMode(for: WindowPresentation.smallSize) == .small)
        precondition(WindowPresentation.sizeMode(for: WindowPresentation.largeSize) == .large)
        precondition(WindowPresentation.sizeMode(for: CGSize(width: 721, height: 420)) == .custom)
    }

    @MainActor
    private static func testClampingRetainsTopLeft() {
        let visible = NSRect(x: 40, y: 70, width: 1_000, height: 700)
        let inside = NSRect(x: 180, y: 240, width: 500, height: 400)
        let retained = WindowPresentation.clampedFrame(inside, within: visible)
        precondition(retained.minX == inside.minX)
        precondition(retained.maxY == inside.maxY)
        precondition(retained.size == inside.size)

        let offscreen = NSRect(x: 900, y: 20, width: 300, height: 800)
        let clamped = WindowPresentation.clampedFrame(offscreen, within: visible)
        precondition(clamped.maxX <= visible.maxX)
        precondition(clamped.minX >= visible.minX)
        precondition(clamped.minY >= visible.minY)
        precondition(clamped.maxY <= visible.maxY)
        precondition(clamped.maxY == visible.maxY,
                     "An oversized frame is fitted using its top edge")
    }
}
