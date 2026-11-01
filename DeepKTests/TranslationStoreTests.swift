import Foundation

actor TranslationProbe {
    private var requests: [TranslationRequest] = []
    private var requestWaiters: [CheckedContinuation<TranslationRequest, Never>] = []
    private var completions: [UUID: CheckedContinuation<String, Error>] = [:]
    private var cancelledRequestIDs = Set<UUID>()
    private var totalRequestCount = 0

    func translate(_ request: TranslationRequest) async throws -> String {
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                completions[request.id] = continuation
                totalRequestCount += 1

                if !requestWaiters.isEmpty {
                    requestWaiters.removeFirst().resume(returning: request)
                } else {
                    requests.append(request)
                }
            }
        }, onCancel: {
            Task { await self.recordCancellation(for: request.id) }
        })
    }

    func nextRequest() async -> TranslationRequest {
        if !requests.isEmpty {
            return requests.removeFirst()
        }

        let watchdog = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { fatalError("Expected translation request did not arrive within five seconds") }
        }
        defer { watchdog.cancel() }
        return await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func complete(_ requestID: UUID, with text: String) {
        completions.removeValue(forKey: requestID)?.resume(returning: text)
    }

    func fail(_ requestID: UUID, with error: Error) {
        completions.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    func requestCount() -> Int {
        totalRequestCount
    }

    /// The requests that arrived and were not taken yet, without waiting.
    func takeRequests() -> [TranslationRequest] {
        defer { requests.removeAll() }
        return requests
    }

    func wasCancelled(_ requestID: UUID) -> Bool {
        cancelledRequestIDs.contains(requestID)
    }

    private func recordCancellation(for requestID: UUID) {
        cancelledRequestIDs.insert(requestID)
    }
}

@MainActor
private enum TranslationStoreTests {
    static func runAll() async {
        await IncrementalTranslationTests.runAll()
        await OutputCheckStoreTests.runAll()
        await CodeBlockStoreTests.runAll()
        await providerErrorsShowGuidanceAndRemainRetryable()
        await cosmeticWhitespaceUsesCache()
        await cosmeticWhitespaceReusesActiveRequest()
        await structuralWhitespaceDoesNotShareCache()
        await cacheSeparatesProvidersAndExpires()
        await cacheEvictsLeastRecentlyUsedFirst()
        await expiredEntriesDoNotEvictLiveOnes()
        await emptyExplicitInvocationReportsAnError()
        await explicitRequestBypassesDebounceAndAllowsCopy()
        await repeatedCopiedInputIsDeduplicatedUntilAnError()
        await providerChangeWaitsForExplicitRetranslation()
        await providerChangeCancelsAnActiveRequest()
        await resultKeepsTheActualModelLabel()
        await lateCompletionCannotReplaceNewerResult()
        await providerCancellationIsIgnoredWhenProviderStillCompletes()
        await languageChangeCancelsAndUsesTheNewDirection()
        await ambiguousEnglishUsesConservativeFallback()
        await undecidedLanguageIsPickedForThisSourceOnly()
        await koreanTargetFollowsTheDirection()
        directionRawValuesRoundTrip()
        await imeCompositionDoesNotRequestUntilCompositionEnds()
        await duplicateEditorCallbacksDoNotRestartTheRequest()
        await automaticRequestUsesConfigurableDebounce()
        await defaultConfigurationUsesHalfSecondDebounce()
        await connectingResumesLatestUserInputButNotSelection()
        await refreshingAnAlreadyReadyEngineKeepsItsRequest()
        await inputLengthIsValidatedExplicitly()
        await emptyProviderResultBecomesAnError()
        await timeoutBecomesAnError()
        await codeFencesAreNormalizedAtCompletion()
        await copiedStructureTravelsWithTheSource()
        await copiedPrefixSurvivesAppendAndRetranslation()
        await copiedPrefixKeepsItsInternalBoundaries()
        await copiedPrefixRequiresExactBytes()
        await capturedAndAuthoredInlineCodeKeepTheirCopyPolicies()
        await copiedBlockSameLineExtensionIsPlain()
        await structureReview()
        await partialSourcesAndInsertionText()
        await singleWordChatCommandsSurviveCompletionAndInsertion()
        await unknownTagsAreNeverInserted()
        await appFencesKeepThePrompt()
    }

    private static func providerErrorsShowGuidanceAndRemainRetryable() async {
        struct LoginRequired: LocalizedError {
            var errorDescription: String? { "구독 로그인 후 다시 연결해 주세요." }
        }
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("Hello world.")
        let first = await probe.nextRequest()
        await probe.fail(first.id, with: LoginRequired())
        await settle()
        require(store.status == .error(.provider("구독 로그인 후 다시 연결해 주세요.")),
                "show recovery guidance rather than the internal error type")
        require(!store.canCopy && !store.lastResultWasCached, "failed responses must not become cached results")
        store.invokeCopiedText("Hello world. ")
        let retry = await probe.nextRequest()
        require(await probe.requestCount() == 2, "an equivalent input must retry after a failure")
        await probe.complete(retry.id, with: "안녕하세요.")
        await settle()
        require(store.canCopy, "successful retry should restore normal result actions")
    }

    private static func cosmeticWhitespaceUsesCache() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("Hello world.")
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: "안녕하세요.")
        await settle()
        store.editSource("  Hello   world.\n\n", isComposing: false)
        require(store.status == .success && store.lastResultWasCached, "cosmetic edits must return immediately")
        require(store.canCopy && store.result?.input == store.sourceText, "cache must use the current input snapshot")
        require(await probe.requestCount() == 1, "cache hit must not send another request")
        store.beginComposition()
        require(!store.canCopy, "IME composition must invalidate cached copy availability")
        store.endComposition("Hello world. ")
        require(store.lastResultWasCached, "completed composition may reuse a cached result")
    }

    private static func cosmeticWhitespaceReusesActiveRequest() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("Hello world.")
        let first = await probe.nextRequest()
        store.editSource("Hello  world.\n", isComposing: false)
        await settle()
        require(await probe.requestCount() == 1, "equivalent inflight input must not duplicate a request")
        require(!(await probe.wasCancelled(first.id)), "cosmetic input should keep its inflight request")
        await probe.complete(first.id, with: "안녕하세요.")
        await settle()
        require(store.result?.input == "Hello  world.\n" && store.canCopy, "inflight result must attach to the newest version")
    }

    private static func structuralWhitespaceDoesNotShareCache() async {
        for (original, edited) in [("Hello world.", "Hello\nworld."), ("let x = `a b`", "let x = `a  b`"), ("- hello", "-  hello"), ("print('a b')", "print('a  b')"), ("Hello world.", "Helloworld.")] {
            let probe = TranslationProbe()
            let store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.invokeCopiedText(original)
            let first = await probe.nextRequest()
            await probe.complete(first.id, with: "처음")
            await settle()
            store.invokeCopiedText(edited)
            let second = await probe.nextRequest()
            require(await probe.requestCount() == 2, "structural edits must request their own result")
            await probe.complete(second.id, with: "변경됨")
            await settle()
        }
    }

    private static func cacheSeparatesProvidersAndExpires() async {
        let probe = TranslationProbe()
        let store = TranslationStore(configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 1, cacheLifetime: .milliseconds(80)), engineReady: true, cacheContext: "codex:luna", translator: { try await probe.translate($0) })
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("hello")
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: "Luna 결과")
        await settle()
        store.prepareForProviderChange(cacheContext: "claude:haiku")
        store.retranslateSelection()
        let second = await probe.nextRequest()
        await probe.complete(second.id, with: "Haiku 결과")
        await settle()
        require(await probe.requestCount() == 2, "different providers must not share entries")
        store.prepareForProviderChange(cacheContext: "codex:luna")
        store.retranslateSelection()
        let evicted = await probe.nextRequest()
        require(await probe.requestCount() == 3, "bounded cache must evict its oldest entry")
        await probe.complete(evicted.id, with: "새 결과")
        await settle()
        try? await Task.sleep(for: .milliseconds(100))
        // A trailing space is covered by the on-screen document; a leading one
        // must go through the expired cache entry.
        store.editSource(" hello", isComposing: false)
        let expired = await probe.nextRequest()
        require(await probe.requestCount() == 4, "expired result must not be reused")
        await probe.complete(expired.id, with: "만료 후 결과")
        await settle()
        require(store.testCacheEntryCount == 1 && store.testCacheIsConsistent, "capacity one keeps a single consistent entry")
    }

    private static func cacheEvictsLeastRecentlyUsedFirst() async {
        // Each entry counts 6 × 10 bytes: the key, the result, and the document's and basis's
        // source and translation. 150 bytes therefore hold two entries, like a capacity of two.
        for configuration in [
            TranslationStore.Configuration(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 2),
            TranslationStore.Configuration(typingDebounce: .zero, requestTimeout: nil, maximumCacheBytes: 150)
        ] {
            let probe = TranslationProbe()
            let store = TranslationStore(configuration: configuration, engineReady: true, translator: { try await probe.translate($0) })
            store.setDirection(.englishToKorean)
            var requests = 0
            // Reusing Alpha moves it behind Bravo, so Delta evicts Bravo rather than the older Alpha.
            for (source, cached) in [("Alpha one.", false), ("Bravo two.", false), ("Alpha one.", true), ("Delta six.", false),
                                     ("Delta six.", true), ("Alpha one.", true), ("Bravo two.", false), ("Alpha one.", true)] {
                store.editSource("", isComposing: false)
                store.invokeCopiedText(source)
                if cached {
                    require(store.lastResultWasCached && store.resultText == source.uppercased(), "\(source) is answered from the cache")
                } else {
                    require(store.status == .translating && !store.lastResultWasCached, "\(source) is not in the cache")
                    let request = await probe.nextRequest()
                    await probe.complete(request.id, with: source.uppercased())
                    await settle()
                    requests += 1
                }
                let count = await probe.requestCount()
                require(count == requests, "only misses call the provider")
            }
            require(store.testCacheEntryCount == 2 && store.testCacheIsConsistent, "eviction keeps the byte total and order exact")
        }
    }

    private static func expiredEntriesDoNotEvictLiveOnes() async {
        // A hit moves an entry behind newer ones but does not extend its lifetime,
        // so the most recently used entry can be the first to expire.
        let probe = TranslationProbe()
        let store = TranslationStore(configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 2, cacheLifetime: .milliseconds(400)), engineReady: true, translator: { try await probe.translate($0) })
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("first entry")
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: "FIRST ENTRY")
        await settle()
        try? await Task.sleep(for: .milliseconds(200))
        store.editSource("", isComposing: false)
        store.invokeCopiedText("second entry")
        let second = await probe.nextRequest()
        await probe.complete(second.id, with: "SECOND ENTRY")
        await settle()
        store.editSource("", isComposing: false)
        store.invokeCopiedText("first entry")
        require(store.lastResultWasCached, "the first entry is reused before it expires")
        try? await Task.sleep(for: .milliseconds(210))
        store.editSource("", isComposing: false)
        store.invokeCopiedText("third entry")
        require(store.status == .translating && store.testCacheEntryCount == 1 && store.testCacheIsConsistent,
                "a lookup for any key drops the expired entry")
        let third = await probe.nextRequest()
        await probe.complete(third.id, with: "THIRD ENTRY")
        await settle()
        require(store.resultText == "THIRD ENTRY", "the third entry completes")
        store.editSource("", isComposing: false)
        store.invokeCopiedText("second entry")
        require(store.lastResultWasCached && store.resultText == "SECOND ENTRY", "an expired entry must not push out a live one")
        require(await probe.requestCount() == 3, "the live entry needs no request")
        require(store.testCacheEntryCount == 2 && store.testCacheIsConsistent, "only live entries remain")
    }

    private static func emptyExplicitInvocationReportsAnError() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)

        store.invokeCopiedText(" \n\t")

        require(store.status == .error(.emptyInput), "empty copied text should be an explicit error")
        require(await probe.requestCount() == 0, "empty copied text must not call the provider")
    }

    private static func explicitRequestBypassesDebounceAndAllowsCopy() async {
        let probe = TranslationProbe()
        let store = makeStore(
            probe: probe,
            engineReady: true,
            debounce: .seconds(10)
        )

        store.setDirection(.englishToKorean)
        store.invokeCopiedText("Hello")
        let request = await probe.nextRequest()

        require(request.input == "Hello", "explicit invocation should preserve the copied input")
        require(store.status == .translating, "an explicit request should start immediately")

        await probe.complete(request.id, with: "안녕하세요")
        await settle()

        require(store.status == .success, "a current provider result should complete successfully")
        require(store.resultText == "안녕하세요", "the result text should be exposed to the view")
        require(store.canCopy, "a current result should be copyable")
        require(store.canInsert, "a current result should be eligible for integration validation")
    }

    private static func repeatedCopiedInputIsDeduplicatedUntilAnError() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)

        store.setDirection(.englishToKorean)
        store.invokeCopiedText("same input")
        let first = await probe.nextRequest()

        store.invokeCopiedText("same input")
        try? await Task.sleep(for: .milliseconds(5))
        require(await probe.requestCount() == 1, "an identical copied input must not duplicate an active request")

        await probe.complete(first.id, with: "같은 입력")
        await settle()
        store.invokeCopiedText("same input")
        try? await Task.sleep(for: .milliseconds(5))
        require(await probe.requestCount() == 1, "an identical copied input must not duplicate a completed result")

        store.invokeCopiedText("retry")
        let failed = await probe.nextRequest()
        await probe.fail(failed.id, with: TranslationStoreError.provider("temporary failure"))
        await settle()
        require(store.status == .error(.provider("temporary failure")), "the fake provider failure should be visible")

        store.invokeCopiedText("retry")
        let retried = await probe.nextRequest()
        require(await probe.requestCount() == 3, "an explicit retry after an error must call the provider again")
        await probe.complete(retried.id, with: "재시도 성공")
        await settle()
        require(store.resultText == "재시도 성공", "the explicit retry result should become current")
    }

    private static func providerChangeWaitsForExplicitRetranslation() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)

        store.setDirection(.englishToKorean)
        store.invokeCopiedText("same source")
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: "첫 번째 모델")
        await settle()

        require(store.resultText == "첫 번째 모델", "the initial provider result should be current")

        store.setTranslationContext(
            cacheContext: "v1|claude|haiku",
            provider: "claude",
            model: "haiku",
            modelLabel: "Claude Code · haiku"
        )
        require(store.resultText == "첫 번째 모델", "a provider change should keep the displayed result")
        require(store.resultModelLabel == nil, "a result without context metadata keeps no fabricated model label")
        require(store.requiresRetranslation, "a provider change should require an explicit action")
        try? await Task.sleep(for: .milliseconds(5))
        require(await probe.requestCount() == 1, "changing provider or model must not auto-request")

        store.retranslateSelection()
        require(store.resultText == nil, "an explicit retranslation may replace the previous result")

        let second = await probe.nextRequest()
        require(second.input == "same source", "a provider change should reuse the current source")
        require(await probe.requestCount() == 2, "a provider change should issue one fresh request")

        await probe.complete(second.id, with: "두 번째 모델")
        await settle()
        require(store.resultText == "두 번째 모델", "the new provider result should replace the old result")
    }

    private static func resultKeepsTheActualModelLabel() async {
        let probe = TranslationProbe()
        let store = TranslationStore(
            configuration: .init(typingDebounce: .zero, requestTimeout: nil),
            engineReady: true,
            cacheContext: "v1|codex|gpt-5.6-luna",
            translator: { try await probe.translate($0) }
        )
        store.setTranslationContext(
            cacheContext: "v1|codex|gpt-5.6-luna",
            provider: "codex",
            model: "gpt-5.6-luna",
            modelLabel: "Codex · gpt-5.6-luna"
        )
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("model label")
        let request = await probe.nextRequest()
        require(request.modelLabel == "Codex · gpt-5.6-luna", "the request should freeze the selected model label")
        await probe.complete(request.id, with: "모델 표시")
        await settle()
        require(store.resultModelLabel == "Codex · gpt-5.6-luna", "the displayed result should retain the actual model label")

        store.setTranslationContext(
            cacheContext: "v1|codex|gpt-5.6-terra",
            provider: "codex",
            model: "gpt-5.6-terra",
            modelLabel: "Codex · gpt-5.6-terra"
        )
        require(store.resultModelLabel == "Codex · gpt-5.6-luna", "selection changes must not relabel an existing result")
    }

    private static func providerChangeCancelsAnActiveRequest() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("진행 중 선택 변경")
        let stale = await probe.nextRequest()

        store.setTranslationContext(
            cacheContext: "v1|claude|haiku",
            provider: "claude",
            model: "haiku",
            modelLabel: "Claude Code · haiku"
        )
        require(store.requiresRetranslation, "changing selection during a request should require explicit retry")
        await settle()
        require(await probe.wasCancelled(stale.id), "changing selection should cancel the old request")
        await probe.complete(stale.id, with: "늦은 이전 결과")
        await settle()
        require(store.resultText == nil, "a late result from the old selection must be ignored")
        require(await probe.requestCount() == 1, "selection change must not auto-request")

        store.retranslateSelection()
        let current = await probe.nextRequest()
        require(current.provider == "claude" && current.model == "haiku", "explicit retry should use the new selection")
        await probe.complete(current.id, with: "새 결과")
        await settle()
        require(store.resultText == "새 결과", "the explicit retry should become visible")
    }

    private static func lateCompletionCannotReplaceNewerResult() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)

        store.setDirection(.englishToKorean)
        store.invokeCopiedText("first")
        let first = await probe.nextRequest()

        store.invokeCopiedText("again")
        let second = await probe.nextRequest()

        await probe.complete(second.id, with: "두 번째")
        await settle()
        require(store.resultText == "두 번째", "the newer result should be visible")

        await probe.complete(first.id, with: "첫 번째")
        await settle()
        require(store.resultText == "두 번째", "a late result must not replace a newer result")
        require(store.result?.id == second.id, "the latest result ID should remain the newer request")
    }

    private static func providerCancellationIsIgnoredWhenProviderStillCompletes() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)

        store.setDirection(.englishToKorean)
        store.invokeCopiedText("old text")
        let staleRequest = await probe.nextRequest()

        store.editSource("", isComposing: false)
        await settle()
        require(await probe.wasCancelled(staleRequest.id), "editing should cancel the active request")

        // 취소를 무시하고 늦게 완료하는 제공자를 재현한다.
        await probe.complete(staleRequest.id, with: "오래된 결과")
        await settle()
        require(store.resultText == nil, "a provider that ignores cancellation must still be ignored")
        require(store.status == .idle, "clearing the source should return to idle")
    }

    private static func languageChangeCancelsAndUsesTheNewDirection() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)

        store.invokeCopiedText("hello")
        let original = await probe.nextRequest()
        require(
            original.sourceLanguage == .english && original.targetLanguage == .korean,
            "automatic English detection should target Korean"
        )

        store.setDirection(.koreanToEnglish)
        let changed = await probe.nextRequest()
        require(
            changed.sourceLanguage == .korean && changed.targetLanguage == .english,
            "a manual direction should override automatic detection"
        )
        require(await probe.requestCount() == 2, "a changed direction should create one new provider request")

        await probe.complete(original.id, with: "old")
        await probe.complete(changed.id, with: "new")
        await settle()

        require(store.result?.id == changed.id, "the language change should invalidate the old result")
        require(store.result?.direction == .koreanToEnglish, "the result should retain the current direction")
    }

    /// A short Cyrillic phrase ranks Kazakh first: Russian is offered, and the pick holds until a new copy.
    private static func undecidedLanguageIsPickedForThisSourceOnly() async {
        let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
        store.invokeCopiedText("Привет мир")
        require(store.status == .error(.unsupportedLanguage), "a Kazakh-ranked phrase is undecided")
        require(store.undecidedLanguageCandidates.contains(.russian), "Russian is offered: \(store.undecidedLanguageCandidates)")

        store.translateSource(as: .russian)
        let picked = await probe.nextRequest()
        require(picked.sourceLanguage == .russian && picked.targetLanguage == .korean, "the pick is the source language")
        await probe.complete(picked.id, with: "안녕 세상")
        await waitForSuccess(store)
        require(store.undecidedLanguageCandidates.isEmpty, "a decided source offers nothing")

        store.editSource("Привет мир!", isComposing: false)
        let edited = await probe.nextRequest()
        require(edited.sourceLanguage == .russian, "editing the same source keeps the pick")
        await probe.complete(edited.id, with: "안녕 세상!")
        await waitForSuccess(store)

        store.invokeCopiedText("مرحبا بالعالم")
        try? await Task.sleep(for: .milliseconds(30))
        require(store.sourceLanguageOverride == nil, "a new copy drops the pick")
        require(await probe.takeRequests().isEmpty, "a new undecided copy is not sent")

        let fixed = makeStore(probe: TranslationProbe(), engineReady: true)
        fixed.setDirection(.englishToKorean)
        fixed.translateSource(as: .russian)
        require(fixed.sourceLanguageOverride == nil, "a fixed direction takes no pick")
    }

    private static func koreanTargetFollowsTheDirection() async {
        let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
        store.setDirection(TranslationDirection(source: nil, koreanTarget: .japanese))
        store.invokeCopiedText("회의는 다음 주 화요일로 옮겨도 괜찮을까요?")
        let korean = await probe.nextRequest()
        require(korean.sourceLanguage == .korean && korean.targetLanguage == .japanese, "automatic Korean goes to the chosen language")
        await probe.complete(korean.id, with: "会議は来週の火曜日に移しても大丈夫でしょうか？")
        await waitForSuccess(store)

        store.invokeCopiedText("The meeting starts at three in the afternoon.")
        let english = await probe.nextRequest()
        require(english.sourceLanguage == .english && english.targetLanguage == .korean, "other languages still go to Korean")
        await probe.complete(english.id, with: "회의는 오후 세 시에 시작합니다.")
        await waitForSuccess(store)

        store.setDirection(TranslationDirection(source: .korean, koreanTarget: .german))
        store.invokeCopiedText("안녕하세요")
        let fixed = await probe.nextRequest()
        require(fixed.sourceLanguage == .korean && fixed.targetLanguage == .german, "a fixed Korean source uses the chosen language")
        await probe.complete(fixed.id, with: "Hallo")
    }

    private static func directionRawValuesRoundTrip() {
        // Values saved before more languages keep their meaning.
        require(TranslationDirection(rawValue: "auto") == .automatic && TranslationDirection.automatic.rawValue == "auto", "auto")
        require(TranslationDirection(rawValue: "en-ko") == .englishToKorean, "en-ko")
        require(TranslationDirection(rawValue: "ko-en") == .koreanToEnglish, "ko-en")
        for direction in [TranslationDirection(source: nil, koreanTarget: .simplifiedChinese),
                          TranslationDirection(source: .traditionalChinese),
                          TranslationDirection(source: .korean, koreanTarget: .traditionalChinese),
                          TranslationDirection(source: .vietnamese)] {
            require(TranslationDirection(rawValue: direction.rawValue) == direction, "round trip: \(direction.rawValue)")
        }
        require(TranslationDirection(source: .korean, koreanTarget: .traditionalChinese).rawValue == "ko-zh-Hant", "a code with a dash")
        require(TranslationDirection(rawValue: "auto>zh-Hans")?.koreanTarget == .simplifiedChinese, "automatic keeps where Korean goes")
        for invalid in ["ja-en", "ko-ko", "auto>ko", "xx-ko", "auto>"] {
            require(TranslationDirection(rawValue: invalid) == nil, "invalid: \(invalid)")
        }
        // A fixed non-Korean source does not depend on where Korean goes.
        require(TranslationDirection(source: .japanese, koreanTarget: .german) == TranslationDirection(source: .japanese),
                "the Korean target does not change a fixed Japanese source")
    }

    private static func imeCompositionDoesNotRequestUntilCompositionEnds() async {
        let probe = TranslationProbe()
        let store = makeStore(
            probe: probe,
            engineReady: true,
            debounce: .milliseconds(20)
        )

        store.beginComposition()
        store.updateComposition("안녕")
        store.updateComposition("안녕")
        store.retranslateForProviderChange()
        try? await Task.sleep(for: .milliseconds(50))
        require(await probe.requestCount() == 0, "IME composition must not trigger a request")

        store.endComposition("안녕")
        store.endComposition("안녕")
        let request = await probe.nextRequest()
        require(await probe.requestCount() == 1, "composition commit should create one provider request")
        require(request.input == "안녕", "the final composed text should be requested")
        require(request.sourceLanguage == .korean, "automatic detection should identify Korean")
        require(request.targetLanguage == .english, "Korean should target English")
        await probe.complete(request.id, with: "Hello")
    }

    private static func ambiguousEnglishUsesConservativeFallback() async {
        let english = [
            "I smell fear",
            "Keep both rows and their values.\n\n| Item | Count | Status |\n| --- | ---: | --- |\n| Report INV-2048 | 120 | Pending |\n| Backup BK-0045 | 45 | Complete |\n\nDo not swap the counts."
        ]
        for input in english {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.invokeCopiedText(input)
            require(store.status != .error(.unsupportedLanguage), "ambiguous English must reach the provider")
            let request = await probe.nextRequest()
            require(request.sourceLanguage == .english && request.targetLanguage == .korean,
                    "English is the substantial supported alternative")
            await probe.complete(request.id, with: "영어 문장을 번역했습니다.")
            await waitForSuccess(store)
        }

        // Neither a confident Latin-language result nor a non-Latin alphabet is coerced to English.
        // Supported languages go to Korean; the others stay undecided.
        let detected: [(String, TranslationLanguage)] = [
            ("Hola mundo", .spanish), ("Bonjour tout le monde", .french), ("こんにちは世界", .japanese),
            ("你好世界", .traditionalChinese), ("Die Methode wird asynchron ausgeführt.", .german), ("No sé.", .spanish)
        ]
        for (input, language) in detected {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.invokeCopiedText(input)
            let request = await probe.nextRequest()
            require(request.sourceLanguage == language && request.targetLanguage == .korean,
                    "\(input) is \(language.rawValue) → ko, got \(request.sourceLanguage.rawValue) → \(request.targetLanguage.rawValue)")
            await probe.complete(request.id, with: "번역")
        }
        for input in ["Jeg er veldig glad", "Привет мир", "مرحبا بالعالم", "12345 — !"] {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.invokeCopiedText(input)
            require(store.status == .error(.unsupportedLanguage), "unsupported input stays unsupported: \(input)")
            require(await probe.requestCount() == 0, "unsupported language must not make a provider request")
        }

        let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
        store.invokeCopiedText("The meeting starts at three in the afternoon.")
        await probe.complete((await probe.nextRequest()).id, with: "회의는 오후 세 시에 시작합니다.")
        await waitForSuccess(store)
        store.editSource(store.sourceText + "\n\nI smell fear", isComposing: false)
        let tail = await probe.nextRequest()
        require(tail.input == "I smell fear" && tail.sourceLanguage == .english,
                "an ambiguous English tail keeps the completed prefix")
        await probe.complete(tail.id, with: "두려움의 냄새가 납니다.")
        await waitForSuccess(store)
    }

    private static func duplicateEditorCallbacksDoNotRestartTheRequest() async {
        let probe = TranslationProbe()
        let store = makeStore(
            probe: probe,
            engineReady: true,
            debounce: .milliseconds(30)
        )

        store.setDirection(.englishToKorean)
        store.editSource("duplicate callback", isComposing: false)
        store.editSource("duplicate callback", isComposing: false)
        store.editSource("duplicate callback", isComposing: false)
        try? await Task.sleep(for: .milliseconds(10))
        require(await probe.requestCount() == 0, "duplicate callbacks before the debounce must not call the provider")

        let request = await probe.nextRequest()
        store.editSource("duplicate callback", isComposing: false)
        try? await Task.sleep(for: .milliseconds(5))
        require(await probe.requestCount() == 1, "duplicate callbacks during an active request must not restart it")
        await probe.complete(request.id, with: "중복 콜백")
    }

    private static func automaticRequestUsesConfigurableDebounce() async {
        let probe = TranslationProbe()
        let store = makeStore(
            probe: probe,
            engineReady: true,
            debounce: .milliseconds(35)
        )

        store.setDirection(.englishToKorean)
        store.editSource("t", isComposing: false)
        require(store.status == .waiting, "normal editor input should enter the waiting state")
        try? await Task.sleep(for: .milliseconds(5))
        store.editSource("ty", isComposing: false)
        try? await Task.sleep(for: .milliseconds(5))
        store.editSource("typing", isComposing: false)
        try? await Task.sleep(for: .milliseconds(5))
        require(await probe.requestCount() == 0, "a normal edit should wait for the configured debounce")

        let request = await probe.nextRequest()
        require(request.input == "typing", "the final edit after a short pause should be requested")
        await probe.complete(request.id, with: "타이핑")
    }

    private static func defaultConfigurationUsesHalfSecondDebounce() async {
        require(
            TranslationStore.Configuration().typingDebounce == .milliseconds(500),
            "the default typing debounce should wait half a second"
        )
    }

    private static func connectingResumesLatestUserInputButNotSelection() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: false, debounce: .milliseconds(10))
        store.setDirection(.englishToKorean)
        store.editSource("first input", isComposing: false)
        store.editSource("latest input", isComposing: false)
        require(await probe.requestCount() == 0, "연결 전에는 요청하지 않는다")
        store.setEngineReady(true)
        let first = await probe.nextRequest()
        require(first.input == "latest input", "연결 후에는 최신 사용자 입력 하나만 재개한다")
        await probe.complete(first.id, with: "최근 입력")
        await settle()
        store.setEngineReady(false)
        store.invokeCopiedText("copied while connecting")
        store.setEngineReady(true)
        let copied = await probe.nextRequest()
        require(copied.input == "copied while connecting", "두 번 복사 대기는 연결 후 재개한다")
        await probe.complete(copied.id, with: "대기 복사")
        await settle()
        store.setEngineReady(false)
        store.editSource("new user input", isComposing: false)
        store.prepareForProviderChange(cacheContext: "different-model")
        store.setEngineReady(true)
        try? await Task.sleep(for: .milliseconds(30))
        require(await probe.requestCount() == 2, "선택 변경이 취소한 대기는 재연결로 전송하지 않는다")
    }

    private static func refreshingAnAlreadyReadyEngineKeepsItsRequest() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("연결 확인 중에도 유지")
        let request = await probe.nextRequest()
        store.setEngineReady(true)
        await settle()
        require(!(await probe.wasCancelled(request.id)), "refreshing an already-ready engine must not cancel work")
        await probe.complete(request.id, with: "유지된 결과")
        await settle()
        require(store.resultText == "유지된 결과", "the active request should complete after a no-op refresh")
    }

    private static func inputLengthIsValidatedExplicitly() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)

        store.invokeCopiedText(String(repeating: "a", count: 4_001))

        require(
            store.status == .error(.inputTooLong(limit: 4_000)),
            "input above the initial limit should report an explicit error"
        )
        require(await probe.requestCount() == 0, "overlong input must not call the provider")
    }

    private static func timeoutBecomesAnError() async {
        let store = TranslationStore(
            configuration: .init(
                typingDebounce: .zero,
                requestTimeout: .milliseconds(20)
            ),
            engineReady: true,
            translator: { _ in
                try await Task.sleep(for: .seconds(1))
                return "late"
            }
        )

        store.setDirection(.englishToKorean)
        store.invokeCopiedText("timeout")
        for _ in 0..<100 {
            if store.status == .error(.timedOut) { return }
            try? await Task.sleep(for: .milliseconds(2))
        }

        fail("a request exceeding the configured timeout should report timedOut")
    }

    private static func emptyProviderResultBecomesAnError() async {
        let store = TranslationStore(
            configuration: .init(
                typingDebounce: .zero,
                requestTimeout: nil
            ),
            engineReady: true,
            translator: { _ in " \n" }
        )

        store.setDirection(.englishToKorean)
        store.invokeCopiedText("empty result")
        for _ in 0..<100 {
            if store.status == .error(.emptyResult) { return }
            try? await Task.sleep(for: .milliseconds(2))
        }

        fail("a provider returning only whitespace should report emptyResult")
    }

    private static func codeFencesAreNormalizedAtCompletion() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("Install it:\n\nnpm i")
        let first = await probe.nextRequest()
        store.receivePartialText("설치합니다:\n\n```bash\nnpm i", for: first)
        try? await Task.sleep(for: .milliseconds(80))
        require(store.streamingText == "설치합니다:\n\n```bash\nnpm i", "partials stay raw")
        require(TranslationMarkup(store.displayedText ?? "", streaming: true).containsCode, "the draft parses as code")
        await probe.complete(first.id, with: "설치합니다:\n\n```bash\nnpm i\n```\n```")
        await settle()
        require(store.resultText == "설치합니다:\n\n```bash\nnpm i\n```", "a stray trailing fence is removed")

        store.invokeCopiedText("Explain")
        let second = await probe.nextRequest()
        await probe.complete(second.id, with: "설명\n```js\nx")
        await settle()
        require(store.resultText == "설명\n```js\nx\n```", "an unclosed block is closed")

        store.invokeCopiedText("Install it:\n\nnpm i")
        require(store.lastResultWasCached && store.resultText == "설치합니다:\n\n```bash\nnpm i\n```", "cache returns normalized text")

        for empty in ["```", "```\n```"] {
            store.invokeCopiedText("Empty \(empty.count)")
            let request = await probe.nextRequest()
            await probe.complete(request.id, with: empty)
            await settle()
            require(store.status == .error(.emptyResult), "fences without code are an empty result: \(empty)")
        }

        store.invokeCopiedText("First paragraph.")
        let head = await probe.nextRequest()
        await probe.complete(head.id, with: "첫 문단.\n```text\n코드")
        await settle()
        store.invokeCopiedText("First paragraph.\n\nSecond paragraph.")
        let tail = await probe.nextRequest()
        await probe.complete(tail.id, with: "둘째 문단.")
        await settle()
        let joined = TranslationMarkup(store.resultText ?? "")
        require(store.isIncrementalResult && joined.blocks.last?.kind == .prose, "each segment is closed on its own")
    }

    private static func copiedStructureTravelsWithTheSource() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        let plain = "Use read first. See the docs."
        func markup(_ url: String) -> SourceMarkup {
            SourceMarkup(text: "Use `read` first. See <a1>the docs</a1>.",
                         links: [SourceLink(url: URL(string: url)!, text: "the docs")], code: ["read"])
        }
        let copied = CapturedSource(plain: plain, markup: markup("https://a.dev/docs"))

        store.invokeCopiedSource(copied)
        let first = await probe.nextRequest()
        require(first.input == plain && first.markup == copied.markup && first.modelInput == copied.markup?.text,
                "the model gets the markup while the identity stays plain")
        require(store.sourceText == plain, "the source pane shows plain text")
        await probe.complete(first.id, with: "먼저 `read`를 쓰세요. <a1>문서</a1>를 보세요.")
        await settle()
        require(store.result?.markup == copied.markup, "the result keeps the structure")
        require(store.display.inline == InlineOptions(code: .only(["read"]), links: copied.markup!.links), "display options")

        store.invokeCopiedSource(copied)
        await settle()
        require(await probe.requestCount() == 1 && store.status == .success, "the same copy is a duplicate")

        // Same words, new URL: the cached translation is reused with the new link table.
        let moved = CapturedSource(plain: plain, markup: markup("https://b.dev/docs"))
        store.invokeCopiedSource(moved)
        await settle()
        require(store.lastResultWasCached && store.result?.markup == moved.markup, "links resolve to the latest copy")

        // The same words copied without structure replace the old links.
        store.invokeCopiedSource(CapturedSource(plain: plain))
        let bare = await probe.nextRequest()
        require(bare.markup == nil && bare.modelInput == plain, "a plain copy does not reuse old links")
        await probe.complete(bare.id, with: "먼저 read를 쓰세요. 문서를 보세요.")
        await settle()
        require(store.result?.markup == nil && store.display.inline == InlineOptions(), "plain result")

        // Retry and resume reattach the structure of the last copy.
        store.invokeCopiedSource(moved)
        await settle()
        require(store.lastResultWasCached && store.result?.markup == moved.markup, "structured copy hits its own cache entry")
        store.invokeCopiedText(plain)
        await settle()
        let count = await probe.requestCount()
        require(store.result?.markup == moved.markup && count == 2, "re-invoking keeps the captured structure")

        // Changing the captured prefix translates plain text; undoing it brings the links back.
        let editedPlain = plain.replacingOccurrences(of: "Use", with: "Prefer")
        store.editSource(editedPlain, isComposing: false)
        let edited = await probe.nextRequest()
        require(edited.markup == nil && edited.input == editedPlain, "edited captured prefix is plain")
        await probe.complete(edited.id, with: "수정된 번역")
        await settle()
        store.editSource(plain, isComposing: false)
        await settle()
        try? await Task.sleep(for: .milliseconds(5))
        require(store.result?.markup == moved.markup && store.lastResultWasCached, "undo restores the structured translation")

        // A typed paragraph after the copy is a plain tail; the links above it stay.
        store.editSource(plain + "\n\nMore text.", isComposing: false)
        let tail = await probe.nextRequest()
        require(tail.input == "More text." && tail.markup == nil, "typed tail is translated alone, without structure")
        await probe.complete(tail.id, with: "더 많은 글.")
        await settle()
        require(store.isIncrementalResult && store.result?.markup == moved.markup && store.display.inline.links == moved.markup!.links,
                "the document keeps its links")

        // A structured copy over a plain document is translated whole, not as a tail.
        store.editSource("Intro line.", isComposing: false)
        let intro = await probe.nextRequest()
        await probe.complete(intro.id, with: "소개.")
        await settle()
        let grown = CapturedSource(plain: "Intro line.\n\nRead the guide.", markup: SourceMarkup(
            text: "Intro line.\n\nRead <a1>the guide</a1>.", links: [SourceLink(url: URL(string: "https://g.dev")!, text: "the guide")], code: []))
        store.invokeCopiedSource(grown)
        let whole = await probe.nextRequest()
        require(whole.input == grown.plain && whole.markup == grown.markup, "structure forces a whole-document request")
        await probe.complete(whole.id, with: "소개.\n\n<a1>안내서</a1>를 읽으세요.")
        await settle()
        require(store.display.inline.code == .off && store.display.inline.links.count == 1, "links without code chips")

        // An explicit boundary after a structured copy with code: B alone, and A keeps its links and chips.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            let plainA = "Set x = 1 | y, then read the docs."
            let markupA = SourceMarkup(text: "Set `x = 1 | y`, then read <a1>the docs</a1>.",
                                       links: [SourceLink(url: URL(string: "https://a.dev/docs")!, text: "the docs")], code: ["x = 1 | y"])
            store.invokeCopiedSource(CapturedSource(plain: plainA, markup: markupA))
            let first = await probe.nextRequest()
            await probe.complete(first.id, with: "`x = 1 | y`로 설정하고 <a1>문서</a1>를 읽으세요.")
            await settle()
            for key in ["\n", "\n", "-", "-", "-", "\n", "\n"] {
                store.editSource(store.sourceText + key, isComposing: false)
                await settle()
            }
            let typed = await probe.requestCount()
            require(typed == 1 && store.canCopy, "typing the boundary after a structured copy needs no request")
            store.editSource(store.sourceText + "Bring the report.", isComposing: false)
            let tail = await probe.nextRequest()
            require(tail.input == "Bring the report." && tail.markup == nil, "the block after the boundary goes alone, without structure")
            await probe.complete(tail.id, with: "보고서를 가져오세요.")
            await settle()
            require(store.result?.markup == markupA && store.display.inline.links == markupA.links
                        && store.display.inline.code == .only(["x = 1 | y"]), "A keeps its links and chips")
            require(store.resultCopy?.plain.contains("---") == false && store.display.unitBreaks.count == 1, "no `---`, one line")
            // '전체 다시 번역': the first block carries the copy's structure again, then B; A is not repeated.
            store.retranslateWholeDocument()
            let wholeA = await probe.nextRequest()
            require(wholeA.input == plainA && wholeA.markup == markupA, "the first block is the copy with its structure")
            await probe.complete(wholeA.id, with: "`x = 1 | y`로 설정한 뒤 <a1>문서</a1>를 읽으세요.")
            let wholeB = await probe.nextRequest()
            require(wholeB.input == "Bring the report." && wholeB.markup == nil, "then B without structure")
            await probe.complete(wholeB.id, with: "보고서를 가져오세요.")
            await settle()
            let total = await probe.requestCount()
            require(total == 4 && store.canCopy && store.display.inline.links == markupA.links && store.display.unitBreaks.count == 1,
                    "the links survive a whole retranslation")
        }
        // u: a `---` line inside a structured copy goes to the model with it, and is not grey.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            let plain = "Intro.\n\n---\n\nRead the guide."
            let markup = SourceMarkup(text: "Intro.\n\n---\n\nRead <a1>the guide</a1>.",
                                      links: [SourceLink(url: URL(string: "https://g.dev")!, text: "the guide")], code: [])
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup))
            let whole = await probe.nextRequest()
            require(whole.input == plain && whole.markup == markup && store.sourceBoundaryLines.isEmpty, "a structured copy is sent whole")
            await probe.complete(whole.id, with: "소개.\n\n---\n\n<a1>안내서</a1>를 읽으세요.")
            await settle()
            require(store.canCopy && store.sourceBoundaryLines.isEmpty, "and stays one unit")
            // A line typed after it is a boundary; the copy's own line stays ordinary (§1).
            let typedLine = NSRange(location: (plain + "\n\n").utf16.count, length: 3)
            store.editSource(plain + "\n\n---\n\nBring.", isComposing: false)
            let tail = await probe.nextRequest()
            require(tail.input == "Bring." && store.sourceBoundaryLines == [typedLine], "only the typed line is grey once the copy completed")
            await probe.complete(tail.id, with: "가져오세요.")
            await settle()
            require(store.canCopy && store.sourceBoundaryLines == [typedLine], "and after the block below completes")
            // The same after the structured document comes back from the cache.
            store.editSource("Something else.", isComposing: false)
            await probe.complete((await probe.nextRequest()).id, with: "다른 것.")
            await settle()
            store.invokeCopiedText(plain)
            await settle()
            let restored = await probe.requestCount()
            require(store.canCopy && restored == 3, "the structured copy is restored from the cache")
            store.editSource(plain + "\n\n---\n\nBring.", isComposing: false)
            await settle()
            require(store.sourceBoundaryLines == [typedLine], "a restored structured unit keeps its line ordinary")
        }
        // u, pending: the structured first request is still running when a boundary and a block are typed.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            let plain = "Intro.\n\n---\n\nRead the guide."
            let markup = SourceMarkup(text: "Intro.\n\n---\n\nRead <a1>the guide</a1>.",
                                      links: [SourceLink(url: URL(string: "https://g.dev")!, text: "the guide")], code: [])
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup))
            let whole = await probe.nextRequest()
            store.editSource(plain + "\n\n---\n\nBring.", isComposing: false)
            await settle()
            let cancelled = await probe.wasCancelled(whole.id)
            require(!cancelled && store.sourceBoundaryLines == [NSRange(location: (plain + "\n\n").utf16.count, length: 3)],
                    "while the structured copy is pending, only the typed line is grey")
        }
        // A structured copy's document loses its first unit: the boundary left at the top is grey (d).
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            let plainA = "Run `make` with x = 1 | y first."
            store.invokeCopiedSource(CapturedSource(plain: plainA, markup: SourceMarkup(text: "Run `make` with x = 1 | y first.",
                                                                                       links: [], code: ["make"])))
            await probe.complete((await probe.nextRequest()).id, with: "먼저 `make`를 x = 1 | y로 실행하세요.")
            await settle()
            store.editSource(plainA + "\n\n---\n\n", isComposing: false)
            store.editSource(plainA + "\n\n---\n\nBring it.", isComposing: false)
            await probe.complete((await probe.nextRequest()).id, with: "가져오세요.")
            await settle()
            require(store.sourceBoundaryLines == [NSRange(location: (plainA + "\n\n").utf16.count, length: 3)], "the line below A is grey")
            store.editSource("---\n\nBring it.", isComposing: false)
            await settle()
            let count = await probe.requestCount()
            require(store.resultText == "가져오세요." && count == 2, "the upper block is removed without a request")
            require(store.sourceBoundaryLines == [NSRange(location: 0, length: 3)], "the line left at the top is grey")
        }
    }

    private static func partialSourcesAndInsertionText() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        // A source that ends inside a fence is the user's partial selection: the result is kept as written.
        store.invokeCopiedText("Run this first:\n```bash\nnpm install")
        let partial = await probe.nextRequest()
        await probe.complete(partial.id, with: "먼저 실행하세요:\n```bash\nnpm install")
        await settle()
        require(store.resultText == "먼저 실행하세요:\n```bash\nnpm install", "a source ending inside a fence keeps the result")
        require(store.resultInsertionText == store.resultText, "the source's own fences are inserted")
        require(store.resultFenceStyle == .fenced, "a fenced source keeps fences in view copies")
        // Fences the model added to an unfenced source are left out of copy and insert.
        store.invokeCopiedText("Explain\n\nnpm i")
        let added = await probe.nextRequest()
        await probe.complete(added.id, with: "설명\n\n```bash\nnpm i\n```")
        await settle()
        require(store.resultInsertionText == "설명\n\nnpm i", "model-added fences are not inserted")
        require(store.resultCopy?.markdown == "설명\n\n```bash\nnpm i\n```" && store.resultCopy?.plain == "설명\n\nnpm i",
                "the copy button writes the stored markdown and the insert text")
        require(store.resultFenceStyle == .none, "an unfenced source drops added fences in view copies too")
        // A result that shows nothing is an empty result, even when its fences are kept as written.
        store.invokeCopiedText("Example:\n```\n```")
        let empty = await probe.nextRequest()
        await probe.complete(empty.id, with: "```js\n```")
        await settle()
        require(store.status == .error(.emptyResult), "a result that shows nothing is empty")
    }

    private static func singleWordChatCommandsSurviveCompletionAndInsertion() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        for command in ["pwd", "ls", "deepk-check"] {
            let source = "Run this command:\n```\(command)\n```"
            let result = "이 명령을 실행하세요:\n```\(command)\n```"
            store.invokeCopiedText(source)
            let request = await probe.nextRequest()
            await probe.complete(request.id, with: result)
            await settle()
            require(store.status == .success && store.canCopy, "a chat-style command completes successfully: \(command)")
            require(store.resultText == result, "normalization keeps the opener's single-word command: \(command)")
            require(store.resultFenceStyle == .untagged, "a command on the source's opener is not a language tag: \(command)")
            require(store.resultInsertionText == result && store.resultCopy?.plain == result,
                    "fenced-source insertion and plain copy keep the command: \(command)")

            store.invokeCopiedText("Run \(command)")
            let unfenced = await probe.nextRequest()
            await probe.complete(unfenced.id, with: "```\(command)\n```")
            await settle()
            require(store.status == .success && store.resultText == "```\(command)\n```",
                    "a command alone is a nonempty translation result: \(command)")
            require(store.resultFenceStyle == .none && store.resultInsertionText == command,
                    "an unfenced source removes only delimiters and keeps its command: \(command)")
            require(store.resultCopy?.markdown == "```\(command)\n```" && store.resultCopy?.plain == command,
                    "the copy button has both the stored command and its plain form: \(command)")
        }

        store.invokeCopiedText("Show the directory and files")
        let inlineCloser = await probe.nextRequest()
        await probe.complete(inlineCloser.id, with: "명령어:\n```pwd\nls```\n완료")
        await settle()
        require(store.resultText == "명령어:\n```pwd\nls```\n완료", "an inline closing fence keeps both command lines")
        require(store.resultInsertionText == "명령어:\npwd\nls\n완료", "insertion removes an inline closing delimiter without losing commands")
    }

    private static func unknownTagsAreNeverInserted() async {
        let probe = TranslationProbe()
        let store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText("Create a project:\n\n$ cargo new hello")
        let unfenced = await probe.nextRequest()
        await probe.complete(unfenced.id, with: "프로젝트를 만듭니다:\n```console\n$ cargo new hello\n```")
        await settle()
        require(store.status == .success && store.resultFenceStyle == .none, "an unfenced source")
        require(store.resultInsertionText == "프로젝트를 만듭니다:\n$ cargo new hello" && store.resultCopy?.plain == store.resultInsertionText,
                "a model-added unknown tag is dropped with its fence, not inserted")

        store.invokeCopiedText("Create a project:\n```console\n$ cargo new hello\n```\nDone.")
        let fenced = await probe.nextRequest()
        await probe.complete(fenced.id, with: "프로젝트를 만듭니다:\n```console\n$ cargo new hello\n```\n완료.")
        await settle()
        require(store.resultFenceStyle == .fenced && store.resultInsertionText == "프로젝트를 만듭니다:\n```console\n$ cargo new hello\n```\n완료.",
                "a source fenced with an unknown tag keeps it")

        store.invokeCopiedText("This is the translated result.")
        let stray = await probe.nextRequest()
        await probe.complete(stray.id, with: "번역 결과입니다.\n```console")
        await settle()
        require(store.resultText == "번역 결과입니다." && store.resultInsertionText == "번역 결과입니다.", "a stray unknown-name fence is cut")
    }

    /// Independent review of PR #53.
    private static func structureReview() async {
        let plain = "Use read first. See the docs."
        func markup(_ url: String, text: String = "Use `read` first. See <a1>the docs</a1>.", words: String = "the docs") -> SourceMarkup {
            SourceMarkup(text: text, links: [SourceLink(url: URL(string: url)!, text: words)], code: text.contains("`read`") ? ["read"] : [])
        }
        let answer = "먼저 `read`를 쓰세요. <a1>문서</a1>를 보세요."
        // A plain re-copy of the same words during the structured request replaces it.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup("https://a.dev/docs")))
            let first = await probe.nextRequest()
            store.invokeCopiedSource(CapturedSource(plain: plain))
            let second = await probe.nextRequest()
            require(second.markup == nil, "a plain re-copy is translated without the old links")
            await probe.complete(first.id, with: answer)
            await probe.complete(second.id, with: "먼저 read를 쓰세요. 문서를 보세요.")
            await settle()
            require(store.result?.markup == nil, "the old links do not come back")
        }
        // A re-copy with new URLs during the request keeps the request and uses the new link table.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup("https://a.dev/docs")))
            let first = await probe.nextRequest()
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup("https://b.dev/docs")))
            await probe.complete(first.id, with: answer)
            await settle()
            let count = await probe.requestCount()
            require(count == 1 && store.result?.markup?.links.first?.url.absoluteString == "https://b.dev/docs", "links follow the latest copy")
        }
        // Retrying an edited source keeps the copy, so undoing the edit brings the links back.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup("https://a.dev/docs")))
            let first = await probe.nextRequest()
            await probe.complete(first.id, with: answer)
            await settle()
            store.editSource(plain.replacingOccurrences(of: "Use", with: "Prefer"), isComposing: false)
            let edited = await probe.nextRequest()
            await probe.fail(edited.id, with: TranslationStoreError.timedOut)
            await settle()
            store.retry()
            let retried = await probe.nextRequest()
            await probe.complete(retried.id, with: "수정된 번역")
            await settle()
            store.editSource(plain, isComposing: false)
            await settle()
            try? await Task.sleep(for: .milliseconds(5))
            require(store.result?.markup != nil && store.lastResultWasCached, "undo after a retry restores the links")
        }
        // The same words with a different structure are a different cache entry.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: markup("https://a.dev/docs")))
            let first = await probe.nextRequest()
            await probe.complete(first.id, with: answer)
            await settle()
            let other = markup("https://git.dev", text: "Use <a1>read</a1> first. See the docs.", words: "read")
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: other))
            let second = await probe.nextRequest()
            require(second.markup == other && !store.lastResultWasCached, "another structure is not answered from the cache")
            await probe.complete(second.id, with: "먼저 <a1>read</a1>를 쓰세요.")
            await settle()
        }
        // A kept translation is read as its own source did while a new one is pending.
        do {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.invokeCopiedText("Run `make` now, then run the test suite again later today please.")
            let first = await probe.nextRequest()
            await probe.complete(first.id, with: "지금 `make`를 실행하고, 오늘 나중에 테스트를 다시 실행하세요.")
            await settle()
            store.editSource("Run make now, then run the test suite again later today please.", isComposing: false)
            require(store.display.isStale && store.display.inline.code == .any, "the kept translation keeps its chips")
            _ = await probe.nextRequest()
        }
    }

    /// App fences need no instructions: a copy with only code blocks asks for no inline markup, so its prompt is the
    /// one a plain copy gets. Links or chips still ask for it.
    private static func appFencesKeepThePrompt() async {
        let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        let fenced = SourceMarkup(text: "Install it:\n```sh\nnpm install foo\n```", links: [], code: [],
                                  blocks: [SourceCodeBlock(language: "sh", code: "npm install foo")])
        store.invokeCopiedSource(CapturedSource(plain: "Install it:\nnpm install foo", markup: fenced))
        let request = await probe.nextRequest()
        require(request.modelInput == fenced.text && !request.usesInlineMarkup, "app fences alone use the plain prompt")
        await probe.complete(request.id, with: "설치합니다:\n```sh\nnpm install foo\n```")
        await settle()
        let linked = SourceMarkup(text: fenced.text + "\nSee <a1>the docs</a1>.", links: [SourceLink(url: URL(string: "https://a.dev/docs")!, text: "the docs")],
                                  code: [], blocks: fenced.blocks)
        let chips = SourceMarkup(text: "Use `read`.", links: [], code: ["read"])
        for (markup, inline) in [(linked, true), (chips, true), (nil, false)] {
            let request = TranslationRequest(inputVersion: 1, input: "x", sourceLanguage: .english, targetLanguage: .korean, markup: markup)
            require(request.usesInlineMarkup == inline, "inline markup follows links and chips: \(String(describing: markup?.text))")
        }
    }

    private static func makeStore(
        probe: TranslationProbe,
        engineReady: Bool,
        debounce: Duration = .zero
    ) -> TranslationStore {
        TranslationStore(
            configuration: .init(
                typingDebounce: debounce,
                requestTimeout: nil
            ),
            engineReady: engineReady,
            translator: { request in
                try await probe.translate(request)
            }
        )
    }

    private static func copiedPrefixSurvivesAppendAndRetranslation() async {
        let plain = "Read the docs before calling cancel()."
        let source = SourceMarkup(text: "Read <a1>the docs</a1> before calling `cancel()`.",
                                  links: [SourceLink(url: URL(string: "https://example.com/docs")!, text: "the docs")],
                                  code: ["cancel()"])
        let answer = "`cancel()`을 호출하기 전에 <a1>문서</a1>를 읽으세요."
        for suffix in ["\n\nBring the report.", "\nBring the report.", " Bring the report.", "\u{0301} Bring the report."] {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.invokeCopiedSource(CapturedSource(plain: plain, markup: source))
            await probe.complete((await probe.nextRequest()).id, with: answer)
            await waitForSuccess(store)
            let combined = plain + suffix
            let expected = SourceMarkup(text: source.text + suffix, links: source.links, code: source.code)
            func requireStructure(_ request: TranslationRequest) {
                require(request.input == combined && request.markup == expected,
                        "unchanged captured prefix keeps its exact markup in the whole request")
            }
            store.editSource(combined, isComposing: false)
            let appended = await probe.nextRequest()
            requireStructure(appended)
            await probe.complete(appended.id, with: answer + "\n\n보고서를 가져오세요.")
            await waitForSuccess(store)
            require(store.result?.markup == expected && store.display.inline.links == source.links
                        && store.display.inline.code == .only(source.code), "appended result retains links and chips")

            store.retranslateWholeDocument()
            let whole = await probe.nextRequest()
            requireStructure(whole)
            await probe.complete(whole.id, with: answer + "\n\n보고서를 가져오세요.")
            await waitForSuccess(store)

            store.setTranslationContext(cacheContext: "another-model", provider: "test", model: "model-b", modelLabel: "B")
            store.retranslateSelection()
            let provider = await probe.nextRequest()
            requireStructure(provider)
            require(provider.provider == "test" && provider.model == "model-b", "retranslation uses the new provider selection")
            await probe.complete(provider.id, with: answer + "\n\n보고서를 가져오세요.")
            await waitForSuccess(store)

            store.setDirection(.koreanToEnglish)
            let direction = await probe.nextRequest()
            requireStructure(direction)
            require(direction.sourceLanguage == .korean && direction.targetLanguage == .english,
                    "direction changes keep the same source metadata")
            await probe.complete(direction.id, with: "Consult <a1>documentation</a1>, then use `cancel()`. Deliver the report.")
            await waitForSuccess(store)

            store.retranslateWholeDocument()
            let failed = await probe.nextRequest()
            await probe.fail(failed.id, with: TranslationStoreError.timedOut)
            for _ in 0..<1_000 {
                if store.status == .error(.timedOut) { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            require(store.status == .error(.timedOut), "whole-document failure is observed before retry")
            store.retry()
            let retry = await probe.nextRequest()
            requireStructure(retry)
            await probe.complete(retry.id, with: "Consult <a1>documentation</a1>, then use `cancel()`. Deliver the report.")
            await waitForSuccess(store)

            store.editSource("A different unrelated source for the cache check.", isComposing: false)
            await probe.complete((await probe.nextRequest()).id, with: "An independently translated result.")
            await waitForSuccess(store)
            let count = await probe.requestCount()
            store.editSource(combined, isComposing: false)
            await waitForSuccess(store)
            require(store.lastResultWasCached && store.result?.markup == expected,
                    "cache restoration uses the same projected markup and original link table")
            require(await probe.requestCount() == count, "restoring an unchanged captured extension needs no request")

            // A new plain copy is an explicit replacement, even when its words match the edited source.
            store.invokeCopiedSource(CapturedSource(plain: combined))
            let bare = await probe.nextRequest()
            require(bare.markup == nil, "plain re-copy clears the old captured links")
            await probe.complete(bare.id, with: "A plain result after replacing the source.")
            await waitForSuccess(store)
        }
    }

    private static func copiedPrefixKeepsItsInternalBoundaries() async {
        let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        let plain = "Intro.\n\n---\n\nRead the docs before calling cancel()."
        let source = SourceMarkup(text: "Intro.\n\n---\n\nRead <a1>the docs</a1> before calling `cancel()`.",
                                  links: [SourceLink(url: URL(string: "https://example.com/docs")!, text: "the docs")],
                                  code: ["cancel()"])
        let answer = "소개.\n\n---\n\n`cancel()`을 호출하기 전에 <a1>문서</a1>를 읽으세요."
        store.invokeCopiedSource(CapturedSource(plain: plain, markup: source))
        let first = await probe.nextRequest()
        require(first.input == plain, "the initial copied internal boundary goes to the model")
        await probe.complete(first.id, with: answer)
        await waitForSuccess(store)

        let suffix = "\n\nExtra context."
        store.editSource(plain + suffix, isComposing: false)
        let appended = await probe.nextRequest()
        require(appended.input == plain + suffix && appended.markup?.text == source.text + suffix,
                "a no-boundary append does not split the original copied internal boundary")
        await probe.complete(appended.id, with: answer + "\n\n추가 문맥.")
        await waitForSuccess(store)

        let tail = "Bring the report."
        let combined = plain + suffix + "\n\n---\n\n" + tail
        let boundary = NSRange(location: (plain + suffix + "\n\n").utf16.count, length: 3)
        store.editSource(combined, isComposing: false)
        let later = await probe.nextRequest()
        require(later.input == tail && later.markup == nil, "only the newly bounded tail is requested")
        await probe.complete(later.id, with: "보고서를 가져오세요.")
        await waitForSuccess(store)
        require(store.sourceBoundaryLines == [boundary] && store.display.unitBreaks.count == 1,
                "only the boundary entered after the copy is rendered as a unit boundary")

        store.retranslateWholeDocument()
        let copied = await probe.nextRequest()
        require(copied.input == plain + suffix && copied.markup?.text == source.text + suffix,
                "whole retranslation preserves copied boundaries while retaining the user's later split")
        await probe.complete(copied.id, with: answer + "\n\n추가 문맥.")
        let newTail = await probe.nextRequest()
        require(newTail.input == tail && newTail.markup == nil, "whole retranslation sends the later tail separately")
        await probe.complete(newTail.id, with: "보고서를 가져오세요.")
        await waitForSuccess(store)
        require(store.sourceBoundaryLines == [boundary] && store.display.inline.links == source.links,
                "source boundaries and links survive the block-by-block replacement")
    }

    private static func copiedPrefixRequiresExactBytes() async {
        let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        let plain = "Read café docs."
        let source = SourceMarkup(text: "Read <a1>café docs</a1>.",
                                  links: [SourceLink(url: URL(string: "https://example.com/docs")!, text: "café docs")], code: [])
        store.invokeCopiedSource(CapturedSource(plain: plain, markup: source))
        await probe.complete((await probe.nextRequest()).id, with: "<a1>카페 문서</a1>를 읽으세요.")
        await waitForSuccess(store)
        let changed = "Read cafe\u{0301} docs. Bring the report."
        store.editSource(changed, isComposing: false)
        let request = await probe.nextRequest()
        require(request.input == changed && request.markup == nil,
                "a canonically equivalent but byte-different prefix is not assigned the captured URLs")
        await probe.complete(request.id, with: "카페 문서를 읽고 보고서를 가져오세요.")
        await waitForSuccess(store)
    }

    private static func waitForSuccess(_ store: TranslationStore) async {
        for _ in 0..<2_000 {
            if store.status == .success { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fail("translation did not reach success: \(store.status)")
    }

    private static func capturedAndAuthoredInlineCodeKeepTheirCopyPolicies() async {
        for automatic in [false, true] {
            for typed in ["reset()", "cancel()"] {
                let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
                if !automatic { store.setDirection(.englishToKorean) }
                let capture = RichSourceImporter.copiedSource(plain: "Run cancel().", html: "<p>Run <code>cancel()</code>.</p>")
                require(capture.markup?.code == ["cancel()"], "the real importer records the page's inline code")
                store.invokeCopiedSource(capture)
                await probe.complete((await probe.nextRequest()).id, with: "`cancel()`을 실행하세요.")
                await waitForSuccess(store)
                let combined = capture.plain + " Then run `" + typed + "`."
                let answer = "`cancel()`을 실행한 다음 `" + typed + "`을 실행하세요."
                // Identical values are ambiguous after model reordering: authored literal syntax wins.
                let expected = (typed == "cancel()" ? "`cancel()`" : "cancel()") + "을 실행한 다음 `" + typed + "`을 실행하세요."
                func checkResult() {
                    let parsed = TranslationMarkup(store.display.text ?? "", inline: store.display.inline)
                    let text = parsed.displayText as NSString
                    let spans = parsed.spans.filter { $0.kind == .code }
                    require(spans.map { text.substring(with: $0.range) } == ["cancel()", typed],
                            "captured and authored inline code are both displayed as chips")
                    let all = NSRange(location: 0, length: text.length)
                    require(store.resultInsertionText == expected && store.resultCopy?.plain == expected
                                && parsed.plainText(in: all, fences: .none) == expected,
                            "insertion, full copy and selection preserve the same authored delimiters")
                    require(parsed.plainText(in: spans[1].range, fences: .none) == "`" + typed + "`",
                            "selecting authored inline code keeps its backticks")
                    let partial = NSRange(location: spans[1].range.location, length: 3)
                    require(parsed.plainText(in: partial, fences: .none) == "`" + String(typed.prefix(3)) + "`",
                            "partial selection uses the full span's authored origin")
                    require(parsed.html.components(separatedBy: "<code>").count == 3, "rich copy includes both code elements")
                }
                store.editSource(combined, isComposing: false)
                let appended = await probe.nextRequest()
                require(appended.modelInput == "Run `cancel()`. Then run `" + typed + "`.",
                        "the request carries both copied and authored syntax")
                await probe.complete(appended.id, with: answer)
                await waitForSuccess(store)
                checkResult()
                store.retranslateWholeDocument()
                await probe.complete((await probe.nextRequest()).id, with: answer)
                await waitForSuccess(store)
                checkResult()
                store.setTranslationContext(cacheContext: "literal-origin", provider: "test", model: "origin", modelLabel: "Origin")
                store.retranslateSelection()
                await probe.complete((await probe.nextRequest()).id, with: answer)
                await waitForSuccess(store)
                checkResult()
                let count = await probe.requestCount()
                store.editSource("", isComposing: false)
                store.invokeCopiedText(combined)
                await waitForSuccess(store)
                let cachedCount = await probe.requestCount()
                require(store.lastResultWasCached && cachedCount == count,
                        "cache restoration rebuilds authored provenance without another request")
                checkResult()
                store.editSource(capture.plain, isComposing: false)
                await probe.complete((await probe.nextRequest()).id, with: "`cancel()`을 실행하세요.")
                await waitForSuccess(store)
                require(store.resultInsertionText == "cancel()을 실행하세요.", "undoing the literal suffix restores the captured-only copy policy")
            }
        }
    }

    private static func copiedBlockSameLineExtensionIsPlain() async {
        for suffix in [" + 1", "\n\nThen continue.", " \t\n\n다음 문단입니다.", " \t\r\n\r\n다음 문단입니다."] {
            let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
            store.setDirection(.englishToKorean)
            store.retriesSourceEcho = false
            let capture = RichSourceImporter.copiedSource(plain: "print(1)", html: "<pre><code class=\"language-python\">print(1)</code></pre>")
            require(capture.markup?.blocks.count == 1, "the real importer fences the copied code block")
            store.invokeCopiedSource(capture)
            let first = await probe.nextRequest()
            await probe.complete(first.id, with: first.modelInput)
            await waitForSuccess(store)
            let combined = capture.plain + suffix
            let safe = suffix.unicodeScalars.contains("\n")
            func checkRequest(_ request: TranslationRequest) {
                require((request.markup != nil) == safe,
                        "same-line code extension is plain; a later paragraph keeps the captured block: \(suffix.debugDescription)")
                require(request.modelInput == (safe ? capture.markup!.text + suffix : combined),
                        "a raw suffix cannot turn the app's closing fence into model-input code")
            }
            store.editSource(combined, isComposing: false)
            let extended = await probe.nextRequest()
            checkRequest(extended)
            await probe.complete(extended.id, with: extended.modelInput)
            await waitForSuccess(store)
            let exported = store.resultInsertionText ?? ""
            require((safe ? exported.contains("print(1)") && exported.contains(suffix.contains("다음") ? "다음 문단입니다." : "Then continue.")
                        && !exported.contains("```") : exported == combined) && store.resultCopy?.plain == exported,
                    "provider-independent echo control exposes no synthetic closing-fence text")
            store.retranslateWholeDocument()
            let failed = await probe.nextRequest()
            checkRequest(failed)
            await probe.fail(failed.id, with: TranslationStoreError.timedOut)
            for _ in 0..<1_000 {
                if store.status == .error(.timedOut) { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            require(store.status == .error(.timedOut), "observe the failed request before retrying")
            store.retry()
            let retry = await probe.nextRequest()
            checkRequest(retry)
            await probe.complete(retry.id, with: retry.modelInput)
            await waitForSuccess(store)
            let count = await probe.requestCount()
            store.editSource("", isComposing: false)
            store.invokeCopiedText(combined)
            await waitForSuccess(store)
            let cachedCount = await probe.requestCount()
            require(store.lastResultWasCached && cachedCount == count && store.resultInsertionText == exported,
                    "cache restoration cannot reintroduce the contaminated closing fence")
        }
        let probe = TranslationProbe(), store = makeStore(probe: probe, engineReady: true)
        store.setDirection(.englishToKorean)
        store.retriesSourceEcho = false
        let capture = RichSourceImporter.copiedSource(plain: "print(1)", html: "<pre><code class=\"language-python\">print(1)</code></pre>")
        store.invokeCopiedSource(capture)
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: first.modelInput)
        await waitForSuccess(store)
        store.editSource(capture.plain + " \t", isComposing: false)
        await waitForSuccess(store)
        require(await probe.requestCount() == 1, "a whitespace-only extension remains completed coverage")
        store.retranslateWholeDocument()
        let whole = await probe.nextRequest()
        require(whole.markup?.blocks == capture.markup?.blocks && whole.modelInput == capture.markup?.text,
                "whole retranslation after whitespace-only extension retains the guarded block")
        await probe.complete(whole.id, with: whole.modelInput)
        await waitForSuccess(store)
    }

    private static func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("TranslationStoreTests failed: \(message)")
    }
}

#if TRANSLATION_STORE_STANDALONE
@main
private struct TranslationStoreStandaloneRunner {
    static func main() async {
        await TranslationStoreTests.runAll()
        print("TranslationStoreTests passed")
    }
}
#endif
