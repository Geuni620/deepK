import AppKit
import CoreGraphics

private let deepKDoubleCopyEventMask: CGEventMask =
    (CGEventMask(1) << CGEventType.keyDown.rawValue)
    | (CGEventMask(1) << CGEventType.keyUp.rawValue)
    | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

private struct DoubleCopyKeyboardEvent: Sendable {
    let timestamp: TimeInterval
    let processIdentifier: Int32
    let keyCode: UInt16
    let modifiers: DoubleCopyModifiers
    let phase: DoubleCopyDetector.KeyEvent.Phase
    let isAutorepeat: Bool
}

/// 번역 창을 닫은 뒤 원래 앱으로 포커스를 돌려주기 위해 앱 참조를 보관한다.
public struct DoubleCopyCaptureContext {
    public let sourceProcessIdentifier: Int32
    public let application: NSRunningApplication?
    public let triggerUptime: TimeInterval

    public init(
        sourceProcessIdentifier: Int32,
        application: NSRunningApplication?,
        triggerUptime: TimeInterval
    ) {
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.application = application
        self.triggerUptime = triggerUptime
    }
}

/// 원래 복사 동작을 방해하지 않도록 키 이벤트를 수신만 한다.
/// AppKit과 콜백을 메인 액터에서 다루므로 이벤트 탭도 메인 런 루프에 등록한다.
@MainActor
public final class DoubleCopyMonitor {
    public struct Configuration: Equatable {
        public let pairWindow: TimeInterval
        public let pasteboardWait: TimeInterval
        public let pollInterval: TimeInterval

        public init(
            pairWindow: TimeInterval = 0.5,
            pasteboardWait: TimeInterval = 0.25,
            pollInterval: TimeInterval = 0.01
        ) {
            precondition(pairWindow.isFinite && pairWindow > 0, "The pair window must be finite and greater than zero.")
            precondition(pasteboardWait.isFinite && pasteboardWait > 0, "The pasteboard wait must be finite and greater than zero.")
            precondition(pollInterval.isFinite && pollInterval > 0, "The poll interval must be finite and greater than zero.")
            self.pairWindow = pairWindow
            self.pasteboardWait = pasteboardWait
            self.pollInterval = pollInterval
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        /// 전역 키 감시에는 시스템 설정의 입력 모니터링 권한이 필요하다.
        case inputMonitoringPermissionRequired
        case eventTapCreationFailed
        case runLoopSourceCreationFailed
        case eventTapRecoveryFailed
        /// 두 번째 키 입력 뒤에도 pasteboard changeCount가 갱신되지 않았다.
        case clipboardNotUpdated
        /// 새 pasteboard 항목은 문자열이지만 값이 비어 있다.
        case clipboardTextEmpty
        /// 새 pasteboard 항목에 읽을 수 있는 문자열 표현이 없다.
        case clipboardNonText
        /// 감지된 복사 쌍과 pasteboard 처리 상태가 일치하지 않는다.
        case clipboardTextUnavailable
        /// 비밀번호 관리자 등이 민감·임시 항목으로 표시한 복사다. 원문을 읽지 않는다.
        case clipboardConcealed
    }

    /// 원문이나 앱 이름을 남기지 않고 단축키 감지 경로의 마지막 단계를 나타낸다.
    public enum DiagnosticStage: Equatable, Sendable {
        case stopped
        case checkingPermission
        case creatingEventTap
        case ready
        case firstCopyDetected
        case secondCopyDetected
        case waitingForClipboard
        case clipboardCaptured
        case failed(Failure)
        case gestureReset(ResetReason)
        case recoveringEventTap
        case eventTapRecovered
    }

    /// 대기 중인 복사 쌍이 조용히 폐기된 이유를 구분한다.
    public enum ResetReason: Equatable, Sendable {
        case applicationChanged
        case unrelatedInput
        case pairWindowExpired
    }

    /// 진단 콜백으로 전달되는 메타데이터다. 클립보드 원문과 앱 식별자는 포함하지 않는다.
    public struct DiagnosticState: Equatable, Sendable {
        public let stage: DiagnosticStage
        public let updatedAtUptime: TimeInterval
        public let isReady: Bool

        public init(
            stage: DiagnosticStage,
            updatedAtUptime: TimeInterval,
            isReady: Bool
        ) {
            self.stage = stage
            self.updatedAtUptime = updatedAtUptime
            self.isReady = isReady
        }
    }

    /// 두 번째 복사를 감지하면 원문 콜백보다 먼저 동기 호출한다.
    /// 번역 창이 포커스를 가져가기 전에 원래 앱과 입력 위치를 저장할 수 있다.
    public var onWillCapture: ((DoubleCopyCaptureContext) -> Void)?

    /// 복사한 문자열과 같은 changeCount에서 읽은 public.html을 함께 전달한다.
    /// HTML이 없거나 `CopiedMathNormalizer.maximumHTMLBytes`를 넘으면 nil이다.
    public var onCopiedText: ((String, String?, Int32, TimeInterval) -> Void)?

    public var onFailure: ((Failure) -> Void)?

    /// 원문·앱 이름 없이 감시 준비와 복사 쌍의 진행 단계를 전달한다.
    public var onDiagnostic: ((DiagnosticState) -> Void)?

    public private(set) var isRunning = false
    public private(set) var lastFailure: Failure?
    public private(set) var diagnosticState: DiagnosticState

    /// 입력 모니터링 탭이 설치되고 활성화되어 단축키를 받을 수 있는 상태다.
    public var isReady: Bool {
        isRunning && eventTapHealthy
    }

    /// 설정을 다시 열 때 캐시된 준비 상태 대신 실제 키 이벤트 수신 가능 여부를 확인한다.
    public func verifyReadiness() -> Bool {
        guard isRunning, eventTapHealthy, let tap = eventTap, let id = eventTapID,
              CGEvent.tapIsEnabled(tap: tap),
              let info = ownEventTaps().first(where: { $0.eventTapID == id }) else { return false }
        return Self.includesCopyEvents(info.eventsOfInterest)
    }

    private struct FirstCopyObservation {
        let sourceProcessIdentifier: Int32
        let application: NSRunningApplication?
    }

    public let configuration: Configuration
    private let processIdentifier: Int32
    private let pasteboard: NSPasteboard
    private var detector: DoubleCopyDetector
    // 실행 중에는 메인 액터에서만 접근한다. nonisolated(unsafe)는
    // deinit에서 탭을 해제해 비소유 userInfo 포인터가 남지 않도록 하기 위해 필요하다.
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?
    private let workspaceNotifications: NotificationCenter
    private var firstCopy: FirstCopyObservation?
    private var pasteboardTask: Task<Void, Never>?
    private var gestureGeneration: UInt64 = 0
    private var eventTapHealthy = false
    private var eventTapID: UInt32?

    public init(
        configuration: Configuration = Configuration(),
        pasteboard: NSPasteboard = .general,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.configuration = configuration
        self.pasteboard = pasteboard
        self.processIdentifier = processIdentifier
        workspaceNotifications = NSWorkspace.shared.notificationCenter
        detector = DoubleCopyDetector(window: configuration.pairWindow)
        diagnosticState = DiagnosticState(
            stage: .stopped,
            updatedAtUptime: ProcessInfo.processInfo.systemUptime,
            isReady: false
        )
    }

    deinit {
        if let activationObserver { workspaceNotifications.removeObserver(activationObserver) }
        pasteboardTask?.cancel()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }

    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return isReady }

        lastFailure = nil
        eventTapHealthy = false
        updateDiagnostic(.checkingPermission)

        // 사전 확인과 실제 사용 가능 상태가 다를 수 있어, OS가 권한을 검사하는
        // 수신 전용 탭 생성을 최종 판단으로 사용한다. 권한 요청은 UI에서만 한다.
        let preflightAllowed = CGPreflightListenEventAccess()

        updateDiagnostic(.creatingEventTap)
        let previousIDs = Set(ownEventTaps().map(\.eventTapID))

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: deepKDoubleCopyEventMask,
            callback: deepKDoubleCopyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            reportFailure(preflightAllowed ? .eventTapCreationFailed : .inputMonitoringPermissionRequired)
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            reportFailure(.runLoopSourceCreationFailed)
            return false
        }

        eventTap = tap
        runLoopSource = source
        isRunning = true
        guard let info = ownEventTaps().first(where: { !previousIDs.contains($0.eventTapID) }) else {
            stop()
            reportFailure(.eventTapCreationFailed)
            return false
        }
        // OS가 허용하지 않은 키 이벤트를 제거할 수 있어 탭 생성만으로 준비 완료를 판단하지 않는다.
        guard Self.includesCopyEvents(info.eventsOfInterest) else {
            stop()
            reportFailure(.inputMonitoringPermissionRequired)
            return false
        }
        eventTapID = info.eventTapID
        eventTapHealthy = true
        activationObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let firstCopy = self.firstCopy,
                      let activatedPID,
                      activatedPID != firstCopy.sourceProcessIdentifier else { return }
                self.cancelGesture(reason: .applicationChanged)
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            reportFailure(.eventTapRecoveryFailed)
            return false
        }
        updateDiagnostic(.ready)
        return true
    }

    /// 감시와 클립보드 확인을 중단하고, 재시작 때 이전 복사를 재사용하지 않도록 상태를 비운다.
    public func stop() {
        cancelGesture()
        if let activationObserver { workspaceNotifications.removeObserver(activationObserver) }
        activationObserver = nil

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        eventTapID = nil
        isRunning = false
        eventTapHealthy = false
        updateDiagnostic(.stopped)
    }

    fileprivate func reenableEventTap() {
        guard isRunning, let eventTap else { return }
        eventTapHealthy = false
        updateDiagnostic(.recoveringEventTap)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        // tapEnable은 실패를 반환하지 않으므로 실제 탭 상태를 다시 읽는다.
        guard CGEvent.tapIsEnabled(tap: eventTap),
              let info = ownEventTaps().first(where: { $0.eventTapID == eventTapID }),
              Self.includesCopyEvents(info.eventsOfInterest) else {
            reportFailure(.eventTapRecoveryFailed)
            return
        }
        eventTapHealthy = true
        updateDiagnostic(.eventTapRecovered)
    }

    static func includesCopyEvents(_ mask: CGEventMask) -> Bool {
        mask & deepKDoubleCopyEventMask == deepKDoubleCopyEventMask
    }

    /// Chromium 계열은 복사할 때 출처 URL 타입을 함께 쓰고 public.html을 미리 써 둔다.
    static let chromiumSourceURLType = NSPasteboard.PasteboardType("org.chromium.source-url")

    /// 수식 정리에 쓸 public.html이다. 다른 앱은 HTML을 읽는 순간에 만들 수 있어(지연 제공) 그동안
    /// 메인 액터가 멈추므로, Chromium 복사에서만 읽는다. 크기 상한을 넘으면 nil이다.
    static func copiedHTML(from pasteboard: NSPasteboard) -> String? {
        guard pasteboard.pasteboardItems?.contains(where: { $0.types.contains(chromiumSourceURLType) }) == true,
              let data = pasteboard.data(forType: .html), data.count <= CopiedMathNormalizer.maximumHTMLBytes
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// nspasteboard.org 관례 타입이다. 1Password·Bitwarden·KeePassXC 같은 비밀번호 관리자가 붙인다.
    static let sensitivePasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    ]

    static func isConcealed(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.pasteboardItems?.contains { !sensitivePasteboardTypes.isDisjoint(with: $0.types) } ?? false
    }

    /// 한 번의 poll에서 읽은 pasteboard 상태다.
    struct PasteboardRead {
        let changeCount: Int
        /// 읽는 동안 다른 앱이 쓰지 않았다(읽기 전후 changeCount가 같다).
        let isStable: Bool
        let containsFileURL: Bool
        let isConcealed: Bool
        let text: String?
        let html: String?
    }

    /// 민감 항목은 문자열을 읽기 전에 거절해 원문이 앱 메모리에도 남지 않게 한다.
    /// 수식 정리에 쓸 HTML도 같은 전후 비교 안에서 읽는다. 파싱은 여기서 하지 않는다.
    static func readPasteboard(_ pasteboard: NSPasteboard) -> PasteboardRead {
        let changeCountBeforeRead = pasteboard.changeCount
        let containsFileURL = pasteboard.pasteboardItems?.contains { $0.types.contains(.fileURL) } ?? false
        let isConcealed = isConcealed(pasteboard)
        let text = isConcealed ? nil : pasteboard.string(forType: .string)
        let html = text == nil ? nil : copiedHTML(from: pasteboard)
        let changeCountAfterRead = pasteboard.changeCount
        return PasteboardRead(
            changeCount: changeCountAfterRead,
            isStable: changeCountBeforeRead == changeCountAfterRead,
            containsFileURL: containsFileURL,
            isConcealed: isConcealed,
            text: text,
            html: html
        )
    }

    /// 표시 확인을 기다리는 성공 후보다.
    struct PendingCapture {
        let changeCount: Int
        let text: String
        let html: String?
    }

    /// 문자열을 먼저 쓰고 민감 표시를 따로 붙이는 앱이 있다(arboard를 쓰는 1Password·Bitwarden).
    /// 표시를 붙여도 changeCount가 오르지 않아 읽기 전후 비교로는 그 사이를 구분하지 못한다.
    /// 그래서 다음 poll에서 같은 항목에 표시가 없을 때만 확정한다. 항목이 바뀌었으면 nil이다.
    static func confirmCapture(_ pending: PendingCapture, on pasteboard: NSPasteboard) -> Result<PendingCapture, Failure>? {
        guard pasteboard.changeCount == pending.changeCount else { return nil }
        return isConcealed(pasteboard) ? .failure(.clipboardConcealed) : .success(pending)
    }

    /// 변경 횟수가 같으면 이전 복사 값일 수 있으므로 문자열이 있어도 거절한다.
    static func captureResult(
        changeCount: Int,
        baselineChangeCount: Int,
        text: String?,
        containsFileURL: Bool = false,
        isConcealed: Bool = false
    ) -> Result<String, Failure> {
        guard changeCount != baselineChangeCount else {
            return .failure(.clipboardNotUpdated)
        }
        guard !isConcealed else {
            return .failure(.clipboardConcealed)
        }
        guard !containsFileURL else {
            return .failure(.clipboardNonText)
        }
        guard let text else {
            return .failure(.clipboardNonText)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.clipboardTextEmpty)
        }
        return .success(text)
    }

    private func ownEventTaps() -> [CGEventTapInformation] {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success else { return [] }
        let capacity = count + 8
        var taps = Array(repeating: CGEventTapInformation(), count: Int(capacity))
        guard CGGetEventTapList(capacity, &taps, &count) == .success else { return [] }
        return taps.prefix(Int(min(count, capacity))).filter { $0.tappingProcess == processIdentifier }
    }

    fileprivate func consumeKeyboardEvent(_ event: DoubleCopyKeyboardEvent) {
        guard isRunning else { return }

        let sourcePID = event.processIdentifier
        guard sourcePID != processIdentifier else { return }

        let eventTimestamp = ProcessInfo.processInfo.systemUptime
        let keyEvent = DoubleCopyDetector.KeyEvent(
            timestamp: event.timestamp,
            processIdentifier: sourcePID,
            keyCode: event.keyCode,
            modifiers: event.modifiers,
            phase: event.phase,
            isAutorepeat: event.isAutorepeat
        )

        let outcome = detector.receive(keyEvent)

        switch outcome {
        case .waitingForSecondCopy:
            guard isCopyCandidate(keyEvent) else { return }
            beginFirstCopy(sourceProcessIdentifier: sourcePID)
        case .triggered:
            guard isCopyCandidate(keyEvent) else { return }
            beginSecondCopy(
                sourceProcessIdentifier: sourcePID,
                triggerUptime: eventTimestamp
            )
        case .reset:
            cancelGesture(reason: firstCopy == nil ? nil : .unrelatedInput)
        case .ignored:
            break
        }
    }

    private func isCopyCandidate(_ event: DoubleCopyDetector.KeyEvent) -> Bool {
        event.phase == .keyDown
            && event.keyCode == detector.configuration.copyKeyCode
            && !event.isAutorepeat
            && event.modifiers == detector.configuration.commandModifiers
    }

    private func beginFirstCopy(
        sourceProcessIdentifier: Int32
    ) {
        if let previousCopy = firstCopy {
            let resetReason: ResetReason = previousCopy.sourceProcessIdentifier == sourceProcessIdentifier
                ? .pairWindowExpired
                : .applicationChanged
            updateDiagnostic(.gestureReset(resetReason))
        }
        cancelPasteboardTask()
        gestureGeneration &+= 1

        firstCopy = FirstCopyObservation(
            sourceProcessIdentifier: sourceProcessIdentifier,
            application: NSRunningApplication(processIdentifier: sourceProcessIdentifier)
        )
        updateDiagnostic(.firstCopyDetected)
    }

    private func beginSecondCopy(
        sourceProcessIdentifier: Int32,
        triggerUptime: TimeInterval
    ) {
        guard let firstCopy,
              firstCopy.sourceProcessIdentifier == sourceProcessIdentifier
        else {
            finishFailure(.clipboardTextUnavailable)
            return
        }

        cancelPasteboardTask()
        gestureGeneration &+= 1
        let generation = gestureGeneration
        let changeCountAtTrigger = pasteboard.changeCount
        updateDiagnostic(.secondCopyDetected)
        let context = DoubleCopyCaptureContext(
            sourceProcessIdentifier: sourceProcessIdentifier,
            application: firstCopy.application ?? NSRunningApplication(processIdentifier: sourceProcessIdentifier),
            triggerUptime: triggerUptime
        )

        // 콜백이 번역 창을 열어 포커스를 바꾸기 전에 원래 앱을 저장한다.
        onWillCapture?(context)

        guard isRunning else { return }
        updateDiagnostic(.waitingForClipboard)
        pasteboardTask = Task { @MainActor [weak self] in
            await self?.pollSecondCopy(
                generation: generation,
                changeCountAtTrigger: changeCountAtTrigger,
                context: context
            )
        }
    }

    private func pollSecondCopy(
        generation: UInt64,
        changeCountAtTrigger: Int,
        context: DoubleCopyCaptureContext
    ) async {
        let deadline = context.triggerUptime + configuration.pasteboardWait
        var observedFreshChange = false
        var latestFailure: Failure?
        var pending: PendingCapture?

        /// 후보를 확정했으면 true다. 표시가 붙었으면 실패를 기록하고, 항목이 바뀌었으면 다시 읽는다.
        func settle(_ candidate: PendingCapture) -> Bool {
            switch Self.confirmCapture(candidate, on: pasteboard) {
            case .success(let capture)?:
                finishSuccess(text: capture.text, html: capture.html, context: context)
                return true
            case .failure(let failure)?:
                latestFailure = failure
                return false
            case nil:
                return false
            }
        }

        while !Task.isCancelled {
            guard generation == gestureGeneration, self.firstCopy != nil else { return }

            if let candidate = pending {
                pending = nil
                if settle(candidate) { return }
            }

            // 두 번째 키 입력 뒤의 변경 횟수로 새 복사를 확인한다.
            // 같은 문자열을 다시 복사할 수 있으므로 문자열 비교로 판단하지 않는다.
            if pasteboard.changeCount != changeCountAtTrigger {
                observedFreshChange = true
                let read = Self.readPasteboard(pasteboard)

                // clearContents()와 setString() 사이 또는 다른 앱의 동시
                // 쓰기 중간 상태는 확정하지 않고 다음 poll에서 다시 읽는다.
                if read.isStable {
                    switch Self.captureResult(
                        changeCount: read.changeCount,
                        baselineChangeCount: changeCountAtTrigger,
                        text: read.text,
                        containsFileURL: read.containsFileURL,
                        isConcealed: read.isConcealed
                    ) {
                    case .success(let text):
                        pending = PendingCapture(changeCount: read.changeCount, text: text, html: read.html)
                    case .failure(let failure):
                        latestFailure = failure
                    }
                }
            }

            let now = ProcessInfo.processInfo.systemUptime
            if now >= deadline {
                // 마지막 poll에서 잡은 후보는 더 기다리지 않고 바로 확인한다.
                if let candidate = pending, settle(candidate) { return }
                // 문자열이 늦게 채워지는 pasteboard는 deadline까지 기다린 뒤
                // 마지막으로 관측한 새 항목의 유형을 안내한다.
                finishFailure(latestFailure ?? (observedFreshChange ? .clipboardNonText : .clipboardNotUpdated))
                return
            }

            await sleepForPollingInterval()
        }
    }

    private func sleepForPollingInterval() async {
        let nanoseconds = UInt64(configuration.pollInterval * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func finishSuccess(text: String, html: String?, context: DoubleCopyCaptureContext) {
        cancelGesture()
        updateDiagnostic(.clipboardCaptured)
        onCopiedText?(text, html, context.sourceProcessIdentifier, context.triggerUptime)
    }

    private func finishFailure(_ failure: Failure) {
        cancelGesture()
        reportFailure(failure)
    }

    private func cancelGesture(reason: ResetReason? = nil) {
        cancelPasteboardTask()
        gestureGeneration &+= 1
        firstCopy = nil
        detector.reset()
        if let reason {
            updateDiagnostic(.gestureReset(reason))
        }
    }

    private func cancelPasteboardTask() {
        pasteboardTask?.cancel()
        pasteboardTask = nil
    }

    private func reportFailure(_ failure: Failure) {
        lastFailure = failure
        updateDiagnostic(.failed(failure))
        onFailure?(failure)
    }

    private func updateDiagnostic(_ stage: DiagnosticStage) {
        let state = DiagnosticState(
            stage: stage,
            updatedAtUptime: ProcessInfo.processInfo.systemUptime,
            isReady: isReady
        )
        diagnosticState = state
        onDiagnostic?(state)
    }
}

private func deepKDoubleCopyEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<DoubleCopyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            monitor.reenableEventTap()
        }
        return Unmanaged.passUnretained(event)
    }

    let phase: DoubleCopyDetector.KeyEvent.Phase
    switch type {
    case .keyDown:
        phase = .keyDown
    case .keyUp:
        phase = .keyUp
    case .flagsChanged:
        // 보조 키는 flagsChanged로만 전달된다. Command 전환은 복사 쌍을 유지하도록
        // 감지기에 전달하고, 다른 보조 키 입력은 대기 중인 쌍을 취소한다.
        phase = flagsChangedPhase(
            keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags
        )
    default:
        return Unmanaged.passUnretained(event)
    }

    // 하드웨어 이벤트의 발신 PID는 0일 수 있고 합성 이벤트는 발신 프로세스를 가리킨다.
    // 실제로 키를 받는 앱을 일관되게 식별하려면 대상 PID를 사용해야 한다.
    let sourcePIDValue = event.getIntegerValueField(.eventSourceUnixProcessID)
    let targetPIDValue = event.getIntegerValueField(.eventTargetUnixProcessID)
    let processIdentifierValue = targetPIDValue > 0 ? targetPIDValue : sourcePIDValue
    guard processIdentifierValue > 0, processIdentifierValue <= Int64(Int32.max) else {
        return Unmanaged.passUnretained(event)
    }

    let snapshot = DoubleCopyKeyboardEvent(
        timestamp: Double(event.timestamp) / 1_000_000_000,
        processIdentifier: Int32(processIdentifierValue),
        keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
        modifiers: normalizedModifiers(from: event.flags),
        phase: phase,
        isAutorepeat: type == .keyDown
            && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    )

    MainActor.assumeIsolated {
        monitor.consumeKeyboardEvent(snapshot)
    }
    return Unmanaged.passUnretained(event)
}

private func normalizedModifiers(from flags: CGEventFlags) -> DoubleCopyModifiers {
    var modifiers: DoubleCopyModifiers = []
    if flags.contains(.maskCommand) { modifiers.insert(.command) }
    if flags.contains(.maskShift) { modifiers.insert(.shift) }
    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
    if flags.contains(.maskControl) { modifiers.insert(.control) }
    return modifiers
}

private func flagsChangedPhase(
    keyCode: UInt16,
    flags: CGEventFlags
) -> DoubleCopyDetector.KeyEvent.Phase {
    let isDown: Bool

    switch keyCode {
    case DoubleCopyDetector.leftCommandKeyCode, DoubleCopyDetector.rightCommandKeyCode:
        isDown = flags.contains(.maskCommand)
    case 56, 60: // 왼쪽·오른쪽 Shift 키
        isDown = flags.contains(.maskShift)
    case 58, 61: // 왼쪽·오른쪽 Option 키
        isDown = flags.contains(.maskAlternate)
    case 59, 62: // 왼쪽·오른쪽 Control 키
        isDown = flags.contains(.maskControl)
    case 57: // Caps Lock 키
        isDown = flags.contains(.maskAlphaShift)
    case 63: // Fn 키
        isDown = flags.contains(.maskSecondaryFn)
    default:
        // 알 수 없는 보조 키 입력도 기존 복사 쌍을 취소하도록 키 누름으로 처리한다.
        isDown = true
    }

    return isDown ? .keyDown : .keyUp
}

private extension UInt16 {
    init(clamping value: Int64) {
        if value < 0 {
            self = 0
        } else if value > Int64(UInt16.max) {
            self = UInt16.max
        } else {
            self = UInt16(value)
        }
    }
}
