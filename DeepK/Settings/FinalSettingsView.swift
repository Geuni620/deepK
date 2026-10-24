import AppKit
import SwiftUI

@MainActor
struct FinalSettingsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case general
        case translation
        case display

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "일반"
            case .translation: "번역"
            case .display: "표시"
            }
        }
    }

    @State private var app = AppModel.shared
    @State private var tab: Tab = .general
    @State private var showPermissions = false
    @State private var confirmCodexLogout = false
    @State private var installInstructionsProvider: TranslationProvider?

    var body: some View {
        VStack(spacing: 0) {
            // The tabs slide out to the left as the window widens for the style picker, which slides in from the right.
            ZStack(alignment: .topLeading) {
                if app.showsCodeStylePicker {
                    CodeStylePickerView(app: app)
                        .transition(.move(edge: .trailing))
                } else {
                    tabs
                        .frame(width: CodeStylePickerModel.tabsSize.width)
                        .transition(.move(edge: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()

            Divider()
            versionFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(Color(nsColor: .labelColor))
        .font(.system(size: 13))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            refreshPermissionStatus()
            app.loginItemController.refresh()
            refreshProviderStates()
        }
        .onChange(of: showPermissions) { _, isPresented in
            if isPresented { refreshPermissionStatus() }
        }
        // The only Esc handler (`AppModel.escapeSettings`): the picker goes back to the 표시 tab before anything closes.
        .onExitCommand {
            if app.escapeSettings(permissionsShown: showPermissions) == .permissions {
                showPermissions = false
            }
        }
        .confirmationDialog(
            "Codex에서 로그아웃하시겠어요?",
            isPresented: $confirmCodexLogout,
            titleVisibility: .visible
        ) {
            Button("Codex 로그아웃", role: .destructive) {
                runProviderAction { await app.logoutProvider(.codex) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("공유 Codex 로그인도 해제됩니다. 다른 Codex 앱에서 다시 로그인해야 할 수 있습니다. deepK만 끊으려면 연결 해제를 사용하세요.")
        }
        .alert(item: $installInstructionsProvider) { provider in
            if provider == .codex {
                // 설치나 경로 지정 뒤 바로 다시 탐색할 수 있게 한다.
                Alert(
                    title: Text("\(provider.title) 설치 방법"),
                    message: Text(installInstructions(for: provider)),
                    primaryButton: .default(Text("연결 확인")) {
                        runProviderAction { await app.connectProvider(provider) }
                    },
                    secondaryButton: .cancel(Text("닫기"))
                )
            } else {
                Alert(
                    title: Text("\(provider.title) 설치 방법"),
                    message: Text(installInstructions(for: provider)),
                    dismissButton: .default(Text("확인"))
                )
            }
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch tab {
                    case .general:
                        generalSettings
                    case .translation:
                        translationSettings
                    case .display:
                        DisplaySettingsTab(app: app)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabBar: some View {
        HStack {
            Spacer(minLength: 0)
            Picker("설정 영역", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(.gray)
            .controlSize(.small)
            .frame(width: 186)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
    }

    private var generalSettings: some View {
        VStack(spacing: 0) {
            settingToggleRow(
                title: "⌘C 두 번 자동 번역",
                subtitle: app.shortcutEnabled ? "선택한 텍스트를 두 번 복사하면 번역합니다" : "자동 번역을 사용하지 않습니다",
                isOn: Binding(
                    get: { app.shortcutEnabled },
                    set: { app.setShortcutEnabled($0) }
                )
            )

            Divider().padding(.horizontal, 20)

            permissionRow
                .popover(isPresented: $showPermissions, arrowEdge: .trailing) {
                    permissionPopover
                }

            Divider().padding(.horizontal, 20)

            windowSizeRow

            Divider().padding(.horizontal, 20)

            loginItemRow
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var permissionRow: some View {
        Button {
            refreshPermissionStatus()
            showPermissions = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(permissionSummary.tint)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text("권한")
                        .foregroundStyle(Color(nsColor: .labelColor))
                }

                Spacer(minLength: 8)
                Text(permissionSummary.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .accessibilityLabel("권한 \(permissionSummary.title)")
    }

    private var permissionPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("권한")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 8)

            permissionDetailRow(
                title: "입력 모니터링",
                subtitle: "⌘C 두 번 감지",
                state: inputMonitoringState,
                settingsAction: inputMonitoringSettingsAction
            )
            Divider()
            permissionDetailRow(
                title: "손쉬운 사용",
                subtitle: "원래 위치에 번역 삽입",
                state: accessibilityState,
                settingsAction: accessibilitySettingsAction
            )

            if !app.shortcutEnabled {
                Text("자동 번역이 꺼져 있으면 입력 모니터링을 사용하지 않습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.top, 10)
            } else if permissionSummary != .ready {
                Text(app.permissionConnectionHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(width: 282, alignment: .leading)
        .onAppear { refreshPermissionStatus() }
    }

    private func permissionDetailRow(
        title: String,
        subtitle: String,
        state: PermissionState,
        settingsAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(state.tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                Text(state.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer(minLength: 4)
                if let settingsAction {
                    Button("설정 열기…", action: settingsAction)
                        .font(.system(size: 11))
                        .buttonStyle(.link)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var windowSizeRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("열릴 때 창 크기")
                HStack(spacing: 4) {
                    Text("지금 창: \(app.windowPresentation.currentSizeLabel) ·")
                        .foregroundStyle(.secondary)
                    Button("창 보기") { app.previewTranslationWindow() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }.font(.system(size: 11)).lineLimit(1)
            }

            Spacer(minLength: 8)
            Menu {
                ForEach(WindowPresentation.OpeningPreference.allCases) { preference in
                    Button {
                        app.windowPresentation.setOpeningPreference(preference)
                    } label: {
                        if app.windowPresentation.openingPreference == preference {
                            Label(preference.displayName, systemImage: "checkmark")
                        } else {
                            Text(preference.displayName)
                        }
                    }
                }
                Divider()
                Text("다음에 창을 열 때부터 적용됩니다.")
                Divider()
                Text("지금 창: \(app.windowPresentation.currentSizeLabel)")
                Button("창 보기") { app.previewTranslationWindow() }
            } label: {
                HStack(spacing: 4) {
                    Text(app.windowPresentation.openingPreference.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("열릴 때 창 크기 \(app.windowPresentation.openingPreference.displayName)")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }

    private var loginItemRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("로그인 시 자동 실행")
                Spacer(minLength: 8)
                Toggle(
                    "로그인 시 자동 실행",
                    isOn: Binding(
                        get: { app.loginItemController.isRegistered },
                        set: { app.loginItemController.setEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .controlSize(.mini)
                .disabled(app.loginItemController.isBusy)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(app.loginItemController.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(loginItemStatusTint)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if app.loginItemController.requiresApproval || app.loginItemController.error != nil {
                    Button("설정 열기…") { app.openLoginItemSettings() }
                        .font(.system(size: 11))
                        .buttonStyle(.link)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }

    private var translationSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(TranslationProvider.allCases) { provider in
                providerRow(provider)
                Divider().padding(.horizontal, 20)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("모델")
                    Text("\(app.selectedProvider.title) 모델").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Picker("번역 모델", selection: Binding(get: { app.selectedModel }, set: { app.changeModel($0) })) {
                    let options = modelOptions(for: app.selectedProvider)
                    ForEach(options) { Text($0.displayName).tag($0.model) }
                    if !options.contains(where: { $0.model == app.selectedModel }) {
                        Text(app.providerState(for: app.selectedProvider).isConnected ? "모델 선택 필요" : "연결 후 선택").tag(app.selectedModel)
                    }
                }
                .labelsHidden().controlSize(.small).frame(maxWidth: 166)
                .disabled(!app.providerState(for: app.selectedProvider).isConnected)
                .help("새 선택은 ‘다시 번역’ 또는 다음 원문부터 사용합니다.")
            }.padding(.horizontal, 20).frame(minHeight: 54)
            if app.selectedProvider == .codex {
                Divider().padding(.horizontal, 20)
                // 정확한 사용량 배수는 모델 카탈로그에 없으므로 숫자를 쓰지 않는다.
                settingToggleRow(
                    title: "Codex 빠른 응답(Fast)",
                    subtitle: "더 빠른 생성 · 구독 사용량 증가",
                    isOn: Binding(
                        get: { app.codexFastServiceTier },
                        set: { app.setCodexFastServiceTier($0) }
                    )
                )
                .help("새 설정은 ‘다시 번역’ 또는 다음 원문부터 사용합니다.")
            }
            Divider().padding(.horizontal, 20)
            copyFormatRow
        }.padding(.top, 8).padding(.bottom, 10)
    }

    private var copyFormatRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("복사 형식")
                Text(app.copyFormat.detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(ResultCopyFormat.allCases) { format in
                    Button {
                        app.setCopyFormat(format)
                    } label: {
                        if app.copyFormat == format {
                            Label(format.title, systemImage: "checkmark")
                        } else {
                            Text(format.title)
                        }
                    }
                }
            } label: {
                Text(app.copyFormat.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("복사 형식 \(app.copyFormat.title)")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }

    private func providerRow(_ provider: TranslationProvider) -> some View {
        let state = providerState(for: provider)

        return HStack(alignment: .center, spacing: 10) {
            Button {
                app.changeProvider(provider)
            } label: {
                Image(systemName: app.selectedProvider == provider ? "circle.inset.filled" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(app.selectedProvider == provider ? Color.primary : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기본 제공자 \(provider.title)")
            .disabled(!state.isConnected)

            Button {
                app.changeProvider(provider)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(providerStatusDetail(state))
                        .font(.system(size: 11))
                        .foregroundStyle(providerStatusTint(state))
                        .lineLimit(1)
                        .help(state.message)
                    if provider == .codex, let info = app.codexExecutableInfo {
                        Text(codexExecutableText(info))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(info.path)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!state.isConnected)

            providerAction(provider, state: state)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }

    @ViewBuilder
    private func providerAction(_ provider: TranslationProvider, state: ProviderState) -> some View {
        if state.isConnecting || (app.connecting && app.selectedProvider == provider) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20)
        } else if state.isConnected {
            Menu {
                Button("deepK에서 연결 해제") {
                    runProviderAction { await app.disconnectProvider(provider) }
                }
                if provider == .codex {
                    Divider()
                    Button("Codex 로그아웃…", role: .destructive) {
                        confirmCodexLogout = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("\(provider.title) 연결 관리")
        } else {
            Button(providerPrimaryActionTitle(state)) {
                if case .cliMissing = state {
                    installInstructionsProvider = provider
                } else {
                    runProviderAction {
                        switch state {
                        case .authenticationRequired:
                            if state.message.contains("확인") {
                                await app.connectProvider(provider)
                            } else {
                                await app.loginProvider(provider)
                            }
                        case .notChecked, .failure:
                            await app.connectProvider(provider)
                        case .connecting, .connected, .cliMissing:
                            break
                        }
                    }
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.link)
        }
    }

    private var versionFooter: some View {
        HStack {
            Text(versionText)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
    }

    private func settingToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        SettingsToggleRow(title: title, subtitle: subtitle, isOn: isOn)
    }

    private enum PermissionState: Equatable {
        case ready
        case needsPermission
        case needsConnection
        case disabled
        case unknown

        var title: String {
            switch self {
            case .ready: "준비됨"
            case .needsPermission: "확인 필요"
            case .needsConnection: "연결 확인 필요"
            case .disabled: "감시 꺼짐"
            case .unknown: "확인 필요"
            }
        }

        var tint: Color {
            switch self {
            case .ready: .green
            case .needsPermission, .needsConnection, .unknown: .orange
            case .disabled: Color(nsColor: .tertiaryLabelColor)
            }
        }
    }

    private enum PermissionSummary: Equatable {
        case ready
        case oneNeeded
        case twoNeeded
        case unknown

        var title: String {
            switch self {
            case .ready: "준비됨"
            case .oneNeeded: "1개 권한 확인 필요"
            case .twoNeeded: "2개 권한 확인 필요"
            case .unknown: "확인 필요"
            }
        }

        var tint: Color {
            switch self {
            case .ready: .green
            case .oneNeeded, .twoNeeded, .unknown: .orange
            }
        }
    }

    private var inputMonitoringState: PermissionState {
        guard app.shortcutEnabled else { return .disabled }
        if app.shortcutReady { return .ready }
        if !app.inputMonitoringAllowed { return .needsPermission }
        return .needsConnection
    }

    private var accessibilityState: PermissionState {
        app.accessibilityReady ? .ready : .needsPermission
    }

    private var permissionSummary: PermissionSummary {
        if !app.shortcutEnabled {
            return accessibilityState == .needsPermission ? .oneNeeded : .ready
        }
        let states = [inputMonitoringState, accessibilityState]
        if states.contains(.unknown) || states.contains(.needsConnection) {
            return .unknown
        }
        let missing = states.filter { $0 == .needsPermission }.count
        switch missing {
        case 0: return .ready
        case 1: return .oneNeeded
        default: return .twoNeeded
        }
    }

    private var inputMonitoringSettingsAction: (() -> Void)? {
        switch inputMonitoringState {
        case .unknown, .needsConnection, .needsPermission:
            return {
                showPermissions = false
                app.openInputMonitoringSettings()
            }
        case .ready, .disabled:
            return nil
        }
    }

    private var accessibilitySettingsAction: (() -> Void)? {
        accessibilityState == .needsPermission ? {
            showPermissions = false
            app.openAccessibilitySettings()
        } : nil
    }

    private var loginItemStatusTint: Color {
        if app.loginItemController.error != nil { return .orange }
        if app.loginItemController.isEnabled { return .green }
        if app.loginItemController.requiresApproval { return .orange }
        return Color(nsColor: .secondaryLabelColor)
    }

    private func refreshPermissionStatus() {
        app.refreshPermissionStatus()
    }

    private func refreshProviderStates() {
        Task { @MainActor in
            await app.refreshProviderConnections()
        }
    }

    /// 실제 경로(홈은 `~`)와 버전을 보여 준다. 검증한 버전보다 새로우면 함께 알린다.
    private func codexExecutableText(_ info: CodexTranslationClient.ExecutableInfo) -> String {
        var parts = ["실행 파일: \(info.displayPath)"]
        if let version = info.version { parts.append(version) }
        if info.isNewerThanTested { parts.append("검증 범위보다 새 버전") }
        return parts.joined(separator: " · ")
    }

    private func installInstructions(for provider: TranslationProvider) -> String {
        switch provider {
        case .codex:
            """
            Codex CLI \(CodexTranslationClient.minimumCodexVersion) 이상이 필요합니다. npm install -g @openai/codex 또는 brew install --cask codex로 설치하거나 ChatGPT 앱을 설치한 뒤 연결 확인을 눌러 주세요.

            찾는 순서: 지정 경로 → CODEX_EXECUTABLE·CODEX_CLI_PATH → Homebrew·npm 전역·~/.local/bin·Volta·Bun·nvm(모든 Node 버전) → PATH → ChatGPT 앱 내장 CLI. 같은 단계에서는 가장 높은 버전을 씁니다.

            경로 지정: defaults write com.deepk.app codexExecutablePath -string <경로>
            지정 해제: defaults delete com.deepk.app codexExecutablePath
            """
        case .claude:
            "Claude Code를 설치하고 scripts/setup-claude.sh로 앱 전용 CLI를 준비한 뒤 연결 확인을 눌러 주세요."
        }
    }

    private func providerState(for provider: TranslationProvider) -> ProviderState {
        app.providerState(for: provider)
    }

    private func providerStatusText(_ state: ProviderState) -> String {
        switch state {
        case .connected: "연결됨"
        case .connecting: "연결 중…"
        case .authenticationRequired: "로그인 필요"
        case .cliMissing: "CLI 설치 필요"
        case .notChecked: "확인 전"
        case .failure: "연결 실패"
        }
    }

    private func providerStatusDetail(_ state: ProviderState) -> String {
        switch state {
        case .authenticationRequired, .cliMissing, .failure:
            return state.message
        case .connected, .connecting, .notChecked:
            return providerStatusText(state)
        }
    }

    private func providerStatusTint(_ state: ProviderState) -> Color {
        switch state {
        case .connected: Color(nsColor: .secondaryLabelColor)
        case .connecting, .authenticationRequired, .cliMissing, .notChecked: .orange
        case .failure: .red
        }
    }

    private func providerPrimaryActionTitle(_ state: ProviderState) -> String {
        switch state {
        case .authenticationRequired:
            state.message.contains("확인") ? "연결 확인" : "로그인…"
        case .cliMissing: "설치 방법"
        case .notChecked, .failure: "연결 확인"
        case .connecting: "연결 중…"
        case .connected: "관리"
        }
    }

    private func runProviderAction(_ action: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            await action()
        }
    }

    private func modelOptions(for provider: TranslationProvider) -> [TranslationModelOption] {
        let options = app.models(for: provider)
        if !options.isEmpty {
            return options
        }

        if let fixed = provider.fixedModels {
            return fixed
        }
        return app.models.map {
            TranslationModelOption(id: $0.id, model: $0.model, displayName: $0.displayName)
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version?.isEmpty == false, build?.isEmpty == false) {
        case (true, true): return "deepK \(version!) (\(build!))"
        case (true, false): return "deepK \(version!)"
        case (false, true): return "deepK 빌드 \(build!)"
        default: return "deepK 개발 버전"
        }
    }
}

extension DisplaySettingsTab {
    /// The 표시 tab as the settings window shows it, wired to the app.
    init(app: AppModel) {
        self.init(display: app.resultDisplay, update: app.updateResultDisplay, openPicker: app.openCodeStylePicker)
    }
}

extension CodeStylePickerView {
    /// The picker as the settings window shows it, wired to the app.
    init(app: AppModel) {
        self.init(display: app.resultDisplay, update: app.updateResultDisplay, back: app.closeCodeStylePicker)
    }
}
