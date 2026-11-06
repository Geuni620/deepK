#if IMAGE_INPUT_RELEASE_TESTS
import AppKit

/// The production compilation flag, with synthetic fixtures linked only to this executable.
@main @MainActor enum ImageInputReleaseTests {
    static func main() {
        _ = NSApplication.shared
        Task {
            await NativeImageTests.run()
            await ImageFeedbackBenchmark.run()
            do { try ScreenScannerTests.run() }
            catch { fputs("FAIL: production image scanner geometry\n",stderr);exit(1) }
            ImageTranslationTests.run()
            await AppModel.shared.shutdown()
            print("PASS: production image compilation path; synthetic only; no provider or general clipboard")
            exit(0)
        }
        RunLoop.main.run()
    }
}
#endif
