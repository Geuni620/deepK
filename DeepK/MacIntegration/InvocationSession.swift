import AppKit
import ApplicationServices
import Foundation

/// 호출 도중 권한 창이 뜨지 않도록 손쉬운 사용 권한은 조회만 한다.
/// 필요한 권한 안내와 시스템 설정 이동은 UI가 담당한다.
public enum AccessibilityPermissionStatus: String, Equatable, Sendable {
    case granted
    case denied
}

public enum InvocationSessionPhase: String, Equatable, Sendable {
    case captured
    case restored
    case insertionAttempted
    case inserted
    case invalidated
}

public struct InvocationTextRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    fileprivate init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    fileprivate var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

public struct InvocationApplication: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let name: String
    public let launchDate: Date?

    fileprivate init(application: NSRunningApplication) {
        processIdentifier = application.processIdentifier
        bundleIdentifier = application.bundleIdentifier
        name = application.localizedName
            ?? application.bundleIdentifier
            ?? "Unknown application"
        launchDate = application.launchDate
    }
}

public enum InvocationAXOperation: String, Equatable, Sendable {
    case readFocusedElement
    case readRole
    case readEditableState
    case readSelectedText
    case readSelectedTextRange
    case readValue
    case readFocusedState
    case checkSettable
    case setSelectedText
    case setFocusedState
    case activateApplication
    case verifyReadback
}

public enum InvocationFallbackReason: Equatable, Sendable {
    case accessibilityPermissionDenied
    case targetApplicationUnavailable
    case targetElementUnavailable
    case targetChanged
    case selectionChanged
    case insertionAttributeUnsupported
    case insertionRejected(code: Int32)
    case readbackUnavailable
    case readbackMismatch
    case focusRestorationUnavailable
    case pasteboardApplicationUnsupported
    case pasteboardSnapshotUnavailable
    case pasteboardWriteFailed
    case pasteboardEventUnavailable
    case pasteboardChanged
    case pasteboardReadbackMismatch
    case pasteboardTimeout
    case pasteboardRestoreFailed
}

public enum InvocationSessionError: Error, Equatable, Sendable {
    case accessibilityPermissionDenied
    case noFrontmostExternalApplication
    case applicationTerminated
    case focusedElementUnavailable
    case focusedElementNotEditable
    case selectedTextUnavailable
    case selectedTextRangeUnavailable
    case staleSession
    case targetApplicationChanged
    case targetElementChanged
    case targetNotFocused
    case selectionChanged
    case selectedTextAttributeNotSettable
    case accessibility(operation: InvocationAXOperation, code: Int32)
    case copyFallbackRequired(InvocationFallbackReason)

    /// 삽입을 검증하지 못한 경우 UI에서 수동 복사를 제공해야 한다.
    public var requiresCopyFallback: Bool {
        switch self {
        case .accessibilityPermissionDenied,
             .noFrontmostExternalApplication,
             .applicationTerminated,
             .focusedElementUnavailable,
             .focusedElementNotEditable,
             .selectedTextUnavailable,
             .selectedTextRangeUnavailable,
             .targetApplicationChanged,
             .targetElementChanged,
             .targetNotFocused,
             .selectionChanged,
             .selectedTextAttributeNotSettable,
             .copyFallbackRequired:
            return true
        case .staleSession,
             .accessibility:
            return true
        }
    }

    fileprivate var isRestorationTargetMismatch: Bool {
        switch self {
        case .copyFallbackRequired(.targetApplicationUnavailable),
             .copyFallbackRequired(.targetChanged),
             .copyFallbackRequired(.selectionChanged):
            return true
        default:
            return false
        }
    }
}

public struct FocusRestorationReceipt: Equatable, Sendable {
    public let sessionID: UUID
    public let application: InvocationApplication
    public let restoredAt: Date

    fileprivate init(sessionID: UUID, application: InvocationApplication) {
        self.sessionID = sessionID
        self.application = application
        restoredAt = Date()
    }
}

public struct VerifiedInsertionReceipt: Equatable, Sendable {
    public let sessionID: UUID
    public let replacement: String
    public let resultingValue: String
    public let resultingSelection: InvocationTextRange
    public let resultingSelectedText: String
    public let insertedAt: Date

    fileprivate init(
        sessionID: UUID,
        replacement: String,
        resultingValue: String,
        resultingSelection: InvocationTextRange,
        resultingSelectedText: String
    ) {
        self.sessionID = sessionID
        self.replacement = replacement
        self.resultingValue = resultingValue
        self.resultingSelection = resultingSelection
        self.resultingSelectedText = resultingSelectedText
        insertedAt = Date()
    }
}

/// 호출 대상은 고정하고 phase로 포커스 복원과 삽입의 재시도 가능 여부를 관리한다.
@MainActor
public final class InvocationSession {
    public let id: UUID
    public let application: InvocationApplication
    public let selectedText: String?
    public let selectedRange: InvocationTextRange?
    public let capturedValue: String?
    public let focusedRole: String?
    public let isEditable: Bool
    public let capturedAt: Date

    public private(set) var phase: InvocationSessionPhase = .captured

    private let runningApplication: NSRunningApplication
    private let focusedElement: AXUIElement

    private init(
        id: UUID,
        application: NSRunningApplication,
        selectedText: String?,
        selectedRange: InvocationTextRange?,
        capturedValue: String?,
        focusedRole: String?,
        isEditable: Bool,
        focusedElement: AXUIElement
    ) {
        self.id = id
        self.application = InvocationApplication(application: application)
        self.selectedText = selectedText
        self.selectedRange = selectedRange
        self.capturedValue = capturedValue
        self.focusedRole = focusedRole
        self.isEditable = isEditable
        capturedAt = Date()
        runningApplication = application
        self.focusedElement = focusedElement
    }

    /// 시작 시에도 권한 창을 띄우지 않고 신뢰 상태만 조회한다.
    public static var accessibilityPermissionStatus: AccessibilityPermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    public static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// 실제 검증한 브라우저에만 클립보드 삽입을 제공한다.
    /// 호출자가 경로를 미리 선택해야 하며 insert(_:) 실패 후 자동으로 전환하지 않는다.
    public static let pasteboardInsertionBundleIdentifier = "com.google.Chrome"

    /// 번역 창이 열리기 전에 원래 앱의 입력 요소와 선택 범위를 저장한다.
    /// 전체 원문은 삽입 후 검증에 사용한다. 원문이나 선택 범위를 읽을 수 없어도
    /// 포커스 복원용으로 대상은 보관하되, 삽입 시에는 수동 복사를 안내한다.
    public static func capture(
        excludingProcessIdentifier: Int32? = ProcessInfo.processInfo.processIdentifier,
        excludingBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Result<InvocationSession, InvocationSessionError> {
        guard accessibilityPermissionStatus == .granted else {
            return .failure(.accessibilityPermissionDenied)
        }

        guard let application = NSWorkspace.shared.frontmostApplication,
              !application.isTerminated else {
            return .failure(.noFrontmostExternalApplication)
        }

        if application.processIdentifier == excludingProcessIdentifier
            || (excludingBundleIdentifier != nil
                && application.bundleIdentifier == excludingBundleIdentifier) {
            return .failure(.noFrontmostExternalApplication)
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedRead = copyAttribute(
            from: applicationElement,
            named: kAXFocusedUIElementAttribute,
            operation: .readFocusedElement
        )

        guard focusedRead.error == .success,
              let focusedRaw = focusedRead.value,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return .failure(.focusedElementUnavailable)
        }

        let focusedElement = focusedRaw as! AXUIElement

        let isEditable: Bool
        switch editableState(of: focusedElement) {
        case .success(let value):
            isEditable = value
        case .failure:
            // 편집 가능 여부가 불확실해도 포커스 복원을 위해 대상은 유지한다.
            isEditable = false
        }

        let selectedText = stringAttribute(
            from: focusedElement,
            named: kAXSelectedTextAttribute,
            operation: .readSelectedText
        )

        let selectedRange = textRangeAttribute(
            from: focusedElement,
            named: kAXSelectedTextRangeAttribute,
            operation: .readSelectedTextRange
        )

        let role = stringAttribute(
            from: focusedElement,
            named: kAXRoleAttribute,
            operation: .readRole
        )

        let value = stringAttribute(
            from: focusedElement,
            named: kAXValueAttribute,
            operation: .readValue
        )

        return .success(
            InvocationSession(
                id: UUID(),
                application: application,
                selectedText: selectedText,
                selectedRange: selectedRange,
                capturedValue: value,
                focusedRole: role,
                isEditable: isEditable,
                focusedElement: focusedElement
            )
        )
    }

    public func invalidate() {
        phase = .invalidated
    }

    /// 원래 프로세스·입력 요소·선택 범위가 일치할 때만 포커스를 복원한다.
    /// 앱 활성화는 비동기이므로 메인 액터를 양보하며 최대 300ms 동안 확인한다.
    public func restoreFocus() async -> Result<FocusRestorationReceipt, InvocationSessionError> {
        guard phase != .invalidated else {
            return .failure(.staleSession)
        }
        guard Self.accessibilityPermissionStatus == .granted else {
            return .failure(.copyFallbackRequired(.accessibilityPermissionDenied))
        }
        guard let application = validatedRunningApplication() else {
            return .failure(.copyFallbackRequired(.targetApplicationUnavailable))
        }

        switch validateOriginalTarget(
            requireFrontmost: false,
            requireFocused: false,
            requireSelection: false,
            compareCapturedValue: true
        ) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        guard application.activate(options: [.activateAllWindows]) else {
            return .failure(.copyFallbackRequired(.focusRestorationUnavailable))
        }

        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        while ContinuousClock.now < deadline {
            guard !Task.isCancelled else {
                return .failure(.copyFallbackRequired(.focusRestorationUnavailable))
            }

            guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier else {
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }

            switch validateOriginalTarget(
                requireFrontmost: true,
                requireFocused: false,
                requireSelection: false,
                compareCapturedValue: true
            ) {
            case .failure(let error):
                if error.isRestorationTargetMismatch {
                    return .failure(error)
                }
                try? await Task.sleep(for: .milliseconds(10))
                continue
            case .success:
                break
            }

            let focusError = AXUIElementSetAttributeValue(
                focusedElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            guard focusError == .success else {
                return .failure(.copyFallbackRequired(.focusRestorationUnavailable))
            }

            switch validateOriginalTarget(
                requireFrontmost: true,
                requireFocused: true,
                requireSelection: false,
                compareCapturedValue: true
            ) {
            case .failure(let error):
                if error.isRestorationTargetMismatch {
                    return .failure(error)
                }
                try? await Task.sleep(for: .milliseconds(10))
            case .success:
                phase = .restored
                return .success(
                    FocusRestorationReceipt(sessionID: id, application: self.application)
                )
            }
        }

        return .failure(.copyFallbackRequired(.focusRestorationUnavailable))
    }

    /// AX 선택 텍스트 속성으로 한 번만 삽입한다. 키 이벤트나 클립보드는 사용하지 않는다.
    /// 쓰기 성공 응답만 믿지 않고 전체 값과 선택 범위를 다시 읽어 검증한다.
    /// 지원하지 않거나 검증할 수 없는 대상은 수동 복사를 안내한다.
    public func insert(
        _ replacement: String
    ) -> Result<VerifiedInsertionReceipt, InvocationSessionError> {
        guard phase == .captured || phase == .restored else {
            return .failure(.staleSession)
        }
        guard Self.accessibilityPermissionStatus == .granted else {
            return .failure(.copyFallbackRequired(.accessibilityPermissionDenied))
        }
        guard isEditable,
              selectedText != nil,
              let selectedRange,
              let capturedValue else {
            return .failure(.copyFallbackRequired(.readbackUnavailable))
        }

        switch validateOriginalTarget(
            requireFrontmost: true,
            requireFocused: true,
            requireSelection: true,
            compareCapturedValue: true
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let snapshot):
            guard snapshot.value == capturedValue else {
                return .failure(.copyFallbackRequired(.selectionChanged))
            }
        }

        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard settableError == .success else {
            return .failure(
                .copyFallbackRequired(.insertionRejected(code: settableError.rawValue))
            )
        }
        guard settable.boolValue else {
            return .failure(.copyFallbackRequired(.insertionAttributeUnsupported))
        }

        // 오류 응답 뒤에도 대상 앱이 쓰기를 늦게 반영할 수 있으므로 중복 삽입을 막기 위해 재시도하지 않는다.
        phase = .insertionAttempted

        let setError = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )
        guard setError == .success else {
            return .failure(
                .copyFallbackRequired(.insertionRejected(code: setError.rawValue))
            )
        }

        guard let resultingValue = Self.stringAttribute(
            from: focusedElement,
            named: kAXValueAttribute,
            operation: .verifyReadback
        ),
        let resultingText = Self.stringAttribute(
            from: focusedElement,
            named: kAXSelectedTextAttribute,
            operation: .verifyReadback
        ),
        let resultingRange = Self.textRangeAttribute(
            from: focusedElement,
            named: kAXSelectedTextRangeAttribute,
            operation: .verifyReadback
        ),
        let expectedValue = Self.replacing(
            range: selectedRange.nsRange,
            in: capturedValue,
            with: replacement
        ) else {
            return .failure(.copyFallbackRequired(.readbackUnavailable))
        }

        guard resultingValue == expectedValue,
              isPlausiblePostInsertionSelection(
                  replacement: replacement,
                  originalSelection: selectedRange,
                  resultingText: resultingText,
                  resultingRange: resultingRange
              ) else {
            return .failure(.copyFallbackRequired(.readbackMismatch))
        }

        phase = .inserted
        return .success(
            VerifiedInsertionReceipt(
                sessionID: id,
                replacement: replacement,
                resultingValue: resultingValue,
                resultingSelection: resultingRange,
                resultingSelectedText: resultingText
            )
        )
    }

    /// 검증한 브라우저에 클립보드로 한 번만 삽입한다. AX 쓰기 뒤 붙여넣으면
    /// 늦게 반영된 쓰기와 중복될 수 있으므로 AX 삽입을 먼저 시도하지 않는다.
    /// 클립보드는 변경 횟수가 이 작업과 일치할 때만 복원해 사용자의 새 복사를 보존한다.
    /// 키 전달 이후에는 시간 초과나 검증 실패가 발생해도 재시도하지 않는다.
    public func insertUsingPasteboard(
        _ replacement: String
    ) async -> Result<VerifiedInsertionReceipt, InvocationSessionError> {
        guard phase == .captured || phase == .restored else {
            return .failure(.staleSession)
        }
        guard Self.accessibilityPermissionStatus == .granted else {
            return .failure(.copyFallbackRequired(.accessibilityPermissionDenied))
        }
        guard application.bundleIdentifier
                == Self.pasteboardInsertionBundleIdentifier else {
            return .failure(
                .copyFallbackRequired(.pasteboardApplicationUnsupported)
            )
        }
        guard isEditable,
              focusedRole == kAXTextAreaRole,
              let selectedText,
              let selectedRange,
              let capturedValue else {
            return .failure(.copyFallbackRequired(.readbackUnavailable))
        }

        switch validateOriginalTarget(
            requireFrontmost: true,
            requireFocused: true,
            requireSelection: true,
            compareCapturedValue: true
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let snapshot):
            guard snapshot.selectedText == selectedText,
                  snapshot.selectedRange == selectedRange,
                  snapshot.value == capturedValue else {
                return .failure(.copyFallbackRequired(.selectionChanged))
            }
        }

        guard let expectedValue = Self.replacing(
            range: selectedRange.nsRange,
            in: capturedValue,
            with: replacement
        ) else {
            return .failure(.copyFallbackRequired(.readbackUnavailable))
        }

        let pasteboard = NSPasteboard.general
        guard let originalPasteboard = Self.snapshotPasteboard(pasteboard),
              pasteboard.changeCount == originalPasteboard.changeCount else {
            return .failure(
                .copyFallbackRequired(.pasteboardSnapshotUnavailable)
            )
        }

        guard Self.writeReplacement(
            replacement,
            to: pasteboard,
            expectedChangeCount: originalPasteboard.changeCount
        ),
        let ownChangeCount = Self.currentPasteboardChangeCount(
            pasteboard,
            greaterThan: originalPasteboard.changeCount
        ) else {
            return .failure(.copyFallbackRequired(.pasteboardWriteFailed))
        }

        // 키 누름이 대상에 도달했을 수 있으므로 이벤트 전달 전에 재시도를 차단한다.
        phase = .insertionAttempted

        guard Self.postPaste(to: application.processIdentifier) else {
            _ = Self.restorePasteboardIfOwned(
                originalPasteboard,
                to: pasteboard,
                ownChangeCount: ownChangeCount
            )
            return .failure(
                .copyFallbackRequired(.pasteboardEventUnavailable)
            )
        }

        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while ContinuousClock.now < deadline {
            guard !Task.isCancelled else {
                return finishPasteboardFailure(
                    .pasteboardTimeout,
                    originalPasteboard: originalPasteboard,
                    pasteboard: pasteboard,
                    ownChangeCount: ownChangeCount
                )
            }

            guard pasteboard.changeCount == ownChangeCount else {
                return .failure(.copyFallbackRequired(.pasteboardChanged))
            }

            guard validatedRunningApplication() != nil,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                      == application.processIdentifier else {
                return finishPasteboardFailure(
                    .targetChanged,
                    originalPasteboard: originalPasteboard,
                    pasteboard: pasteboard,
                    ownChangeCount: ownChangeCount
                )
            }

            if let snapshot = postPasteSnapshot(
                expectedValue: expectedValue,
                replacement: replacement,
                originalSelection: selectedRange
            ),
            let resultingValue = snapshot.value,
            let resultingText = snapshot.selectedText,
            let resultingRange = snapshot.selectedRange {
                guard pasteboard.changeCount == ownChangeCount else {
                    return .failure(
                        .copyFallbackRequired(.pasteboardChanged)
                    )
                }
                guard Self.restorePasteboardIfOwned(
                    originalPasteboard,
                    to: pasteboard,
                    ownChangeCount: ownChangeCount
                ) else {
                    return .failure(
                        .copyFallbackRequired(.pasteboardRestoreFailed)
                    )
                }

                phase = .inserted
                return .success(
                    VerifiedInsertionReceipt(
                        sessionID: id,
                        replacement: replacement,
                        resultingValue: resultingValue,
                        resultingSelection: resultingRange,
                        resultingSelectedText: resultingText
                    )
                )
            }

            try? await Task.sleep(for: .milliseconds(10))
        }

        return finishPasteboardFailure(
            .pasteboardTimeout,
            originalPasteboard: originalPasteboard,
            pasteboard: pasteboard,
            ownChangeCount: ownChangeCount
        )
    }

    private func postPasteSnapshot(
        expectedValue: String,
        replacement: String,
        originalSelection: InvocationTextRange
    ) -> TargetSnapshot? {
        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        let focusedRead = Self.copyAttribute(
            from: applicationElement,
            named: kAXFocusedUIElementAttribute,
            operation: .readFocusedElement
        )
        guard focusedRead.error == .success,
              let focusedRaw = focusedRead.value,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return nil
        }

        let currentFocusedElement = focusedRaw as! AXUIElement
        guard Self.stringAttribute(
            from: currentFocusedElement,
            named: kAXRoleAttribute,
            operation: .readRole
        ) == focusedRole else {
            return nil
        }

        let candidates: [AXUIElement]
        if CFEqual(currentFocusedElement, focusedElement) {
            candidates = [focusedElement]
        } else {
            // Chrome은 textarea 값이 바뀌면 AX 객체를 새로 만들 수 있다.
            // 역할과 전체 값·선택 범위가 일치할 때만 객체 교체를 허용한다.
            candidates = [currentFocusedElement]
        }

        for candidate in candidates {
            guard let value = Self.stringAttribute(
                from: candidate,
                named: kAXValueAttribute,
                operation: .verifyReadback
            ),
            let selectedText = Self.stringAttribute(
                from: candidate,
                named: kAXSelectedTextAttribute,
                operation: .verifyReadback
            ),
            let selectedRange = Self.textRangeAttribute(
                from: candidate,
                named: kAXSelectedTextRangeAttribute,
                operation: .verifyReadback
            ),
            value == expectedValue,
            isPlausiblePostInsertionSelection(
                replacement: replacement,
                originalSelection: originalSelection,
                resultingText: selectedText,
                resultingRange: selectedRange
            ) else {
                continue
            }

            return TargetSnapshot(
                value: value,
                selectedText: selectedText,
                selectedRange: selectedRange
            )
        }
        return nil
    }

    private func finishPasteboardFailure(
        _ reason: InvocationFallbackReason,
        originalPasteboard: PasteboardSnapshot,
        pasteboard: NSPasteboard,
        ownChangeCount: Int
    ) -> Result<VerifiedInsertionReceipt, InvocationSessionError> {
        guard pasteboard.changeCount == ownChangeCount else {
            return .failure(.copyFallbackRequired(.pasteboardChanged))
        }
        guard Self.restorePasteboardIfOwned(
            originalPasteboard,
            to: pasteboard,
            ownChangeCount: ownChangeCount
        ) else {
            return .failure(.copyFallbackRequired(.pasteboardRestoreFailed))
        }
        return .failure(.copyFallbackRequired(reason))
    }

    private struct TargetSnapshot {
        let value: String?
        let selectedText: String?
        let selectedRange: InvocationTextRange?
    }

    private struct PasteboardValue: Equatable {
        let type: String
        let data: Data
    }

    private struct PasteboardItemSnapshot: Equatable {
        let values: [PasteboardValue]
    }

    private struct PasteboardSnapshot: Equatable {
        let items: [PasteboardItemSnapshot]
        let changeCount: Int
    }

    private final class PasteboardWriter: NSObject, NSPasteboardWriting {
        let values: [String: Data]

        init(values: [String: Data]) {
            self.values = values
        }

        func writableTypes(
            for pasteboard: NSPasteboard
        ) -> [NSPasteboard.PasteboardType] {
            values.keys.map(NSPasteboard.PasteboardType.init(rawValue:))
        }

        func pasteboardPropertyList(
            forType type: NSPasteboard.PasteboardType
        ) -> Any? {
            values[type.rawValue]
        }
    }

    private func validatedRunningApplication() -> NSRunningApplication? {
        guard !runningApplication.isTerminated,
              let current = NSRunningApplication(
                  processIdentifier: runningApplication.processIdentifier
              ),
              !current.isTerminated,
              current.processIdentifier == application.processIdentifier,
              current.bundleIdentifier == application.bundleIdentifier else {
            return nil
        }

        if let capturedLaunchDate = application.launchDate,
           current.launchDate != capturedLaunchDate {
            return nil
        }

        return current
    }

    private func validateOriginalTarget(
        requireFrontmost: Bool,
        requireFocused: Bool,
        requireSelection: Bool,
        compareCapturedValue: Bool
    ) -> Result<TargetSnapshot, InvocationSessionError> {
        guard let application = validatedRunningApplication() else {
            return .failure(.copyFallbackRequired(.targetApplicationUnavailable))
        }

        if requireFrontmost {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier else {
                return .failure(.copyFallbackRequired(.targetChanged))
            }
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedRead = Self.copyAttribute(
            from: applicationElement,
            named: kAXFocusedUIElementAttribute,
            operation: .readFocusedElement
        )
        guard focusedRead.error == .success,
              let focusedRaw = focusedRead.value,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return .failure(.copyFallbackRequired(.targetElementUnavailable))
        }

        let currentFocusedElement = focusedRaw as! AXUIElement
        guard CFEqual(currentFocusedElement, focusedElement) else {
            return .failure(.copyFallbackRequired(.targetChanged))
        }

        if requireFocused {
            guard let focused = Self.boolAttribute(
                from: focusedElement,
                named: kAXFocusedAttribute,
                operation: .readFocusedState
            ), focused else {
                return .failure(.copyFallbackRequired(.targetElementUnavailable))
            }
        }

        if requireSelection {
            guard Self.editableState(of: focusedElement) == .success(true) else {
                return .failure(.copyFallbackRequired(.targetElementUnavailable))
            }
        }

        let currentSelectedText = Self.stringAttribute(
            from: focusedElement,
            named: kAXSelectedTextAttribute,
            operation: .readSelectedText
        )
        let currentSelectedRange = Self.textRangeAttribute(
            from: focusedElement,
            named: kAXSelectedTextRangeAttribute,
            operation: .readSelectedTextRange
        )

        if requireSelection {
            guard let capturedSelectedText = selectedText,
                  let capturedSelectedRange = selectedRange,
                  currentSelectedText == capturedSelectedText,
                  currentSelectedRange == capturedSelectedRange else {
                return .failure(.copyFallbackRequired(.selectionChanged))
            }
        }

        let currentValue = Self.stringAttribute(
            from: focusedElement,
            named: kAXValueAttribute,
            operation: .readValue
        )
        if compareCapturedValue, let capturedValue {
            guard currentValue == capturedValue else {
                return .failure(.copyFallbackRequired(.selectionChanged))
            }
        }

        return .success(
            TargetSnapshot(
                value: currentValue,
                selectedText: currentSelectedText,
                selectedRange: currentSelectedRange
            )
        )
    }

    private func isPlausiblePostInsertionSelection(
        replacement: String,
        originalSelection: InvocationTextRange,
        resultingText: String,
        resultingRange: InvocationTextRange
    ) -> Bool {
        let originalRange = originalSelection.nsRange
        let replacementLength = replacement.utf16.count
        let collapsedRange = InvocationTextRange(
            location: originalRange.location + replacementLength,
            length: 0
        )
        let replacementRange = InvocationTextRange(
            location: originalRange.location,
            length: replacementLength
        )

        // 삽입한 텍스트가 선택되거나 커서가 끝으로 이동하는 경우 모두 정상이다.
        // 다만 다시 읽은 선택 텍스트가 해당 상태와 일치해야 한다.
        if resultingRange == originalSelection {
            return resultingText == replacement
        }
        if resultingRange == replacementRange {
            return resultingText == replacement
        }
        return resultingRange == collapsedRange && resultingText.isEmpty
    }

    private static func replacing(
        range: NSRange,
        in value: String,
        with replacement: String
    ) -> String? {
        let nsValue = value as NSString
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= nsValue.length else {
            return nil
        }
        return nsValue.replacingCharacters(in: range, with: replacement)
    }

    private static func snapshotPasteboard(
        _ pasteboard: NSPasteboard
    ) -> PasteboardSnapshot? {
        let items = pasteboard.pasteboardItems ?? []
        var snapshots: [PasteboardItemSnapshot] = []
        snapshots.reserveCapacity(items.count)

        for item in items {
            var values: [PasteboardValue] = []
            values.reserveCapacity(item.types.count)
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    return nil
                }
                values.append(
                    PasteboardValue(type: type.rawValue, data: data)
                )
            }
            values.sort { $0.type < $1.type }
            snapshots.append(PasteboardItemSnapshot(values: values))
        }

        return PasteboardSnapshot(
            items: snapshots,
            changeCount: pasteboard.changeCount
        )
    }

    private static func writeReplacement(
        _ replacement: String,
        to pasteboard: NSPasteboard,
        expectedChangeCount: Int
    ) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            return false
        }
        _ = pasteboard.clearContents()
        return pasteboard.setString(replacement, forType: .string)
    }

    private static func currentPasteboardChangeCount(
        _ pasteboard: NSPasteboard,
        greaterThan previousChangeCount: Int
    ) -> Int? {
        let changeCount = pasteboard.changeCount
        return changeCount > previousChangeCount ? changeCount : nil
    }

    private static func restorePasteboardIfOwned(
        _ snapshot: PasteboardSnapshot,
        to pasteboard: NSPasteboard,
        ownChangeCount: Int
    ) -> Bool {
        guard pasteboard.changeCount == ownChangeCount else {
            return false
        }

        _ = pasteboard.clearContents()
        if !snapshot.items.isEmpty {
            let writers = snapshot.items.map { snapshotItem in
                PasteboardWriter(
                    values: Dictionary(
                        uniqueKeysWithValues: snapshotItem.values.map {
                            ($0.type, $0.data)
                        }
                    )
                )
            }
            guard pasteboard.writeObjects(writers) else {
                return false
            }
        }

        guard let restored = snapshotPasteboard(pasteboard) else {
            return false
        }
        return restored.items == snapshot.items
    }

    private static func postPaste(to processIdentifier: Int32) -> Bool {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 9,
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 9,
            keyDown: false
        ) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }

    private static func copyAttribute(
        from element: AXUIElement,
        named attribute: String,
        operation: InvocationAXOperation
    ) -> (error: AXError, value: CFTypeRef?) {
        _ = operation
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        return (error, value)
    }

    private static func stringAttribute(
        from element: AXUIElement,
        named attribute: String,
        operation: InvocationAXOperation
    ) -> String? {
        let result = copyAttribute(from: element, named: attribute, operation: operation)
        guard result.error == .success,
              let value = result.value else {
            return nil
        }
        return value as? String
    }

    private static func boolAttribute(
        from element: AXUIElement,
        named attribute: String,
        operation: InvocationAXOperation
    ) -> Bool? {
        let result = copyAttribute(from: element, named: attribute, operation: operation)
        guard result.error == .success,
              let value = result.value else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func textRangeAttribute(
        from element: AXUIElement,
        named attribute: String,
        operation: InvocationAXOperation
    ) -> InvocationTextRange? {
        let result = copyAttribute(from: element, named: attribute, operation: operation)
        guard result.error == .success,
              let rawValue = result.value,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range),
              range.location >= 0,
              range.length >= 0 else {
            return nil
        }

        return InvocationTextRange(
            location: range.location,
            length: range.length
        )
    }

    private static func editableState(
        of element: AXUIElement
    ) -> Result<Bool, InvocationSessionError> {
        let editable = copyAttribute(
            from: element,
            named: kAXIsEditableAttribute,
            operation: .readEditableState
        )
        if editable.error == .success,
           let value = editable.value,
           let isEditable = (value as? NSNumber)?.boolValue {
            return .success(isEditable)
        }

        // 일부 웹 기반·구형 컨트롤은 AXIsEditable을 제공하지 않는다.
        // 이 경우 알려진 편집 가능 역할만 허용하고 정적 텍스트와 알 수 없는 역할은 거부한다.
        guard let role = stringAttribute(
            from: element,
            named: kAXRoleAttribute,
            operation: .readRole
        ) else {
            return .failure(.focusedElementNotEditable)
        }

        let editableRoles: Set<String> = [
            kAXTextFieldRole,
            kAXTextAreaRole,
            kAXComboBoxRole
        ]
        return .success(editableRoles.contains(role))
    }
}

/// 활성 호출을 하나만 유지하고 새 대상을 저장하기 전에 이전 세션을 무효화한다.
@MainActor
public final class InvocationSessionCoordinator {
    public private(set) var activeSession: InvocationSession?

    private let excludedProcessIdentifier: Int32?
    private let excludedBundleIdentifier: String?

    public init(
        excludingProcessIdentifier: Int32? = ProcessInfo.processInfo.processIdentifier,
        excludingBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.excludedProcessIdentifier = excludingProcessIdentifier
        self.excludedBundleIdentifier = excludingBundleIdentifier
    }

    public func capture() -> Result<InvocationSession, InvocationSessionError> {
        activeSession?.invalidate()
        activeSession = nil
        let result = InvocationSession.capture(
            excludingProcessIdentifier: excludedProcessIdentifier,
            excludingBundleIdentifier: excludedBundleIdentifier
        )
        if case .success(let session) = result {
            activeSession = session
        }
        return result
    }

    public func restoreFocus(
        for session: InvocationSession
    ) async -> Result<FocusRestorationReceipt, InvocationSessionError> {
        guard activeSession?.id == session.id else {
            return .failure(.staleSession)
        }
        return await session.restoreFocus()
    }

    public func insert(
        _ replacement: String,
        into session: InvocationSession
    ) -> Result<VerifiedInsertionReceipt, InvocationSessionError> {
        guard activeSession?.id == session.id else {
            return .failure(.staleSession)
        }
        return session.insert(replacement)
    }

    public func invalidate(_ session: InvocationSession? = nil) {
        guard let activeSession,
              session == nil || activeSession.id == session?.id else {
            return
        }
        activeSession.invalidate()
        self.activeSession = nil
    }
}
