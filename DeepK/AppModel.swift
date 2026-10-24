import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class AppModel: NSObject, NSWindowDelegate {
    static let shared = AppModel()

    let client: CodexTranslationClient
    let claudeClient: ClaudeTranslationClient
    let store: TranslationStore
    let windowPresentation = WindowPresentation()
    let loginItemController = LoginItemController()
    /// 편집 메뉴 ⌘↩ '끝에 구분선 넣기'의 target. 덧붙일 글은 경계 규칙(planner)이 정한다.
    let sourceEditor = SourceEditorProxy(insertion: IncrementalTranslationPlanner.boundaryInsertion(after:))
    var models: [CodexTranslationClient.Model] = []
    var selectedProvider = TranslationSelection.load(from: .standard).provider
    var selectedModel = TranslationSelection.load(from: .standard).model
    /// 선택값과 분리해 두 제공자의 연결·인증 상태를 각각 보존한다.
    var providerStates: [TranslationProvider: ProviderState] = Dictionary(
        uniqueKeysWithValues: TranslationProvider.allCases.map {
            ($0, .notChecked(message: "연결 확인 전"))
        }
    )
    var providerModels: [TranslationProvider: [TranslationModelOption]] = [:]
    var providerAccountLabels: [TranslationProvider: String] = [:]
    /// 마지막 Codex 연결 확인에서 실제로 실행한(또는 실행하려 한) 실행 파일이다.
    var codexExecutableInfo: CodexTranslationClient.ExecutableInfo?
    /// Codex 번역에 Fast(priority) 계층을 쓸지 여부다. 기본은 꺼짐(default 계층)이다.
    var codexFastServiceTier = UserDefaults.standard.bool(forKey: "codexFastServiceTier")
    var requestModelLabel: String?
    var providerMessages: [TranslationProvider: String] = [.codex: "연결 확인 전", .claude: "연결 확인 전"]
    var connectionMessage = "번역 연결 확인 중"
    var connecting = false
    var showSettings = false
    var feedback = ""
    var shortcutReady = false
    var shortcutEnabled = UserDefaults.standard.object(forKey: "shortcutEnabled") as? Bool ?? true
    var copyFormat = ResultCopyFormat.load(from: .standard)
    /// 결과 창의 코드 스타일과 표시 동작이다. 열린 결과 창은 바뀌면 바로 다시 칠한다.
    var resultDisplay = ResultDisplaySettings.load(from: .standard)
    /// The settings window shows the code style picker (620 wide) instead of the tabs.
    var showsCodeStylePicker = false
    var accessibilityReady = AXIsProcessTrusted()
    var inputMonitoringAllowed = CGPreflightListenEventAccess()
    var shortcutMessage = TranslationFooterState.shortcutChecking
    var captureMessage: String?
    var shortcutDiagnostic = "감시 시작 전"
    var inserting = false
    var elapsedMilliseconds: Int?
    /// 원래 위치에 삽입할 수 없는 이유. 하단 문구가 아니라 복사 버튼의 툴팁이며, 호출이 바뀌면 지운다.
    private(set) var insertionNote: String?
    /// 복사가 성공했다. '복사' 버튼이 누른 자리에서 약 2초 '복사됨'으로 바뀐다(하단 왼쪽 상태 칸은 버튼에서 멀다).
    private(set) var copyConfirmed = false
    static let copyFailedMessage = "복사하지 못했습니다"

    /// 지금 안내가 단축키 감시 실패 문구다. 앱이 활성화될 때마다 다시 서므로, 하단은 진행 중·실패한 번역을 이 문구로
    /// 가리지 않는다(`TranslationFooterState.Input.feedbackIsStanding`).
    var feedbackIsShortcutFailure: Bool { !feedback.isEmpty && feedback == shortcutFailureFeedback }

    /// '전체 다시 번역'(결과 창 오른쪽 클릭 메뉴)을 지금 시작할 수 있다.
    var canRetranslateWholeDocument: Bool {
        captureMessage == nil && store.engineReady && !store.isComposing && store.status != .translating
    }

    var inputMonitoringStatusText: String {
        if !shortcutEnabled { return "감시 꺼짐" }
        if shortcutReady { return "감지 중" }
        return "감시 연결 안 됨"
    }

    var accessibilityStatusText: String {
        accessibilityReady ? "연결됨" : "앱 연결 미확인"
    }

    var permissionConnectionHelp: String {
        "시스템 설정의 허용 여부와 현재 실행 중인 앱의 연결 상태는 다를 수 있습니다. 이미 허용했다면 앱을 다시 열어 주세요. 계속 연결되지 않으면 기존 deepK 항목을 현재 앱으로 다시 등록해 주세요."
    }

    @ObservationIgnored private var window: NSWindow?
    /// Set once by `presentSettingsWindow`; the tests give it an offscreen window instead.
    @ObservationIgnored var settingsWindow: NSWindow?
    /// The screen area the settings window stays inside. Replaced in tests, whose window is offscreen.
    @ObservationIgnored var settingsScreenFrame: (NSWindow) -> CGRect = { ($0.screen ?? NSScreen.main)?.visibleFrame ?? .zero }
    /// The settings frame the last resize made and how far the screen edges pushed it; undone on the way back
    /// unless the window was moved in between.
    @ObservationIgnored private var settingsFrameShift: (frame: NSRect, shift: CGVector)?
    /// A resize animation is running: the window's frame is passing by, and `settingsFrameShift.frame` is where it ends.
    @ObservationIgnored private var settingsFrameAnimating = false
    /// Counts resizes, so only the latest animation's end clears `settingsFrameAnimating`.
    @ObservationIgnored private var settingsResizes: UInt64 = 0
    /// Where the display settings are saved. Replaced in tests so they never touch the app's settings.
    @ObservationIgnored var displayDefaults = UserDefaults.standard
    /// Stepping through styles saves only the last one, once the keys rest.
    @ObservationIgnored private var displaySaves = LatestValueCoalescer<ResultDisplaySettings>(interval: .milliseconds(300))
    @ObservationIgnored private var displaySaveTask: Task<Void, Never>?
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var originalApplication: NSRunningApplication?
    @ObservationIgnored private var invocation: InvocationSession? {
        didSet { if insertionNote != nil { insertionNote = nil } }
    }
    @ObservationIgnored private let monitor = DoubleCopyMonitor()
    @ObservationIgnored private var requestStarted: TimeInterval?
    @ObservationIgnored private var launched = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var shortcutMenuItem: NSMenuItem?
    @ObservationIgnored private var shortcutFailureFeedback: String?
    @ObservationIgnored private var briefFeedbackGeneration: UInt64 = 0
    @ObservationIgnored private var copyConfirmationGeneration: UInt64 = 0
    @ObservationIgnored private var invocationGeneration: UInt64 = 0
    @ObservationIgnored private var providerConnectionGenerations: [TranslationProvider: UInt64] = [:]
    @ObservationIgnored private var disconnectedByUser = Set<TranslationProvider>()
    @ObservationIgnored private var refreshingAccounts = false
    @ObservationIgnored private var pendingCopy: (text: String, version: UInt64)?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var systemAsleep = false
    /// Claude 클라이언트에 마지막으로 보낸 대기 프로세스 모델과 세대 번호다.
    /// 클라이언트는 이전 세대의 늦게 도착한 호출을 무시한다.
    @ObservationIgnored private var appliedClaudePrewarmModel: String?
    @ObservationIgnored private var claudePrewarmGeneration: UInt64 = 0
    @ObservationIgnored private var lastClaudeTypingHint: TimeInterval = 0
    @ObservationIgnored private var appliedCodexPrewarmModel: String?
    @ObservationIgnored private var appliedCodexPrewarmFastServiceTier = false
    @ObservationIgnored private var codexPrewarmGeneration: UInt64 = 0
    @ObservationIgnored private var systemSleepGeneration: UInt64 = 0
    @ObservationIgnored private var lastCodexTypingHint: TimeInterval = 0
    @ObservationIgnored private var firstPartialLoggedRequestID: UUID?
    @ObservationIgnored private var finalLoggedResultID: UUID?
    /// 같은 트리거(`requestStarted`)에서 원문 반복으로 다시 요청한 횟수다.
    @ObservationIgnored private var echoRetries: (trigger: TimeInterval?, count: Int) = (nil, 0)

    /// 지연 측정용 로그다. 원문·번역문 없이 ms만 남긴다.
    private static let latencyLog = Logger(subsystem: "com.deepk.app", category: "latency")

    override init() {
        let backend = CodexTranslationClient(configuration: .init(
            prewarmEnabled: UserDefaults.standard.object(forKey: "codexPrewarmEnabled") as? Bool ?? true,
            preserveOpaqueLiterals: UserDefaults.standard.object(forKey: "codexPreserveOpaqueLiterals") as? Bool ?? true,
            // 새 app-server를 띄울 때마다 읽으므로 `defaults write` 뒤 재실행 없이 '연결 해제 → 연결 확인'으로 반영된다.
            userExecutablePathProvider: { UserDefaults.standard.string(forKey: "codexExecutablePath") }
        ))
        client = backend
        let claudePath = UserDefaults.standard.string(forKey: "claudeExecutablePath")
        // 비상 스위치: `defaults write com.deepk.app claudeTransport oneShotJSON`이면 재빌드 없이 기존 경로로 돌아간다.
        // 이때는 구독 증명 재사용과 백그라운드 확인도 끄고, 매 번역 전에 `auth status`를 확인한다.
        let claudeTransport = UserDefaults.standard.string(forKey: "claudeTransport")
            .flatMap(ClaudeTranslationClient.Configuration.Transport.init(rawValue:)) ?? .automatic
        let usesLegacyClaudePath = claudeTransport == .oneShotJSON
        let claude = ClaudeTranslationClient(configuration: .init(
            executableURL: claudePath.map { URL(fileURLWithPath: $0) },
            transport: claudeTransport,
            subscriptionProofMaxAge: usesLegacyClaudePath ? 0 : 30,
            subscriptionRefreshInterval: usesLegacyClaudePath ? 0 : 25
        ))
        claudeClient = claude
        store = TranslationStore(configuration: .init(), engineReady: false,
                                 cacheContext: TranslationSelection.load(from: .standard).cacheContext, translator: { request in
            let (selection, codexFastServiceTier) = try await MainActor.run {
                try Task.checkCancellation()
                let app = AppModel.shared
                guard app.store.isActiveRequest(request) else { throw CancellationError() }
                let provider = request.provider.flatMap(TranslationProvider.init(rawValue:)) ?? app.selectedProvider
                let model = request.model ?? TranslationSelection.model(for: provider, in: .standard)
                let selection = TranslationSelection(provider: provider, model: model)
                // 요청 시점의 선택을 고정해 늦은 응답이나 UI 선택 변경으로
                // 이미 표시 중인 결과의 실제 모델 이름이 덮이지 않게 한다.
                app.requestModelLabel = request.modelLabel ?? selection.label
                // Codex 계층도 같은 시점에 고정한다. 진행 중인 번역은 토글 변경의 영향을 받지 않는다.
                // 대기 스레드·설정 화면과 같은 값을 써야 (모델, 계층)이 어긋나 대기 스레드를 못 쓰는 일이 없다.
                return (selection, app.codexFastServiceTier)
            }
            switch selection.provider {
            case .codex:
                do {
                    let text = try await backend.translate(
                        text: request.modelInput,
                        source: request.sourceLanguage.rawValue,
                        target: request.targetLanguage.rawValue,
                        model: selection.model,
                        fastServiceTier: codexFastServiceTier,
                        inlineMarkup: request.usesInlineMarkup,
                        onPartialText: { text in
                            Task { @MainActor in
                                AppModel.shared.receivePartialText(text, for: request)
                            }
                        }
                    )
                    await MainActor.run {
                        let app = AppModel.shared
                        guard app.store.isActiveRequest(request) else { return }
                        app.markProviderConnected(.codex, message: "Codex 구독 연결됨")
                    }
                    return text
                } catch {
                    await MainActor.run {
                        let app = AppModel.shared
                        guard app.store.isActiveRequest(request) else { return }
                        app.markProviderFailure(.codex, error: error, disconnectEngine: false)
                    }
                    throw error
                }
            case .claude:
                do {
                    let text = try await claude.translate(
                        text: request.modelInput,
                        source: request.sourceLanguage.rawValue,
                        target: request.targetLanguage.rawValue,
                        model: selection.model,
                        inlineMarkup: request.usesInlineMarkup,
                        onPartialText: { text in
                            Task { @MainActor in
                                AppModel.shared.receivePartialText(text, for: request)
                            }
                        }
                    )
                    await MainActor.run {
                        let app = AppModel.shared
                        guard app.store.isActiveRequest(request) else { return }
                        app.markProviderConnected(.claude, message: "Claude Code 연결 확인됨")
                    }
                    return text
                } catch {
                    await MainActor.run {
                        let app = AppModel.shared
                        guard app.store.isActiveRequest(request) else { return }
                        app.markProviderFailure(.claude, error: error, disconnectEngine: false)
                    }
                    throw error
                }
            }
        })
        super.init()
        // 비상 스위치: `defaults write com.deepk.app outputEchoRetry -bool false`면 원문을 그대로 돌려준 답을 다시 요청하지 않고
        // 경고와 함께 보여 준다. `outputHanjaRepair -bool false`면 한국어 결과에 섞인 한자를 그대로 둔다. 재실행하면 반영된다.
        store.applyOutputCheckSwitches(from: .standard)
        store.onOutputReport = { [weak self] in self?.reportOutputCheck($0) }
        let initialSelection = TranslationSelection.load(from: .standard)
        store.setTranslationContext(
            cacheContext: initialSelection.cacheContext,
            provider: initialSelection.provider.rawValue,
            model: initialSelection.model,
            modelLabel: initialSelection.label
        )
        if let raw = UserDefaults.standard.string(forKey: "translationDirection"),
           let direction = TranslationDirection(rawValue: raw) {
            store.setDirection(direction)
        }
    }

    var canInsert: Bool {
        captureMessage == nil && store.canInsert && invocation?.isEditable == true
            && invocation?.capturedValue != nil
            && invocation?.selectedRange != nil
            && invocation?.phase == .captured && !inserting
    }

    /// 연결 여부는 현재 기본 제공자와 무관하게 관찰한다.
    func providerState(for provider: TranslationProvider) -> ProviderState {
        providerStates[provider] ?? .notChecked(message: "연결 확인 전")
    }

    var selectedProviderState: ProviderState {
        providerState(for: selectedProvider)
    }

    var isSelectedModelAvailable: Bool {
        models(for: selectedProvider).contains { $0.model == selectedModel }
    }

    var requiresRetranslation: Bool {
        store.requiresRetranslation
    }

    func models(for provider: TranslationProvider) -> [TranslationModelOption] {
        providerModels[provider] ?? []
    }

    func accountLabel(for provider: TranslationProvider) -> String? {
        providerAccountLabels[provider]
    }

    func attach(_ window: NSWindow) {
        self.window = window
        windowPresentation.attach(window)
        window.delegate = self
        window.isReleasedWhenClosed = false
    }

    func start() {
        guard !launched else { return }
        launched = true
        installMenu()
        monitor.onDiagnostic = { [weak self] state in
            guard let self else { return }
            shortcutReady = state.isReady
            inputMonitoringAllowed = CGPreflightListenEventAccess()
            switch state.stage {
            case .stopped:
                shortcutDiagnostic = "감시 중지"
                captureMessage = nil
            case .checkingPermission: shortcutDiagnostic = "권한 확인 중"
            case .creatingEventTap: shortcutDiagnostic = "키 감시 시작 중"
            case .ready, .eventTapRecovered:
                shortcutDiagnostic = "단축키 입력 대기"
                shortcutMessage = TranslationFooterState.shortcutWatching
                clearShortcutFailureFeedback()
            case .firstCopyDetected: shortcutDiagnostic = "첫 번째 복사 감지"
            case .secondCopyDetected: shortcutDiagnostic = "두 번째 복사 감지"
            case .waitingForClipboard: shortcutDiagnostic = "클립보드 갱신 확인 중"
            case .clipboardCaptured: shortcutDiagnostic = "이번 복사 확인 완료"
            case .recoveringEventTap: shortcutDiagnostic = "키 감시 복구 중"
            case .failed: shortcutDiagnostic = "감시 또는 복사 확인 실패"
            case .gestureReset:
                shortcutDiagnostic = "입력 간격 또는 앱 변경으로 호출 취소"
                if captureMessage != nil {
                    captureMessage = nil
                    feedback = "호출이 취소됐습니다. 원래 앱에서 다시 복사해 주세요"
                    originalApplication = nil
                    invocation?.invalidate()
                    invocation = nil
                }
            }
            updateShortcutMenu()
        }
        monitor.onWillCapture = { [weak self] context in
            self?.invocationGeneration &+= 1
            self?.originalApplication = context.application
            self?.invocation?.invalidate()
            self?.invocation = nil
            self?.requestStarted = context.triggerUptime
            self?.elapsedMilliseconds = nil
            guard let self else { return }
            pendingCopy = nil
            // 새 호출의 결과는 아직 복사하지 않았다.
            if copyConfirmed { copyConfirmed = false }
            // 첫 번째 ⌘C는 모든 앱의 복사라 쓰지 않고, 호출이 확정된 두 번째 ⌘C부터 준비한다.
            hintCodex()
            hintClaude(.capture)
            captureMessage = "복사한 텍스트를 확인하는 중…"
            showWindow(activate: false, nearPointer: true)
        }
        monitor.onCopiedText = { [weak self] plain, html, sourcePID, uptime in
            guard let self else { return }
            // 원문 창에 보이는 글자와 번역·중복 판정에 쓰는 글자가 같도록 한 번만 정리한다.
            // 수식이 없을 때만 링크·인라인 코드를 원문 구조로 붙인다.
            let importStart = DispatchTime.now().uptimeNanoseconds
            let source = RichSourceImporter.copiedSource(plain: plain, html: html)
            let text = source.plain
            if html != nil {
                let elapsed = (DispatchTime.now().uptimeNanoseconds - importStart) / 1_000_000
                let links = source.markup?.links.count ?? 0, code = source.markup?.code.count ?? 0
                // 앱이 펜스를 씌운 블록, 그중 제목이 있는 블록, 지운 꾸밈 글자(줄이나 줄 끝) 수만 남긴다.
                let blocks = source.markup?.blocks ?? [], titles = blocks.filter { $0.title != nil }.count
                Self.latencyLog.notice("copy import \(elapsed, privacy: .public) ms links=\(links, privacy: .public) code=\(code, privacy: .public) blocks=\(blocks.count, privacy: .public) titles=\(titles, privacy: .public) chrome=\(source.removed.count, privacy: .public)")
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID else {
                captureMessage = nil
                feedback = "호출 중 앱이 바뀌었습니다. 원래 앱에서 다시 복사해 주세요"
                originalApplication = nil
                invocation?.invalidate()
                invocation = nil
                return
            }
            captureMessage = nil
            feedback = ""
            switch InvocationSession.capture() {
            case .success(let session):
                invocation = session
                if !session.isEditable { insertionNote = "읽기 전용 위치입니다. 복사를 사용하세요" }
            case .failure(.accessibilityPermissionDenied):
                accessibilityReady = AXIsProcessTrusted()
                insertionNote = "원래 위치에 삽입하기 위한 손쉬운 사용 연결을 확인하지 못했습니다. 복사는 사용할 수 있습니다"
            case .failure:
                insertionNote = "원래 입력 위치를 확인하지 못했습니다. 복사를 사용하세요"
            }
            requestStarted = uptime
            // Show the translation without deactivating the app the user is reading.
            showWindow(activate: false)
            store.invokeCopiedSource(source)
            if !store.engineReady { pendingCopy = (text, store.inputVersion) }
        }
        monitor.onFailure = { [weak self] failure in
            guard let self else { return }
            captureMessage = nil
            switch failure {
            case .inputMonitoringPermissionRequired:
                feedback = "현재 앱의 키 입력 감시가 연결되지 않았습니다. 이미 허용했다면 앱을 다시 열어 주세요"
                shortcutFailureFeedback = feedback
                shortcutMessage = "단축키 감시 연결 안 됨"
            case .clipboardTextUnavailable, .clipboardNotUpdated, .clipboardTextEmpty, .clipboardNonText, .clipboardConcealed:
                pendingCopy = nil
                store.editSource("", isComposing: false)
                switch failure {
                case .clipboardNotUpdated: feedback = "복사한 내용이 갱신되지 않았습니다. 텍스트를 선택해 다시 복사해 주세요"
                case .clipboardTextEmpty: feedback = "복사한 텍스트가 비어 있습니다. 번역할 문장을 선택해 주세요"
                case .clipboardNonText: feedback = "이미지·파일은 번역하지 않습니다. 텍스트를 선택해 주세요"
                case .clipboardConcealed: feedback = "비밀번호 등 민감한 항목으로 표시된 복사는 번역하지 않습니다"
                default: feedback = "이번에 복사한 텍스트를 확인할 수 없습니다"
                }
                showWindow()
            default:
                feedback = "단축키를 시작하지 못했습니다. 설정에서 다시 시도해 주세요"
                shortcutFailureFeedback = feedback
                shortcutMessage = "단축키 감시 시작 실패"
            }
            updateShortcutMenu()
        }
        restartShortcut()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartShortcut()
                if self?.showSettings == true {
                    Task { await self?.refreshProviderConnections() }
                }
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSystemAsleep(true) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSystemAsleep(false) }
            },
        ]
        if shortcutEnabled && !shortcutReady && !UserDefaults.standard.bool(forKey: "shortcutSetupShown") {
            UserDefaults.standard.set(true, forKey: "shortcutSetupShown")
            openSettings()
        }
        Task { await connect() }
    }

    private func beginProviderOperation(_ provider: TranslationProvider) -> UInt64 {
        let generation = (providerConnectionGenerations[provider] ?? 0) &+ 1
        providerConnectionGenerations[provider] = generation
        return generation
    }

    private func invalidateProviderOperation(_ provider: TranslationProvider) {
        _ = beginProviderOperation(provider)
        if providerState(for: provider).isConnecting {
            setProviderState(.notChecked(message: "연결 확인 전"), for: provider)
        }
    }

    private func isCurrentProviderOperation(_ provider: TranslationProvider, generation: UInt64) -> Bool {
        providerConnectionGenerations[provider] == generation
    }

    private func setProviderState(_ state: ProviderState, for provider: TranslationProvider) {
        providerStates[provider] = state
        providerMessages[provider] = state.message
        if provider == selectedProvider {
            connectionMessage = state.message
            connecting = state.isConnecting
        }
        if provider == .codex { updateCodexPrewarm() }
        if provider == .claude { updateClaudePrewarm() }
    }

    private func updateCodexPrewarm() {
        var desired: String?
        if selectedProvider == .codex, !disconnectedByUser.contains(.codex), isSelectedModelAvailable {
            switch providerState(for: .codex) {
            case .connected: desired = selectedModel
            case .connecting, .failure:
                if appliedCodexPrewarmModel == selectedModel { desired = selectedModel }
            case .notChecked, .cliMissing, .authenticationRequired: break
            }
        }
        let fast = codexFastServiceTier
        // 대기 스레드는 (모델, 계층) 쌍으로 식별한다. 계층만 바뀌어도 새로 준비한다.
        guard desired != appliedCodexPrewarmModel || fast != appliedCodexPrewarmFastServiceTier else { return }
        appliedCodexPrewarmModel = desired
        appliedCodexPrewarmFastServiceTier = fast
        codexPrewarmGeneration &+= 1
        let generation = codexPrewarmGeneration
        Task { await client.setPrewarm(model: desired, fastServiceTier: fast, generation: generation) }
    }

    private func hintCodex(typing: Bool = false) {
        guard appliedCodexPrewarmModel != nil else { return }
        if typing {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastCodexTypingHint >= 1 else { return }
            lastCodexTypingHint = now
        }
        Task { await client.warmUp() }
    }

    private func updateSystemSleep(_ asleep: Bool) {
        systemSleepGeneration &+= 1
        let generation = systemSleepGeneration
        Task<Void, Never> { await client.setSystemAsleep(asleep, generation: generation) }
    }

    private func markProviderConnected(_ provider: TranslationProvider, message: String) {
        setProviderState(.connected(message: message), for: provider)
        if provider == selectedProvider {
            store.setEngineReady(true)
        }
    }

    private func markProviderFailure(_ provider: TranslationProvider, error: Error, disconnectEngine: Bool = true) {
        let state = providerState(for: provider, error: error)
        setProviderState(state, for: provider)
        if disconnectEngine, provider == selectedProvider {
            store.setEngineReady(false)
        }
    }

    private func providerState(for provider: TranslationProvider, error: Error) -> ProviderState {
        switch provider {
        case .codex:
            guard let error = error as? CodexTranslationClient.ClientError else {
                return .failure(message: error.localizedDescription)
            }
            switch error {
            case let .processStartFailed(message):
                return .cliMissing(message: "Codex CLI를 찾거나 시작하지 못했습니다: \(message)")
            case .executableNotFound:
                return .cliMissing(message: "Codex CLI를 찾지 못했습니다")
            case let .executableUnsupported(details):
                return .cliMissing(message: "Codex \(CodexTranslationClient.minimumCodexVersion) 이상이 필요합니다: \(details)")
            case let .configuredExecutableInvalid(details):
                return .cliMissing(message: "지정한 Codex 경로를 실행할 수 없습니다: \(details)")
            case .notAuthenticated:
                return .authenticationRequired(message: "Codex ChatGPT 구독 로그인이 필요합니다")
            case let .unsupportedAccountType(type):
                return .authenticationRequired(message: "ChatGPT 구독 계정으로 로그인해 주세요 (현재 계정: \(type))")
            case let .modelUnavailable(model):
                return .failure(message: "선택한 Codex 모델을 사용할 수 없습니다: \(model)")
            default:
                return .failure(message: error.localizedDescription)
            }
        case .claude:
            guard let error = error as? ClaudeTranslationClient.ClientError else {
                return .failure(message: error.localizedDescription)
            }
            switch error {
            case let .cliUnavailable(message), let .processStartFailed(message):
                return .cliMissing(message: "Claude Code CLI를 찾거나 시작하지 못했습니다: \(message)")
            case let .authenticationRequired(message):
                return .authenticationRequired(message: message)
            case let .modelUnavailable(model):
                return .failure(message: "선택한 Claude Code 모델을 사용할 수 없습니다: \(model)")
            default:
                return .failure(message: error.localizedDescription)
            }
        }
    }

    /// Claude를 바로 번역에 쓸 수 있을 때만 대기 프로세스 모델을 정한다.
    private func desiredClaudePrewarmModel() -> String? {
        guard selectedProvider == .claude, !disconnectedByUser.contains(.claude), !systemAsleep,
              isSelectedModelAvailable else { return nil }
        switch providerState(for: .claude) {
        case .connected:
            return selectedModel
        case .connecting, .failure:
            // 연결 확인 중이거나 번역 오류처럼 일시적인 실패에서는 같은 모델의 대기 프로세스를 유지한다.
            return appliedClaudePrewarmModel == selectedModel ? selectedModel : nil
        case .notChecked, .cliMissing, .authenticationRequired:
            return nil
        }
    }

    /// 원하는 대기 프로세스 모델이 바뀌었으면 새 세대 번호와 함께 반환한다.
    private func nextClaudePrewarm() -> (model: String?, generation: UInt64)? {
        let model = desiredClaudePrewarmModel()
        guard model != appliedClaudePrewarmModel else { return nil }
        appliedClaudePrewarmModel = model
        claudePrewarmGeneration &+= 1
        return (model, claudePrewarmGeneration)
    }

    private func updateClaudePrewarm() {
        guard let prewarm = nextClaudePrewarm() else { return }
        Task { await claudeClient.setPrewarm(model: prewarm.model, generation: prewarm.generation) }
    }

    /// 사용자 의도가 보이면 Claude 대기 프로세스와 구독 확인을 미리 준비한다. 입력 힌트는 초당 한 번만 보낸다.
    private func hintClaude(_ hint: ClaudeTranslationClient.PrewarmHint) {
        guard appliedClaudePrewarmModel != nil else { return }
        if hint == .typing {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastClaudeTypingHint >= 1 else { return }
            lastClaudeTypingHint = now
        }
        Task { await claudeClient.warmUp(hint) }
    }

    /// 잠자기 동안 대기 프로세스와 구독 확인을 버린다. 깨어날 때는 대기 모델을 먼저 알린 뒤
    /// 재개해야 활동 창이 남아 있는 경우 클라이언트가 확인 후 다시 준비한다.
    private func setSystemAsleep(_ asleep: Bool) {
        systemAsleep = asleep
        updateSystemSleep(asleep)
        let prewarm = nextClaudePrewarm()
        Task {
            if asleep { await claudeClient.systemWillSleep() }
            if let prewarm {
                await claudeClient.setPrewarm(model: prewarm.model, generation: prewarm.generation)
            }
            if !asleep { await claudeClient.systemDidWake() }
        }
    }

    func refreshProviderConnections() async {
        guard !refreshingAccounts else { return }
        refreshingAccounts = true
        defer { refreshingAccounts = false }
        for provider in TranslationProvider.allCases where !disconnectedByUser.contains(provider) {
            await checkProviderConnection(provider)
        }
    }

    func connect() async {
        await checkProviderConnection(selectedProvider)
    }

    /// 설정의 "연결 확인"처럼 사용자가 명시적으로 누른 확인이다. 앱 활성화·설정 열기 같은
    /// 자동 확인과 달리 Claude의 stream 비활성화와 대기 프로세스 backoff도 초기화한다.
    func connectProvider(_ provider: TranslationProvider) async {
        if provider == .claude, !providerState(for: provider).isConnecting {
            await claudeClient.resetStreamingRecovery()
        }
        await checkProviderConnection(provider)
    }

    /// 한 제공자만 확인한다. 현재 기본 제공자를 바꾸거나 원문을 자동으로
    /// 다시 보내지 않으므로, 설정에서 다른 계정을 미리 연결해 둘 수 있다.
    private func checkProviderConnection(_ provider: TranslationProvider) async {
        disconnectedByUser.remove(provider)
        let currentState = providerState(for: provider)
        guard !currentState.isConnecting else { return }

        let generation = beginProviderOperation(provider)
        let preserveSelectedEngine = provider == selectedProvider
            && currentState.isConnected
            && store.engineReady
        setProviderState(.connecting(message: "\(provider.title) 연결 확인 중"), for: provider)
        if provider == selectedProvider, !preserveSelectedEngine {
            connecting = true
            connectionMessage = providerState(for: provider).message
            store.setEngineReady(false)
        } else if provider == selectedProvider {
            connecting = true
            connectionMessage = providerState(for: provider).message
        }

        defer {
            if provider == selectedProvider, isCurrentProviderOperation(provider, generation: generation) {
                connecting = false
            }
        }

        do {
            switch provider {
            case .codex:
                try await client.connect(forceRefresh: true)
                codexExecutableInfo = await client.executableInfo
                let availableModels = try await client.listModels(forceRefresh: true)
                guard isCurrentProviderOperation(provider, generation: generation) else { return }
                models = availableModels
                providerModels[.codex] = availableModels.map {
                    TranslationModelOption(id: $0.id, model: $0.model, displayName: $0.displayName)
                }
                if let account = await client.currentAccount {
                    providerAccountLabels[.codex] = account.email ?? account.planType ?? "ChatGPT 구독"
                }
            case .claude:
                try await claudeClient.connect(forceRefresh: true)
                let availableModels = try await claudeClient.listModels(forceRefresh: true)
                guard isCurrentProviderOperation(provider, generation: generation) else { return }
                providerModels[.claude] = availableModels.map {
                    TranslationModelOption(id: $0.id, model: $0.model, displayName: $0.displayName)
                }
                if let account = await claudeClient.currentAccount {
                    providerAccountLabels[.claude] = account
                }
            }

            guard isCurrentProviderOperation(provider, generation: generation) else { return }
            setProviderState(
                .connected(message: provider == .codex ? "Codex 구독 연결됨" : "Claude Code 연결됨"),
                for: provider
            )
            // 연결 중에 사용자가 기본 제공자·모델을 바꿨을 수 있다.
            // 완료 시점의 선택이 같은 경우에만 엔진을 준비하고 대기 중 복사를 처리한다.
            if provider == selectedProvider {
                let currentSelection = TranslationSelection(provider: provider, model: selectedModel)
                currentSelection.save(to: .standard)
                store.setEngineReady(isSelectedModelAvailable)
                if isSelectedModelAvailable {
                    flushPendingCopyIfReady(provider: provider, model: selectedModel)
                } else {
                    connectionMessage = "계정은 연결됐습니다. 사용 가능한 모델을 선택해 주세요"
                }
            }
        } catch {
            // 실패해도 어떤 실행 파일을 시도했는지(또는 찾지 못했는지) 설정에 보여 준다.
            if provider == .codex { codexExecutableInfo = await client.executableInfo }
            guard isCurrentProviderOperation(provider, generation: generation) else { return }
            markProviderFailure(provider, error: error)
        }
    }

    func changeProvider(_ provider: TranslationProvider) {
        guard provider != selectedProvider else { return }

        let previousProvider = selectedProvider
        invalidateProviderOperation(previousProvider)
        pendingCopy = nil
        selectedProvider = provider
        selectedModel = TranslationSelection.model(for: provider, in: .standard)
        let selection = TranslationSelection(provider: provider, model: selectedModel)
        selection.save(to: .standard)
        store.setTranslationContext(
            cacheContext: selection.cacheContext,
            provider: provider.rawValue,
            model: selectedModel,
            modelLabel: selection.label
        )
        store.setEngineReady(false)
        connectionMessage = providerState(for: provider).message
        connecting = providerState(for: provider).isConnecting
        if providerState(for: provider).isConnected {
            store.setEngineReady(isSelectedModelAvailable)
        } else if !providerState(for: provider).isConnecting {
            Task { await checkProviderConnection(provider) }
        }
        updateCodexPrewarm()
        updateClaudePrewarm()
    }

    func login() async {
        await loginProvider(selectedProvider)
    }

    /// Codex는 공식 브라우저 로그인을 시작하고, Claude는 CLI가 제공하는
    /// 로그인 경로를 안내한다. 두 경우 모두 로그인 뒤 별도의 연결 확인이 필요하다.
    func loginProvider(_ provider: TranslationProvider) async {
        guard !providerState(for: provider).isConnecting else { return }
        disconnectedByUser.remove(provider)
        let generation = beginProviderOperation(provider)
        setProviderState(.connecting(message: "로그인 준비 중…"), for: provider)
        switch provider {
        case .codex:
            do {
                let login = try await client.startChatGPTLogin()
                guard isCurrentProviderOperation(provider, generation: generation) else { return }
                NSWorkspace.shared.open(login.authURL)
                setProviderState(
                    .authenticationRequired(message: "브라우저에서 로그인한 뒤 연결 확인을 눌러 주세요"),
                    for: provider
                )
            } catch {
                guard isCurrentProviderOperation(provider, generation: generation) else { return }
                markProviderFailure(provider, error: error)
            }
        case .claude:
            guard isCurrentProviderOperation(provider, generation: generation) else { return }
            setProviderState(
                .authenticationRequired(message: "Claude Code CLI에서 구독 계정으로 로그인한 뒤 연결 확인을 눌러 주세요"),
                for: provider
            )
        }
    }

    func disconnect() async {
        await disconnectProvider(selectedProvider)
    }

    func disconnectProvider(_ provider: TranslationProvider) async {
        guard !providerState(for: provider).isConnecting else { return }
        disconnectedByUser.insert(provider)
        let generation = beginProviderOperation(provider)
        setProviderState(.connecting(message: "연결 해제 중…"), for: provider)
        let isSelected = provider == selectedProvider
        if isSelected {
            connecting = false
            pendingCopy = nil
            store.setEngineReady(false)
        }
        switch provider {
        case .codex: await client.disconnect()
        case .claude: await claudeClient.disconnect()
        }
        guard isCurrentProviderOperation(provider, generation: generation) else { return }
        setProviderState(
            .notChecked(message: "연결 해제됨 — 구독 로그인은 유지됩니다"),
            for: provider
        )
    }

    func logout() async {
        await logoutProvider(selectedProvider)
    }

    /// 로그아웃은 호출부의 확인창을 통과한 명시적 동작에서만 사용한다.
    /// Claude는 어댑터가 실제 로그아웃을 지원하지 않으므로 사용자 설정을 바꾸지 않는다.
    func logoutProvider(_ provider: TranslationProvider) async {
        guard !providerState(for: provider).isConnecting else { return }
        let generation = beginProviderOperation(provider)
        guard provider == .codex else {
            setProviderState(
                .failure(message: "Claude Code 로그아웃은 CLI에서 직접 관리해 주세요"),
                for: provider
            )
            return
        }
        disconnectedByUser.insert(provider)
        setProviderState(.connecting(message: "로그아웃 중…"), for: provider)
        if provider == selectedProvider {
            connecting = false
            pendingCopy = nil
            store.setEngineReady(false)
        }
        do {
            try await client.logout()
            guard isCurrentProviderOperation(provider, generation: generation) else { return }
            models = []
            providerModels[.codex] = []
            providerAccountLabels[.codex] = nil
            setProviderState(
                .authenticationRequired(message: "ChatGPT 구독 로그인이 필요합니다"),
                for: provider
            )
        } catch {
            guard isCurrentProviderOperation(provider, generation: generation) else { return }
            markProviderFailure(provider, error: error)
        }
    }

    func changeModel(_ model: String) {
        guard selectedModel != model else { return }
        invalidateProviderOperation(selectedProvider)
        selectedModel = model
        let selection = TranslationSelection(provider: selectedProvider, model: model)
        selection.save(to: .standard)
        requestStarted = ProcessInfo.processInfo.systemUptime
        elapsedMilliseconds = nil
        store.setTranslationContext(
            cacheContext: selection.cacheContext,
            provider: selectedProvider.rawValue,
            model: model,
            modelLabel: selection.label
        )
        refreshPendingCopy()
        if providerState(for: selectedProvider).isConnected {
            store.setEngineReady(isSelectedModelAvailable)
        } else {
            store.setEngineReady(false)
            if !providerState(for: selectedProvider).isConnecting {
                Task { await checkProviderConnection(selectedProvider) }
            }
        }
        updateCodexPrewarm()
        updateClaudePrewarm()
    }

    private func flushPendingCopyIfReady(provider: TranslationProvider, model: String) {
        guard provider == selectedProvider,
              selectedModel == model,
              store.engineReady,
              !store.requiresRetranslation,
              let pendingCopy else {
            if store.requiresRetranslation {
                self.pendingCopy = nil
            }
            return
        }
        guard pendingCopy.version == store.inputVersion,
              pendingCopy.text == store.sourceText else {
            self.pendingCopy = nil
            return
        }
        self.pendingCopy = nil
        store.invokeCopiedText(pendingCopy.text)
    }

    /// 선택 변경 뒤 현재 원문을 새 제공자·모델로 다시 요청한다.
    func retranslateSelection() {
        guard store.requiresRetranslation, !store.isComposing, !store.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard store.engineReady, !providerState(for: selectedProvider).isConnecting else { return }
        requestStarted = ProcessInfo.processInfo.systemUptime
        elapsedMilliseconds = nil
        requestModelLabel = nil
        // 앞 요청 때의 안내(삽입 실패 등)가 새 요청의 진행·오류를 가리지 않게 지운다.
        feedback = ""
        store.retranslateSelection()
    }

    func retranslateWholeDocument() {
        guard canRetranslateWholeDocument else { return }
        requestStarted = ProcessInfo.processInfo.systemUptime
        elapsedMilliseconds = nil
        requestModelLabel = nil
        feedback = ""
        store.retranslateWholeDocument()
    }

    /// '다시 시도'. 같은 종류의 요청을 다시 보내고, 앞 요청 때의 안내가 그 진행·오류를 가리지 않게 지운다.
    func retry() {
        requestStarted = ProcessInfo.processInfo.systemUptime
        elapsedMilliseconds = nil
        feedback = ""
        store.retry()
    }

    func changeDirection(_ direction: TranslationDirection) {
        requestStarted = ProcessInfo.processInfo.systemUptime
        elapsedMilliseconds = nil
        feedback = ""
        store.setDirection(direction)
        UserDefaults.standard.set(direction.rawValue, forKey: "translationDirection")
        refreshPendingCopy()
    }

    private func refreshPendingCopy() {
        if pendingCopy != nil && !store.engineReady {
            pendingCopy = (store.sourceText, store.inputVersion)
        }
    }

    func edit(_ text: String, composing: Bool) {
        guard store.sourceText != text || store.isComposing != composing else { return }
        pendingCopy = nil
        requestModelLabel = nil
        requestStarted = ProcessInfo.processInfo.systemUptime
        elapsedMilliseconds = nil
        feedback = ""
        hintCodex(typing: true)
        hintClaude(.typing)
        store.editSource(text, isComposing: composing)
    }

    /// 스트리밍 중간 결과를 표시하고, 요청마다 트리거부터 첫 중간 결과까지의 지연을 한 번 기록한다.
    private func receivePartialText(_ text: String, for request: TranslationRequest) {
        if firstPartialLoggedRequestID != request.id, store.isActiveRequest(request), let requestStarted {
            firstPartialLoggedRequestID = request.id
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - requestStarted) * 1_000)
            let provider = request.provider ?? "unknown"
            Self.latencyLog.notice("trigger→first partial \(elapsed, privacy: .public) ms provider=\(provider, privacy: .public) attempt=\(request.attempt, privacy: .public)")
        }
        store.receivePartialText(text, for: request)
    }

    func resultDidChange() {
        guard store.status == .success, let requestStarted else { return }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - requestStarted) * 1_000)
        elapsedMilliseconds = elapsed
        // 캐시 결과와 이미 기록한 결과를 다시 표시한 경우는 지연 측정에서 뺀다.
        guard let result = store.result, !store.lastResultWasCached, result.id != finalLoggedResultID else { return }
        finalLoggedResultID = result.id
        let provider = result.provider ?? "unknown"
        let retries = echoRetries.trigger == requestStarted ? echoRetries.count : 0
        Self.latencyLog.notice("trigger→final \(elapsed, privacy: .public) ms provider=\(provider, privacy: .public) retries=\(retries, privacy: .public)")
    }

    /// 출력 검사 결과를 지연 로그에 남긴다. 규칙 이름과 수만 쓰고 원문·번역문은 쓰지 않는다.
    /// 다시 요청할 때와 원문 반복이 남았을 때는 VoiceOver로도 알린다.
    private func reportOutputCheck(_ report: TranslationOutputReport) {
        let unit = report.incremental ? "tail" : "document"
        let provider = report.provider ?? "unknown"
        let coverage = String(format: "%.2f", report.coverage)
        if report.outcome == .retryingAfterEcho {
            let early = report.early ? 1 : 0
            if echoRetries.trigger != requestStarted { echoRetries = (requestStarted, 0) }
            echoRetries.count += 1
            let elapsed = requestStarted.map { Int((ProcessInfo.processInfo.systemUptime - $0) * 1_000) } ?? -1
            Self.latencyLog.notice("output echo retry \(elapsed, privacy: .public) ms early=\(early, privacy: .public) unit=\(unit, privacy: .public) provider=\(provider, privacy: .public) coverage=\(coverage, privacy: .public) candidates=\(report.candidates, privacy: .public)")
            announce("원문이 그대로 나와 다시 번역합니다", priority: .medium)
            return
        }
        let rules = report.rules.isEmpty ? "none" : report.rules.joined(separator: ",")
        let preamble = report.preambleRemoved ? 1 : 0
        let code = "\(report.codeKept):\(report.codeRestored):\(report.codeRefenced):\(report.codeInserted)"
        Self.latencyLog.notice("output check \(report.outcome.rawValue, privacy: .public) attempt=\(report.attempt, privacy: .public) unit=\(unit, privacy: .public) provider=\(provider, privacy: .public) rules=\(rules, privacy: .public) coverage=\(coverage, privacy: .public) candidates=\(report.candidates, privacy: .public) hanja=\(report.hanjaReplaced, privacy: .public) unreadable=\(report.hanjaUnreadable, privacy: .public) kept=\(report.hanjaKept, privacy: .public) incode=\(report.hanjaInCode, privacy: .public) preamble=\(preamble, privacy: .public) code=\(code, privacy: .public)")
        if report.outcome == .unresolvedEcho {
            announce("번역 결과에 원문이 그대로 남아 있을 수 있습니다", priority: .high)
        }
    }

    private func announce(_ message: String, priority: NSAccessibilityPriorityLevel) {
        guard let window else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: message, .priority: priority.rawValue
        ])
    }

    func copyResult() {
        guard captureMessage == nil, store.canCopy, let copy = store.resultCopy else { return }
        let copied = ResultClipboard.write(markdown: copy.markdown, plain: copy.plain, inline: store.result?.inlineOptions ?? .init(),
                                           format: copyFormat, to: .general)
        reportCopy(copied)
    }

    /// 복사 결과를 알린다. 성공은 '복사' 버튼이 약 2초 '복사됨'으로 바뀌고(앞 확인의 시계로 일찍 돌아오지 않는다),
    /// 실패는 하단 상태 칸에 남아 저절로 지우지 않는다. 이어서 성공하면 그 실패 문구만 지운다.
    func reportCopy(_ copied: Bool, confirmationDuration: Duration = .seconds(2)) {
        copyConfirmationGeneration &+= 1
        guard copied else {
            copyConfirmed = false
            feedback = Self.copyFailedMessage
            return
        }
        if feedback == Self.copyFailedMessage { feedback = "" }
        copyConfirmed = true
        let generation = copyConfirmationGeneration
        Task { [weak self] in
            try? await Task.sleep(for: confirmationDuration)
            guard let self, copyConfirmationGeneration == generation else { return }
            copyConfirmed = false
        }
    }

    /// 확인 문구(삽입됨)는 잠깐 보이고 스스로 지운다. 그 사이 다른 안내가 오면 그 안내를 남기고,
    /// 다시 확인하면 앞 확인의 시계로 지우지 않는다.
    func showBriefly(_ message: String, for duration: Duration = .seconds(2)) {
        feedback = message
        briefFeedbackGeneration &+= 1
        let generation = briefFeedbackGeneration
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, briefFeedbackGeneration == generation, feedback == message else { return }
            feedback = ""
        }
    }

    func insertResult() async {
        guard canInsert, let session = invocation, let text = store.resultInsertionText else { return }
        let resultID = store.result?.id
        let generation = invocationGeneration
        inserting = true
        defer { inserting = false }
        guard case .success = await session.restoreFocus() else {
            feedback = "원래 입력 위치를 확인할 수 없습니다. 복사를 사용해 주세요"
            return
        }
        guard generation == invocationGeneration, store.canInsert, store.result?.id == resultID, invocation?.id == session.id else {
            feedback = "결과가 변경되어 삽입을 중단했습니다"
            return
        }
        let insertionResult: Result<VerifiedInsertionReceipt, InvocationSessionError>
        if session.application.bundleIdentifier == InvocationSession.pasteboardInsertionBundleIdentifier {
            insertionResult = await session.insertUsingPasteboard(text)
        } else {
            insertionResult = session.insert(text)
        }
        guard generation == invocationGeneration, invocation?.id == session.id else { return }
        switch insertionResult {
        case .success:
            window?.orderOut(nil)
            showBriefly("삽입됨")
        case .failure:
            feedback = "삽입을 확인하지 못했습니다. 원래 내용을 확인해 주세요"
        }
    }

    /// 번역 캐시 키에는 넣지 않는다. 같은 원문은 캐시 결과가 나오므로 새 원문이나 '다시 번역'으로 확인한다.
    func setCodexFastServiceTier(_ enabled: Bool) {
        codexFastServiceTier = enabled
        UserDefaults.standard.set(enabled, forKey: "codexFastServiceTier")
        updateCodexPrewarm()
    }

    func setCopyFormat(_ format: ResultCopyFormat) {
        copyFormat = format
        UserDefaults.standard.set(format.rawValue, forKey: ResultCopyFormat.defaultsKey)
    }

    /// 표시 설정을 바꾸고 저장한다. 같은 값이면 아무것도 하지 않아 결과 창을 다시 칠하지 않는다.
    /// 미리보기는 바로 바뀌고, 열린 결과 창은 100ms 안의 변경을 묶어 칠한다(`ResultScrollView.displayCoalescing`).
    /// 저장은 연속 변경이 멈춘 뒤 마지막 값 하나만 하고, 설정 창을 닫거나 앱을 끝낼 때는 바로 한다.
    func updateResultDisplay(_ change: (inout ResultDisplaySettings) -> Void) {
        var display = resultDisplay
        change(&display)
        guard display != resultDisplay else { return }
        resultDisplay = display
        guard displaySaves.submit(display, at: .now) else { return }
        displaySaveTask = Task { @MainActor [weak self] in
            while let deadline = self?.displaySaves.deadline {
                try? await Task.sleep(until: deadline, clock: .continuous)
                // A flush cancelled this wait and saved; a change after it waits in a task of its own. Not cancelled,
                // this is still `displaySaveTask`.
                guard !Task.isCancelled, let self else { return }
                if let display = displaySaves.fire(at: .now) {
                    display.save(to: displayDefaults)
                    displaySaveTask = nil
                    return
                }
            }
        }
    }

    private func flushResultDisplaySave() {
        displaySaveTask?.cancel()
        displaySaveTask = nil
        displaySaves.flush()?.save(to: displayDefaults)
    }

    func openCodeStylePicker() {
        guard !showsCodeStylePicker else { return }
        withAnimation(Self.settingsAnimation) { showsCodeStylePicker = true }
        resizeSettingsWindow(to: CodeStylePickerModel.pickerSize, animated: true)
    }

    func closeCodeStylePicker() {
        guard showsCodeStylePicker else { return }
        withAnimation(Self.settingsAnimation) { showsCodeStylePicker = false }
        resizeSettingsWindow(to: CodeStylePickerModel.tabsSize, animated: true)
    }

    enum SettingsEscape: Equatable {
        case picker, permissions, window
    }

    /// Esc in the settings window: the picker goes back to the 표시 tab before anything closes, then the permission
    /// popover closes (the view owns it, so `.permissions` is left to the caller), then the window.
    @discardableResult
    func escapeSettings(permissionsShown: Bool) -> SettingsEscape {
        if showsCodeStylePicker {
            closeCodeStylePicker()
            return .picker
        }
        if permissionsShown { return .permissions }
        closeSettingsWindow()
        return .window
    }

    private static var settingsAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    /// Keeps the top-left corner and the window on its screen (`CodeStylePickerModel.settingsFrame`).
    private func resizeSettingsWindow(to contentSize: CGSize, animated: Bool) {
        guard let window = settingsWindow else { return }
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        // Going back mid-animation starts from where the window was going, so a remembered shift still applies.
        let current = settingsFrameAnimating ? settingsFrameShift?.frame ?? window.frame : window.frame
        let remembered = settingsFrameShift.flatMap { last in
            abs(last.frame.minX - current.minX) < 1 && abs(last.frame.maxY - current.maxY) < 1 ? last.shift : nil
        } ?? .zero
        let next = CodeStylePickerModel.settingsFrame(current: current, targetSize: size, visibleFrame: settingsScreenFrame(window),
                                                      rememberedShift: remembered)
        settingsFrameShift = next
        settingsResizes &+= 1
        let resize = settingsResizes
        let animates = animated && Self.settingsAnimation != nil && window.isVisible
        settingsFrameAnimating = animates
        // A plain setFrame would lose to a running animation, which ends at its own frame: closing the window while
        // it widens left the tabs in a 620-wide window. A zero-length animation replaces the running one.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animates ? 0.2 : 0
            if animates { context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) }
            window.animator().setFrame(next.frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.settingsResizes == resize { self?.settingsFrameAnimating = false }
            }
        }
    }

    func setShortcutEnabled(_ enabled: Bool) {
        shortcutEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "shortcutEnabled")
        feedback = ""
        restartShortcut()
    }

    func refreshPermissionStatus() {
        // 이 조회는 현재 프로세스의 접근 가능 여부이며 시스템 설정 스위치 값을 뜻하지 않는다.
        accessibilityReady = AXIsProcessTrusted()
        inputMonitoringAllowed = CGPreflightListenEventAccess()
        let wasReady = shortcutReady
        shortcutReady = monitor.verifyReadiness()
        if wasReady && !shortcutReady {
            shortcutMessage = shortcutEnabled ? "단축키 감시 연결 확인 필요" : TranslationFooterState.shortcutDisabled
            updateShortcutMenu()
        }
    }

    func restartShortcut() {
        refreshPermissionStatus()
        loginItemController.refresh()
        monitor.stop()
        guard shortcutEnabled else {
            shortcutReady = false
            shortcutMessage = TranslationFooterState.shortcutDisabled
            clearShortcutFailureFeedback()
            updateShortcutMenu()
            return
        }
        shortcutReady = monitor.start()
        if shortcutReady {
            shortcutMessage = TranslationFooterState.shortcutWatching
            clearShortcutFailureFeedback()
        }
        updateShortcutMenu()
    }

    private func clearShortcutFailureFeedback() {
        if let shortcutFailureFeedback, feedback == shortcutFailureFeedback { feedback = "" }
        shortcutFailureFeedback = nil
    }

    private func updateShortcutMenu() {
        shortcutMenuItem?.title = shortcutMessage
        statusItem?.button?.toolTip = "deepK · \(shortcutMessage)"
        statusItem?.button?.image = menuBarImage()
    }

    private func menuBarImage() -> NSImage? {
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        return image
    }

    func requestShortcutPermission() {
        guard !CGPreflightListenEventAccess() else {
            restartShortcut()
            return
        }
        prepareForSystemPermissionUI()
        _ = CGRequestListenEventAccess()
        restartShortcut()
    }

    func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else {
            accessibilityReady = true
            return
        }
        prepareForSystemPermissionUI()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityReady = AXIsProcessTrustedWithOptions(options)
    }

    func openInputMonitoringSettings() {
        prepareForSystemPermissionUI()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func openAccessibilitySettings() {
        prepareForSystemPermissionUI()
        NSWorkspace.shared.open(InvocationSession.accessibilitySettingsURL)
    }

    func openLoginItemSettings() {
        prepareForSystemPermissionUI()
        loginItemController.openSettings()
    }

    private func prepareForSystemPermissionUI() {
        // 상시 표시 패널과 설정 창이 macOS의 권한 안내를 가리지 않게 한다.
        // 번역 내용과 원래 앱 정보는 유지해 다시 열었을 때 이어서 사용한다.
        closeSettingsWindow()
        window?.orderOut(nil)
    }

    func hideAndRestore() {
        dismissTranslationWindow(restoreOriginalFocus: true)
    }

    private func dismissTranslationWindow(restoreOriginalFocus: Bool) {
        closeSettingsWindow()
        let target = originalApplication
        captureMessage = nil
        invocationGeneration &+= 1
        invocation?.invalidate()
        invocation = nil
        originalApplication = nil
        pendingCopy = nil
        window?.orderOut(nil)
        guard restoreOriginalFocus else { return }
        NSApp.hide(nil)
        if let target, !target.isTerminated {
            target.activate(options: [.activateAllWindows])
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === settingsWindow {
            closeSettingsWindow()
            return false
        }
        hideAndRestore()
        return false
    }

    func showWindow(activate: Bool = true, nearPointer: Bool = false, preview: Bool = false) {
        let wasVisible = window?.isVisible == true
        if window == nil {
            let panel = TranslationPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 264),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
            )
            panel.title = "deepK"
            panel.minSize = WindowPresentation.smallSize
            panel.appearance = NSAppearance(named: .aqua)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.level = .normal
            panel.hidesOnDeactivate = false
            // Link tooltips show while the reader's app stays in front.
            panel.allowsToolTipsWhenApplicationIsInactive = true
            panel.contentView = NSHostingView(rootView: TranslationView().preferredColorScheme(.light))
            panel.center()
            attach(panel)
        }
        if !wasVisible && !preview { windowPresentation.applyOnOpen() }
        if !wasVisible {
            hintCodex()
            hintClaude(.windowShown)
        }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        if nearPointer, let window {
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            // An open window on the pointer's screen stays put so the text being read does not move.
            if !wasVisible || window.screen != screen, let bounds = screen?.visibleFrame {
                let x = min(max(pointer.x + 16, bounds.minX), max(bounds.minX, bounds.maxX - window.frame.width))
                let y = min(max(pointer.y - window.frame.height - 12, bounds.minY), max(bounds.minY, bounds.maxY - window.frame.height))
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        if activate {
            NSApp.unhide(nil)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 원래 앱이 복사를 마치기 전에 포커스를 빼앗지 않는다.
            NSApp.unhideWithoutActivation()
            window?.orderFrontRegardless()
        }
    }

    func previewTranslationWindow() {
        closeSettingsWindow()
        showWindow(preview: true)
    }

    @objc func toggleWindowSize() {
        if window?.isVisible != true { showWindow(preview: true) }
        windowPresentation.toggleSize()
    }

    @objc private func showSmallWindow() {
        showWindow(preview: true)
        windowPresentation.setCurrentSize(.small)
    }

    @objc private func showLargeWindow() {
        showWindow(preview: true)
        windowPresentation.setCurrentSize(.large)
    }

    func windowDidResize(_ notification: Notification) {
        guard let changed = notification.object as? NSWindow, changed === window else { return }
        windowPresentation.didResize(changed)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard window === self.window else { return true }
        windowPresentation.toggleSize()
        return false
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = menuBarImage()
        item.button?.setAccessibilityLabel("deepK")
        let menu = NSMenu()
        let status = NSMenuItem(title: shortcutMessage, action: #selector(openSettings), keyEquivalent: "")
        status.target = self
        menu.addItem(status)
        let sizeItem = NSMenuItem(title: "창 크기", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "창 크기")
        for (title, action) in [("작게 · 420×296", #selector(showSmallWindow)), ("크게 · 880×600", #selector(showLargeWindow))] {
            let option = NSMenuItem(title: title, action: action, keyEquivalent: "")
            option.target = self
            sizeMenu.addItem(option)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        shortcutMenuItem = status
        for (title, action) in [("deepK 열기", #selector(openFromMenu)), ("설정", #selector(openSettings)), ("종료", #selector(quit))] {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menu.addItem(menuItem)
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func openFromMenu() {
        invocationGeneration &+= 1
        originalApplication = nil
        invocation?.invalidate()
        invocation = nil
        showWindow()
    }

    @objc func openSettings() {
        presentSettingsWindow()
    }

    func presentSettingsWindow() {
        if settingsWindow == nil {
            // 번역 탭은 Codex에서 다섯 행(제공자 둘·모델·Fast·복사 형식)이라 그 높이에 맞춘다.
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 376),
                                    styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            settings.title = "deepK 설정"
            settings.titleVisibility = .hidden
            settings.titlebarAppearsTransparent = true
            settings.isMovableByWindowBackground = true
            settings.isReleasedWhenClosed = false
            settings.delegate = self
            settings.appearance = NSAppearance(named: .aqua)
            settings.level = .normal
            settings.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            settings.contentView = Self.settingsHost(FinalSettingsView().preferredColorScheme(.light))
            settings.center()
            settingsWindow = settings
        } else if showsCodeStylePicker {
            showsCodeStylePicker = false
            resizeSettingsWindow(to: CodeStylePickerModel.tabsSize, animated: false)
        }
        showSettings = true
        refreshPermissionStatus()
        loginItemController.refresh()
        Task { await refreshProviderConnections() }
        NSApp.unhide(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The settings window's content. The window sets the size, 340 for the tabs and 620 for the code style picker,
    /// so the hosting view neither resizes it nor holds it to the content's size.
    static func settingsHost<Content: View>(_ root: Content) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        return host
    }

    func closeSettingsWindow() {
        showSettings = false
        settingsWindow?.orderOut(nil)
        // The window opens on its tabs next time.
        if showsCodeStylePicker {
            showsCodeStylePicker = false
            resizeSettingsWindow(to: CodeStylePickerModel.tabsSize, animated: false)
        }
        flushResultDisplaySave()
    }

    func shutdown() async {
        for provider in TranslationProvider.allCases { _ = beginProviderOperation(provider) }
        connecting = false
        pendingCopy = nil
        closeSettingsWindow()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
        monitor.stop()
        store.setEngineReady(false)
        await client.disconnect()
        await claudeClient.disconnect()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
