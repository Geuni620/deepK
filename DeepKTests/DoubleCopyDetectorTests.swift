import Foundation

private enum DoubleCopyDetectorTests {
    private typealias Detector = DoubleCopyDetector
    private typealias Outcome = Detector.Outcome

    private static let copyKeyCode = Detector.commandCKeyCode

    static func runAll() {
        pairWithinWindowAndAtBoundary()
        timeoutStartsASeparatePair()
        autorepeatDoesNotCountAsAnEdge()
        commandReleaseAndRepressDoesNotResetPendingCopy()
        unrelatedKeyResetsPendingCopy()
        modifierMustBeExactlyCommand()
        processIdentifierChangeStartsASeparatePair()
        explicitApplicationChangeResetsPendingCopy()
        thirdPressDoesNotDuplicateTheCompletedPair()
        outOfOrderTimestampCannotCompleteAnOldPair()
    }

    private static func pairWithinWindowAndAtBoundary() {
        var detector = Detector(window: 0.5)

        expect(
            detector.receive(event(at: 10.0, pid: 42)),
            .waitingForSecondCopy,
            "the first command-C should arm the detector"
        )
        expect(
            detector.receive(event(at: 10.5, pid: 42)),
            .triggered,
            "the configured window boundary should still be accepted"
        )
        expect(!detector.isWaitingForSecondCopy, "a triggered pair should be consumed")
    }

    private static func timeoutStartsASeparatePair() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 1.0, pid: 7)), .waitingForSecondCopy, "first copy")
        expect(
            detector.receive(event(at: 1.51, pid: 7)),
            .waitingForSecondCopy,
            "a command-C after the window should become the first copy of a new pair"
        )
        expect(
            detector.receive(event(at: 1.7, pid: 7)),
            .triggered,
            "the new pair should be independent from the timed-out pair"
        )
    }

    private static func autorepeatDoesNotCountAsAnEdge() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 1.0, pid: 7)), .waitingForSecondCopy, "first copy")
        expect(
            detector.receive(event(at: 1.1, pid: 7, isAutorepeat: true)),
            .ignored,
            "autorepeat must not count as the second edge"
        )
        expect(
            detector.receive(event(at: 1.2, pid: 7)),
            .triggered,
            "the next non-repeat edge should complete the pair"
        )
    }

    private static func commandReleaseAndRepressDoesNotResetPendingCopy() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 1.0, pid: 7)), .waitingForSecondCopy, "first copy")
        expect(
            detector.receive(
                event(
                    at: 1.1,
                    pid: 7,
                    keyCode: Detector.leftCommandKeyCode,
                    modifiers: [],
                    phase: Detector.KeyEvent.Phase.keyUp
                )
            ),
            .ignored,
            "Command key-up is not unrelated text input"
        )
        expect(
            detector.receive(
                event(
                    at: 1.2,
                    pid: 7,
                    keyCode: Detector.leftCommandKeyCode,
                    modifiers: [],
                    phase: Detector.KeyEvent.Phase.keyDown
                )
            ),
            .ignored,
            "Command key-down should preserve the pending copy while the chord is rebuilt"
        )
        expect(
            detector.receive(event(at: 1.3, pid: 7)),
            .triggered,
            "a second command-C after Command release should still trigger"
        )
    }

    private static func unrelatedKeyResetsPendingCopy() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 1.0, pid: 7)), .waitingForSecondCopy, "first copy")
        expect(
            detector.receive(event(at: 1.1, pid: 7, keyCode: 7)),
            .reset,
            "an unrelated key-down should reset the gesture"
        )
        expect(
            detector.receive(event(at: 1.2, pid: 7)),
            .waitingForSecondCopy,
            "the first command-C after reset should only arm the detector"
        )
        expect(detector.receive(event(at: 1.3, pid: 7)), .triggered, "the new pair")
    }

    private static func modifierMustBeExactlyCommand() {
        var detector = Detector(window: 0.5)

        expect(
            detector.receive(event(at: 1.0, pid: 7, modifiers: DoubleCopyModifiers.shift)),
            .reset,
            "C without Command must not arm the detector"
        )
        expect(
            detector.receive(event(at: 1.1, pid: 7)),
            .waitingForSecondCopy,
            "a valid command-C should arm after an invalid modifier chord"
        )
        expect(
            detector.receive(
                event(
                    at: 1.2,
                    pid: 7,
                    modifiers: DoubleCopyModifiers.command.union(.shift)
                )
            ),
            .reset,
            "Command-Shift-C must not complete a Command-C gesture"
        )
        expect(
            detector.receive(event(at: 1.3, pid: 7)),
            .waitingForSecondCopy,
            "the invalid chord should leave the detector idle"
        )
    }

    private static func processIdentifierChangeStartsASeparatePair() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 1.0, pid: 100)), .waitingForSecondCopy, "first app copy")
        expect(
            detector.receive(event(at: 1.1, pid: 200)),
            .waitingForSecondCopy,
            "a command-C from another PID must start a new pair, not trigger the old one"
        )
        expect(
            detector.receive(event(at: 1.2, pid: 200)),
            .triggered,
            "the new app's second copy should trigger"
        )
    }

    private static func explicitApplicationChangeResetsPendingCopy() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 1.0, pid: 100)), .waitingForSecondCopy, "first copy")
        expect(
            detector.receive(.applicationChanged(timestamp: 1.1, processIdentifier: 200)),
            .reset,
            "an explicit app switch should discard the pending copy"
        )
        expect(
            detector.receive(event(at: 1.2, pid: 200)),
            .waitingForSecondCopy,
            "the first copy after an app switch should only arm the detector"
        )
    }

    private static func thirdPressDoesNotDuplicateTheCompletedPair() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 1.0, pid: 7)), .waitingForSecondCopy, "first copy")
        expect(detector.receive(event(at: 1.1, pid: 7)), .triggered, "second copy")
        expect(
            detector.receive(event(at: 1.2, pid: 7)),
            .waitingForSecondCopy,
            "a third press should be a new first copy, not a duplicate trigger"
        )
    }

    private static func outOfOrderTimestampCannotCompleteAnOldPair() {
        var detector = Detector(window: 0.5)

        expect(detector.receive(event(at: 2.0, pid: 7)), .waitingForSecondCopy, "first copy")
        expect(
            detector.receive(event(at: 1.5, pid: 7)),
            .waitingForSecondCopy,
            "an out-of-order edge should discard the old timestamp and start fresh"
        )
        expect(
            detector.receive(event(at: 1.6, pid: 7)),
            .triggered,
            "only the fresh, ordered pair should trigger"
        )
    }

    private static func event(
        at timestamp: TimeInterval,
        pid: Int32,
        keyCode: UInt16 = copyKeyCode,
        modifiers: DoubleCopyModifiers = .command,
        phase: Detector.KeyEvent.Phase = .keyDown,
        isAutorepeat: Bool = false
    ) -> Detector.KeyEvent {
        Detector.KeyEvent(
            timestamp: timestamp,
            processIdentifier: pid,
            keyCode: keyCode,
            modifiers: modifiers,
            phase: phase,
            isAutorepeat: isAutorepeat
        )
    }

    private static func expect(_ actual: Outcome, _ expected: Outcome, _ message: String) {
        guard actual == expected else {
            fail("\(message); expected \(expected), got \(actual)")
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("DoubleCopyDetectorTests failed: \(message)")
    }
}

#if DOUBLE_COPY_DETECTOR_STANDALONE
@main
private enum DoubleCopyDetectorStandaloneRunner {
    static func main() {
        DoubleCopyDetectorTests.runAll()
        print("DoubleCopyDetectorTests passed")
    }
}
#endif
