import Foundation

/// AppKit 의존성을 경계에서 변환해 키 감지 로직을 독립적으로 테스트한다.
public struct DoubleCopyModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let control = Self(rawValue: 1 << 3)
}

/// 같은 앱의 두 번 복사를 판별한다. 실제 키 감시와 클립보드 접근은 호출자가 담당한다.
public struct DoubleCopyDetector: Sendable {
    /// macOS의 ANSI C 가상 키 코드.
    public static let commandCKeyCode: UInt16 = 8

    /// 두 번 복사 사이에 Command를 놓았다 다시 눌러도 첫 복사 상태를 유지한다.
    public static let leftCommandKeyCode: UInt16 = 55
    public static let rightCommandKeyCode: UInt16 = 54

    public struct Configuration: Sendable, Equatable {
        public let window: TimeInterval
        public let copyKeyCode: UInt16
        public let commandModifiers: DoubleCopyModifiers
        public let commandKeyCodes: Set<UInt16>

        public init(
            window: TimeInterval,
            copyKeyCode: UInt16 = DoubleCopyDetector.commandCKeyCode,
            commandModifiers: DoubleCopyModifiers = .command,
            commandKeyCodes: Set<UInt16> = [
                DoubleCopyDetector.leftCommandKeyCode,
                DoubleCopyDetector.rightCommandKeyCode
            ]
        ) {
            precondition(window.isFinite && window > 0, "The detection window must be finite and greater than zero.")
            self.window = window
            self.copyKeyCode = copyKeyCode
            self.commandModifiers = commandModifiers
            self.commandKeyCodes = commandKeyCodes
        }
    }

    public struct KeyEvent: Sendable, Equatable {
        public enum Phase: Sendable, Equatable {
            case keyDown
            case keyUp
        }

        public let timestamp: TimeInterval
        public let processIdentifier: Int32
        public let keyCode: UInt16
        public let modifiers: DoubleCopyModifiers
        public let phase: Phase
        public let isAutorepeat: Bool

        public init(
            timestamp: TimeInterval,
            processIdentifier: Int32,
            keyCode: UInt16,
            modifiers: DoubleCopyModifiers,
            phase: Phase = .keyDown,
            isAutorepeat: Bool = false
        ) {
            self.timestamp = timestamp
            self.processIdentifier = processIdentifier
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.phase = phase
            self.isAutorepeat = isAutorepeat
        }
    }

    public enum Input: Sendable, Equatable {
        case key(KeyEvent)
        case applicationChanged(timestamp: TimeInterval, processIdentifier: Int32)
    }

    public enum Outcome: Sendable, Equatable {
        case ignored
        case waitingForSecondCopy
        case triggered
        case reset
    }

    private struct PendingCopy: Sendable, Equatable {
        let timestamp: TimeInterval
        let processIdentifier: Int32
    }

    public let configuration: Configuration
    private var pendingCopy: PendingCopy?

    public init(configuration: Configuration) {
        self.configuration = configuration
        pendingCopy = nil
    }

    public init(window: TimeInterval) {
        self.init(configuration: Configuration(window: window))
    }

    public var isWaitingForSecondCopy: Bool {
        pendingCopy != nil
    }

    public mutating func reset() {
        pendingCopy = nil
    }

    public mutating func receive(_ input: Input) -> Outcome {
        switch input {
        case .applicationChanged:
            let hadPendingCopy = pendingCopy != nil
            pendingCopy = nil
            return hadPendingCopy ? .reset : .ignored

        case let .key(event):
            return receive(event)
        }
    }

    public mutating func receive(_ event: KeyEvent) -> Outcome {
        guard event.timestamp.isFinite else {
            let hadPendingCopy = pendingCopy != nil
            pendingCopy = nil
            return hadPendingCopy ? .reset : .ignored
        }

        var invalidatedPendingCopy = false

        if let pendingCopy {
            let elapsed = event.timestamp - pendingCopy.timestamp

            // 시간 순서가 뒤집히면 음수 간격을 두 번 복사로 오인하지 않도록 이전 상태를 버린다.
            if elapsed < 0 || elapsed > configuration.window {
                self.pendingCopy = nil
                invalidatedPendingCopy = true
            } else if event.processIdentifier != pendingCopy.processIdentifier {
                // 앱이 바뀐 뒤의 입력은 새 쌍을 시작할 수 있지만 이전 앱의 복사와 짝지을 수 없다.
                self.pendingCopy = nil
                invalidatedPendingCopy = true
            }
        }

        guard event.phase == .keyDown else {
            return invalidatedPendingCopy ? .reset : .ignored
        }

        // 복사 사이에 Command를 놓았다 다시 누르는 동작은 다른 입력으로 취급하지 않는다.
        if configuration.commandKeyCodes.contains(event.keyCode) {
            return invalidatedPendingCopy ? .reset : .ignored
        }

        guard event.keyCode == configuration.copyKeyCode else {
            pendingCopy = nil
            return .reset
        }

        // C 키를 누르고 있어 발생하는 자동 반복은 별도의 복사로 세지 않는다.
        guard !event.isAutorepeat else {
            return .ignored
        }

        // Command-Shift-C 등 다른 단축키가 복사 쌍에 포함되지 않게 한다.
        guard event.modifiers == configuration.commandModifiers else {
            pendingCopy = nil
            return .reset
        }

        if let pendingCopy,
           event.processIdentifier == pendingCopy.processIdentifier,
           event.timestamp - pendingCopy.timestamp <= configuration.window
        {
            // 쌍을 먼저 소진해야 세 번째 입력이 중복 실행 대신 새 쌍을 시작한다.
            self.pendingCopy = nil
            return .triggered
        }

        pendingCopy = PendingCopy(
            timestamp: event.timestamp,
            processIdentifier: event.processIdentifier
        )
        return .waitingForSecondCopy
    }
}
