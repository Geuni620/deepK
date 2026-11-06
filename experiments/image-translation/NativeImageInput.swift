#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import NaturalLanguage
import Observation
import SwiftUI

struct NativeImageTranslator {
    let label: String
    let run: @Sendable (NativeImageRegionBatch, String, String, @escaping @Sendable (String) -> Void) async throws -> String
}

@MainActor @Observable final class NativeImageInput {
    let scanner = POCScreenScanner()
    var isImporting = false
    var selectionText = ""
    var image: POCImage?
    var renderedImage: CGImage?
    var regions: [ImageTextRegion] = []
    var translations: [Int: String] = [:]
    var recognizedText = ""
    var status = ""
    var warning: String?
    var busy = false
    var complete = false
    var showsOCR = false
    var showsTextResult = false
    var zoom: Double = 1
    var prefersReadableSize = true
    var bodyFontPixels: CGFloat = 0
    var stage: ImageProcessingStage = .idle
    var draftText = ""
    var activeRegionID: Int?
    var renderedRegionIDs = Set<Int>()
    var ocrSeconds: Double?
    var translationSeconds: Double?
    var firstResultSeconds: Double?
    var firstTextSeconds: Double?
    var providerLabel = ""
    var failureKind: String?
    @ObservationIgnored var makeTranslator: (() -> NativeImageTranslator)?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderer: NaturalImageRenderer?
    @ObservationIgnored private var rendererPreparation: Task<NaturalImageRenderer, Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var streamID: UUID?
    @ObservationIgnored private var renderRequest = 0
    @ObservationIgnored private var lastRenderedTranslations: [Int: String] = [:]
    @ObservationIgnored private var started = ContinuousClock.now

    var isActive: Bool { isImporting || image != nil }
    var identity: UUID { generation }
    var pendingBoxes: [CGRect] { busy ? regions.filter { !renderedRegionIDs.contains($0.id) }.map(\.box) : [] }
    var activeBox: CGRect? { busy ? regions.first { $0.id == activeRegionID }?.box : nil }
    var copyText: String { ([translations[0]].compactMap { $0 } + regions.compactMap { translations[$0.id] }).joined(separator: "\n\n") }
    var timing: String {
        var fields: [String] = []
        if let ocrSeconds { fields.append(String(format: "글자 읽기 %.1f초", ocrSeconds)) }
        if let translationSeconds { fields.append(String(format: "번역 %.1f초", translationSeconds)) }
        if let firstResultSeconds { fields.append(String(format: "첫 이미지 표시 %.1f초", firstResultSeconds)) }
        return fields.joined(separator: " · ")
    }

    func load(_ image: POCImage, direction: TranslationDirection, selectionText: String = "") {
        cancel()
        let token = generation
        self.selectionText = selectionText; isImporting = false
        self.image = image; renderedImage = image.pixels; regions = []; translations = [:]; recognizedText = ""
        warning = nil; showsOCR = false; showsTextResult = false; zoom = 1; complete = false; busy = true
        failureKind = nil
        stage = .reading; draftText = ""; activeRegionID = nil; renderedRegionIDs = []; bodyFontPixels = 0
        lastRenderedTranslations = [:]; renderRequest = 0
        ocrSeconds = nil; translationSeconds = nil; firstResultSeconds = nil; firstTextSeconds = nil; started = .now
        status = "이미지에서 글자 읽는 중…"
        let translator = makeTranslator?(); providerLabel = translator?.label ?? ""
        operation = Task { [weak self] in
            do {
                let found = try await Task.detached(priority: .userInitiated) { try POCTextRecognition.recognize(image) }.value
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.ocrSeconds = Self.seconds(self.started.duration(to: .now))
                self.regions = found; self.recognizedText = found.map(\.text).joined(separator: "\n\n")
                let heights = found.flatMap(\.lineBoxes).map { $0.height * CGFloat(image.pixels.height) }.sorted()
                self.bodyFontPixels = (heights.isEmpty ? 0 : heights[heights.count / 4]) * 0.85
                self.rendererPreparation = Task.detached(priority: .userInitiated) { try NaturalImageRenderer(image: image.pixels, regions: found) }
                guard let translator else { throw ImagePOCError.message("번역 연결을 준비하지 못했습니다. 설정에서 제공자를 확인해 주세요.") }
                let language = Self.languages(direction, text: self.recognizedText)
                // Image blocks come first: a long copied article must not delay the first image result.
                let requestRegions = found + (selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [ImageTextRegion(id: 0, text: selectionText, box: .zero)])
                guard !requestRegions.isEmpty else { throw ImagePOCError.message("이미지에서 글자를 찾지 못했습니다. 원본은 그대로 유지했습니다.") }
                let batches = try NativeImageRegionBatch.make(requestRegions)
                let requestStart = ContinuousClock.now
                for (index, batch) in batches.enumerated() {
                    var missing = batch.regions
                    for attempt in 0..<2 where !missing.isEmpty {
                        try Task.checkCancellation()
                        guard self.generation == token else { return }
                        self.status = attempt == 0 ? "\(found.count)개 영역 읽음 · 번역 중 \(index + 1)/\(batches.count)…" : "누락된 \(missing.count)개 영역 다시 번역 중…"
                        self.stage = .waiting
                        let current = NativeImageRegionBatch(regions: missing), stream = UUID()
                        self.streamID = stream
                        let partial: @Sendable (String) -> Void = { [weak self] text in
                            Task { @MainActor in
                                guard let self, self.generation == token, self.streamID == stream else { return }
                                let completed = current.completedTranslations(in: text)
                                if let draft = current.draft(in: text) {
                                    self.stage = .generating; self.activeRegionID = draft.id; self.draftText = draft.text
                                    if self.firstTextSeconds == nil { self.firstTextSeconds = Self.seconds(self.started.duration(to: .now)) }
                                } else if let last = current.regions.last(where: { completed[$0.id] != nil }), let value = completed[last.id] {
                                    self.stage = .generating; self.draftText = String(value.suffix(160))
                                }
                                // Tokens inside the next open block do not restart a completed block's display timer.
                                if completed.contains(where: { self.translations[$0.key] != $0.value }) {
                                    self.translations.merge(completed) { _, next in next }
                                    self.scheduleRender(token: token)
                                }
                            }
                        }
                        let response = try await translator.run(current, language.source, language.target, partial)
                        try Task.checkCancellation()
                        guard self.generation == token else { return }
                        self.streamID = nil
                        let parsed = current.completedTranslations(in: response)
                        for region in missing { self.translations[region.id] = nil }
                        self.translations.merge(parsed) { _, next in next }
                        missing = current.regions.filter { parsed[$0.id] == nil }
                        self.scheduleRender(token: token)
                    }
                }
                self.translationSeconds = Self.seconds(requestStart.duration(to: .now))
                self.stage = .applying
                await self.renderTask?.value
                try Task.checkCancellation()
                try await self.renderNow(token: token)
                guard self.generation == token else { return }
                let missing = requestRegions.filter { self.translations[$0.id] == nil }.count
                self.busy = false
                self.complete = missing == 0 && self.warning == nil
                self.stage = .finished; self.activeRegionID = nil; self.draftText = ""
                self.status = missing > 0 ? "\(missing)개 영역의 응답을 연결하지 못해 원본을 유지했습니다." : "\(found.count)개 영역 번역 처리 완료"
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == token else { return }
                self.streamID = nil; self.busy = false; self.complete = false
                self.stage = .failed; self.activeRegionID = nil; self.draftText = ""
                if case let CodexTranslationClient.ClientError.timeout(operation) = error {
                    self.failureKind = ["initialize", "config/read", "account/read", "model/list", "thread/start", "mcpServerStatus/list", "app/installed", "turn/start", "turn completion"].contains(operation) ? "codex.timeout.\(operation)" : "codex.timeout"
                } else { self.failureKind = String(describing: type(of: error)) }
                self.status = Self.message(error)
            }
        }
    }

    private func scheduleRender(token: UUID) {
        renderRequest += 1
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.renderTask = nil } }
            while self.generation == token, !Task.isCancelled {
                let requested = self.renderRequest
                do { try await self.renderNow(token: token) }
                catch is CancellationError { return }
                catch { self.warning = "번역을 이미지에 반영하지 못했습니다. 번역문으로 확인해 주세요."; return }
                if requested == self.renderRequest { return }
            }
        }
    }
    private func renderNow(token: UUID) async throws {
        guard generation == token else { return }
        let values = translations.filter { $0.key != 0 }
        guard !values.isEmpty, values != lastRenderedTranslations else { return }
        if renderer == nil, let preparation = rendererPreparation {
            let prepared = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
            try Task.checkCancellation()
            guard generation == token else { return }
            renderer = prepared; rendererPreparation = nil
        }
        guard let renderer else { return }
        let worker = Task.detached(priority: .userInitiated) { try renderer.render(values) }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard generation == token, values.allSatisfy({ translations[$0.key] == $0.value }) else { return }
        renderedImage = result.image
        lastRenderedTranslations = values; renderedRegionIDs = result.renderedIDs
        if !result.renderedIDs.isEmpty, firstResultSeconds == nil { firstResultSeconds = Self.seconds(started.duration(to: .now)) }
        if result.keptOriginalIDs.isEmpty { warning = nil }
        else {
            let reasons = Set(result.issues.values.map(\.explanation)).sorted().joined(separator: ", ")
            warning = "번역은 받았지만 \(reasons) \(result.keptOriginalIDs.count)개 영역을 원본으로 남겼어요. ‘번역문’에서 전체 결과를 확인하세요."
        }
    }
    func retry(direction: TranslationDirection) { if let image { load(image, direction: direction, selectionText: selectionText) } }
    func cancel() {
        generation = UUID(); streamID = nil; operation?.cancel(); operation = nil
        renderTask?.cancel(); renderTask = nil; rendererPreparation?.cancel(); rendererPreparation = nil; renderer = nil; busy = false
    }
    func clear() {
        cancel(); scanner.clear(); image = nil; renderedImage = nil; regions = []; translations = [:]; isImporting = false; selectionText = ""
        recognizedText = ""; status = ""; warning = nil; complete = false
        stage = .idle; draftText = ""; activeRegionID = nil; renderedRegionIDs = []; bodyFontPixels = 0; lastRenderedTranslations = [:]
        failureKind = nil
        ocrSeconds = nil; translationSeconds = nil; firstResultSeconds = nil; firstTextSeconds = nil
    }
    private static func seconds(_ duration: Duration) -> Double { Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18 }
    private static func languages(_ direction: TranslationDirection, text: String) -> (source: String, target: String) {
        switch direction {
        case .englishToKorean: ("en", "ko")
        case .koreanToEnglish: ("ko", "en")
        case .automatic: NLLanguageRecognizer.dominantLanguage(for: text) == .korean ? ("ko", "en") : ("en", "ko")
        }
    }
    private static func message(_ error: Error) -> String {
        if let own = error as? ImagePOCError { return own.localizedDescription }
        if let codex = error as? CodexTranslationClient.ClientError {
            switch codex {
            case .notAuthenticated, .unsupportedAccountType: return "Codex 구독 로그인이 필요합니다. 설정에서 연결을 확인해 주세요."
            case .modelUnavailable: return "선택한 Codex 모델을 사용할 수 없습니다. 설정에서 모델을 확인해 주세요."
            case .timeout: return "Codex 응답 시간이 초과됐습니다. 인식한 글자를 확인하고 다시 시도해 주세요."
            case .executableNotFound, .configuredExecutableInvalid, .executableUnsupported: return "Codex CLI 실행 경로와 지원 버전을 설정에서 확인해 주세요."
            default: return "Codex 번역 요청을 완료하지 못했습니다. 원본 이미지는 유지했습니다."
            }
        }
        if let claude = error as? ClaudeTranslationClient.ClientError {
            switch claude {
            case .authenticationRequired: return "Claude 구독 로그인이 필요합니다."
            case .modelUnavailable: return "선택한 Claude 모델을 사용할 수 없습니다."
            case .timeout: return "Claude 번역 응답 시간이 초과됐습니다."
            default: return "Claude 번역 요청을 완료하지 못했습니다. 원본 이미지는 유지했습니다."
            }
        }
        return "이미지 처리 중 오류가 발생했습니다. 더 크게 읽을 영역을 골라 다시 시도해 주세요."
    }
}

@MainActor struct NativeImageToolbar: View {
    let app: AppModel
    private var input: NativeImageInput { app.imageInput }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("글·이미지를 선택하고 ⌘C 두 번")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if !app.shortcutReady {
                    Button("단축키 연결 확인") { app.openInputMonitoringSettings() }.foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                if input.image != nil {
                    Button(input.prefersReadableSize ? "화면 맞춤" : "읽기 크기") { input.prefersReadableSize.toggle(); input.zoom = 1 }
                        .help("읽기 쉬운 크기로 확대하며 원래 배경과 배치는 유지합니다")
                    Button(input.showsOCR ? "이미지" : "인식한 글자") { input.showsOCR.toggle() }.disabled(input.recognizedText.isEmpty)
                }
                Button { ImagePOCIntegration.shared.scan() } label: { Image(systemName: "viewfinder") }
                    .help("화면에서 이미지 가져오기").disabled(input.scanner.busy)
                if input.scanner.lastRegion != nil { Button("다시 읽기") { ImagePOCIntegration.shared.rescan() }.disabled(input.scanner.busy) }
            }.controlSize(.small)
            Text("이미지는 Mac에서 읽고, 글자만 선택한 제공자에게 보냅니다. X 이미지는 원본 서버에서 불러옵니다.")
                .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(2)
            if let message = input.scanner.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.horizontal, 16).padding(.vertical, 6)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in input.scanner.refreshPermission() }
    }
}

@MainActor struct NativeImageSource: View {
    let input: NativeImageInput
    var body: some View {
        VStack(spacing: 5) {
            if !input.selectionText.isEmpty {
                ScrollView { Text(input.selectionText).font(.system(size: 16)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                    .frame(maxHeight: 96)
            }
            if input.showsOCR {
                ScrollView { Text(input.recognizedText).font(.system(size: 16)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
            } else if let image = input.image {
                NativeImageHost(image: image.pixels, zoom: input.zoom, bodyFontPixels: input.bodyFontPixels, readable: input.prefersReadableSize).id(input.identity)
            }
        }
    }
}

@MainActor struct NativeImageResult: View {
    let input: NativeImageInput
    var body: some View {
        if input.showsTextResult {
            ScrollView { Text(input.copyText).font(.system(size: 16)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
        } else {
            VStack(spacing: 5) {
                if !input.selectionText.isEmpty {
                    ScrollView { Text(input.translations[0] ?? (input.busy ? "선택한 글 번역 대기" : "번역 결과 없음")).font(.system(size: 16)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                        .frame(maxHeight: 96)
                }
                if let image = input.renderedImage {
                    NativeImageHost(image: image, zoom: input.zoom, bodyFontPixels: input.bodyFontPixels, readable: input.prefersReadableSize,
                                    pendingBoxes: input.pendingBoxes, activeBox: input.activeBox).id(input.identity)
                } else { Text(input.status).font(.system(size: 12)).foregroundStyle(.secondary).padding(12); Spacer() }
            }
        }
    }
}

@MainActor struct NativeImageFooter: View {
    let app: AppModel
    private var input: NativeImageInput { app.imageInput }
    var body: some View {
        HStack(spacing: 7) {
            if input.busy { ProgressView().controlSize(.small) }
            Text(input.warning ?? input.status).font(.system(size: 11)).lineLimit(2)
                .help([input.providerLabel, input.timing].filter { !$0.isEmpty }.joined(separator: " · "))
            Spacer(minLength: 0)
            Button(input.showsTextResult ? "이미지" : "번역문") { input.showsTextResult.toggle() }.disabled(input.translations.isEmpty)
            Button("−") { input.zoom = max(1, input.zoom - 0.5) }.disabled(input.zoom <= 1)
            Button("+") { input.zoom = min(4, input.zoom + 0.5) }.disabled(input.zoom >= 4)
            if !input.busy {
                if input.image != nil { Button("다시 번역") { input.retry(direction: app.store.direction) } }
                else { Button("다시 불러오기") { ImagePOCIntegration.shared.retryImport() } }
            }
            Button("복사") {
                guard let image = input.renderedImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png, forType: .png)
            }.disabled(!input.complete)
        }.controlSize(.small).padding(.horizontal, 10)
    }
}

@MainActor struct NativeImageHost: NSViewRepresentable {
    let image: CGImage
    let zoom: Double
    var bodyFontPixels: CGFloat = 0
    var readable = false
    var pendingBoxes: [CGRect] = []
    var activeBox: CGRect?
    func makeNSView(context: Context) -> NativeImageScroll { NativeImageScroll() }
    func updateNSView(_ scroll: NativeImageScroll, context: Context) {
        scroll.canvas.image = image; scroll.canvas.pendingBoxes = pendingBoxes; scroll.canvas.activeBox = activeBox
        scroll.layoutImage()
        let desired = ImageReadingGeometry.magnification(imageWidth: image.width, viewportWidth: scroll.contentView.frame.width,
                                                       bodyFontPixels: bodyFontPixels, readable: readable, zoom: zoom)
        if scroll.lastRequestedMagnification.map({ abs($0 - desired) > 0.01 }) ?? true {
            let origin = scroll.contentView.bounds.origin
            scroll.magnification = desired; scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
            scroll.lastRequestedMagnification = desired
        }
        scroll.canvas.viewMagnification = scroll.magnification
        scroll.canvas.needsDisplay = true
    }
}
@MainActor final class NativeImageScroll: NSScrollView {
    let canvas = NativeImageCanvas()
    var lastRequestedMagnification: CGFloat?
    override init(frame: CGRect) {
        super.init(frame: frame)
        drawsBackground = false; hasVerticalScroller = true; hasHorizontalScroller = true
        allowsMagnification = true; minMagnification = 1; maxMagnification = 8; documentView = canvas
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tile() { super.tile(); layoutImage() }
    func layoutImage() {
        // bounds shrink while magnifying. Using them here cancels zoom by fitting the image again.
        let viewport = contentView.frame.size
        guard let image = canvas.image, viewport.width > 0 else { return }
        let scale = max(1, viewport.width - 12) / CGFloat(image.width)
        let size = CGSize(width: viewport.width, height: max(viewport.height, CGFloat(image.height) * scale + 12))
        if canvas.frame.size != size { canvas.setFrameSize(size) }; canvas.needsDisplay = true
    }
}
@MainActor final class NativeImageCanvas: NSView {
    var image: CGImage?
    var pendingBoxes: [CGRect] = []
    var activeBox: CGRect?
    var viewMagnification: CGFloat = 1
    override var isFlipped: Bool { true }
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.png, .tiff, .fileURL, .html])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        POCImage.isConcealed(sender.draggingPasteboard) ? [] : .copy
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { ImagePOCIntegration.shared.paste(sender.draggingPasteboard) }
    override func draw(_ dirtyRect: CGRect) {
        guard let image else { return }
        let size = CGSize(width: image.width, height: image.height)
        let target = ImageReadingGeometry.imageRect(size: size, in: bounds)
        NSImage(cgImage: image, size: size).draw(in: target,
                                              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for box in pendingBoxes {
            let rect = ImageReadingGeometry.textRect(box, in: target).insetBy(dx: -2 / viewMagnification, dy: -2 / viewMagnification)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3 / viewMagnification, yRadius: 3 / viewMagnification)
            let active = box == activeBox
            path.lineWidth = (active ? 1.5 : 0.8) / viewMagnification
            if !active { path.setLineDash([3 / viewMagnification, 3 / viewMagnification], count: 2, phase: 0) }
            NSColor.controlAccentColor.withAlphaComponent(active ? 0.9 : 0.45).setStroke(); path.stroke()
        }
    }
}
#endif
