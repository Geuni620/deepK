import Foundation

@MainActor
enum IncrementalTranslationTests {
    static func runAll() async {
        await streamingSnapshots()
        plannerBoundaries()
        copiedPrefixPlanner()
        report("explicit boundary planner")
        explicitBoundaryPlanner()
        report("explicit boundary document")
        explicitBoundaryDocument()
        report("append and queue")
        await appendAndQueue()
        report("remove completed leading units")
        await removeLeadingUnits()
        report("edit and retry")
        await editAndRetry()
        report("cache alignment")
        await cacheAlignment()
        report("composition and limits")
        await compositionAndLimits()
        report("selection and replacement")
        await selectionAndReplacement()
        report("reconnect")
        await reconnect()
        report("whole retranslation")
        await wholeRetranslation()
        report("pinned prefix and direction")
        await pinnedPrefixAndDirection()
        report("byte limits")
        await byteLimits()
        report("expired cache purge")
        await expiredCachePurge()
        report("debounce and language")
        await debounceAndLanguage()
        report("prose with punctuation appends")
        await proseWithPunctuationAppends()
        report("streaming prefix invariant")
        await streamingPrefixInvariant()
        report("trailing coverage")
        await trailingCoverage()
        report("superseded display")
        await supersededDisplay()
        report("coverage edge cases")
        await coverageEdgeCases()
        report("first request continuity")
        await firstRequestContinuity()
        report("review follow-ups")
        await reviewFollowUps()
        report("explicit boundary")
        await explicitBoundary()
        report("explicit boundary races")
        await explicitBoundaryRaces()
        report("explicit boundary language")
        await explicitBoundaryLanguage()
        report("explicit boundary simulation")
        await explicitBoundarySimulation()
        print("IncrementalTranslationTests passed")
    }

    // Explicit `---` boundaries (plans/explicit-boundary-translation.md).
    private static func copiedPrefixPlanner() {
        let copied = "Intro.\n\n---\n\nRun cancel()."
        let extensionText = "\n\nExtra context."
        let source = copied + extensionText + "\n\n---\n\nBring the report."
        let unit = IncrementalTranslationPlanner.firstUnit(in: source, preservingPrefix: copied)
        require(unit.separator.isEmpty && unit.input == copied + extensionText,
                "preserving a copied prefix ignores only its own internal boundaries")
        require(IncrementalTranslationPlanner.firstUnit(in: copied, preservingPrefix: copied).input == copied,
                "the complete captured prefix is atomic")
        let ordinary = "First.\n\n---\n\nSecond."
        require(IncrementalTranslationPlanner.firstUnit(in: ordinary, preservingPrefix: copied)
                    == IncrementalTranslationPlanner.firstUnit(in: ordinary), "a changed prefix uses ordinary boundaries")
        let trailing = copied + "\n"
        require(IncrementalTranslationPlanner.firstUnit(in: trailing + "---\n\nThird.", preservingPrefix: trailing).input == trailing,
                "original trailing bytes stay inside the protected prefix")
    }

    private static let codeA = "Run `make` with x = 1 | y first."
    private static let codeT = "먼저 `make`를 x = 1 | y로 실행하세요."
    private static let bring = "Bring the report."
    private static let bringT = "보고서를 가져오세요."
    private static let close = "Close the door."
    private static let closeT = "문을 닫으세요."
    private static let noCache = TranslationStore.Configuration(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 0)

    /// A store whose first unit `text` completed as `translation`.
    private static func seeded(_ text: String = codeA, _ translation: String = codeT,
                               configuration: TranslationStore.Configuration = .init(typingDebounce: .zero, requestTimeout: nil))
        async -> (TranslationProbe, TranslationStore) {
        let probe = TranslationProbe(), store = make(probe, configuration: configuration)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(text)
        let request = await probe.nextRequest()
        await probe.complete(request.id, with: translation)
        await settle()
        return (probe, store)
    }

    /// Completes the pending request and the ones queued after it, in order.
    private static func completeAll(_ probe: TranslationProbe, _ translations: [String]) async {
        for translation in translations {
            let request = await probe.nextRequest()
            await probe.complete(request.id, with: translation)
        }
        await settle()
    }

    private static func type(_ keys: [String], into store: TranslationStore) async {
        for key in keys {
            store.editSource(store.sourceText + key, isComposing: false)
            await settle()
        }
    }

    /// ⌘↩, as the source editor applies it.
    private static func appendBoundary(_ store: TranslationStore) {
        guard let insertion = IncrementalTranslationPlanner.boundaryInsertion(after: store.sourceText), !insertion.isEmpty else { return }
        store.editSource(store.sourceText + insertion, isComposing: false)
    }

    private static func explicitBoundary() async {
        for newline in ["\n", "\r\n"] {
            let (probe, store) = await seeded()
            let id = store.displaySegments[0].id, identity = store.display.identity
            for key in [newline, newline, "-", "-", "-", newline, newline] {
                await type([key], into: store)
                let count = await probe.requestCount()
                require(count == 1, "typing a boundary makes no request: \(store.sourceText.debugDescription)")
                require(!store.display.isStale && store.display.text == codeT && store.canCopy && store.display.unitBreaks.isEmpty,
                        "T(A) stays readable and usable: \(store.sourceText.debugDescription)")
            }
            let line = NSRange(location: codeA.utf16.count + 2 * newline.utf16.count, length: 3)
            require(store.sourceBoundaryLines == [line], "the typed line is a boundary")
            store.invokeCopiedText(store.sourceText + bring)
            let tail = await probe.nextRequest()
            require(tail.input == bring && tail.markup == nil, "only B is requested")
            require(store.display.text == codeT && store.display.unitBreaks.isEmpty, "no line before B has text")
            store.receivePartialText("보고서", for: tail)
            try? await Task.sleep(for: .milliseconds(80))
            require(store.display.text == codeT + "\n\n보고서" && store.display.unitBreaks == [codeT.utf16.count],
                    "the line appears with B's text")
            await probe.complete(tail.id, with: bringT)
            await settle()
            require(store.resultText == codeT + "\n\n" + bringT && store.display.unitBreaks == [codeT.utf16.count], "T(A), a line and T(B)")
            require(store.displaySegments[0].id == id && store.display.identity == identity, "A is kept on the same surface")
            require(store.resultCopy?.plain == codeT + "\n\n" + bringT && store.resultInsertionText?.contains("---") == false,
                    "copy and insert have no `---`")
            require(store.sourceBoundaryLines == [line], "the line stays grey")
            let count = await probe.requestCount()
            require(count == 2, "two requests in total")
        }

        // A web copy ending in NBSP.
        let (nbspProbe, nbsp) = await seeded(codeA + "\u{A0}", codeT)
        nbsp.invokeCopiedText(codeA + "\u{A0}\n\n---\n\n" + bring)
        require((await nbspProbe.nextRequest()).input == bring, "NBSP before the boundary")

        // P0-1: a held dash that the next key turns into content is translated, without a trap.
        for (content, translation) in [(a, "첫 문단."), (codeA, codeT)] {
            let (probe, store) = await seeded(content, translation)
            await type(["\n\n-", "\n"], into: store)
            let request = await probe.nextRequest()
            require(request.input == (content == a ? "-\n" : content + "\n\n-\n"), "the dash is translated: \(content)")
            await probe.complete(request.id, with: "대시")
            await settle()
            require(store.canCopy && store.result?.input == content + "\n\n-\n", "the whole source is covered: \(content)")
        }
        let (fillProbe, fill) = await seeded()
        await type(["\n\n--"], into: fill)
        appendBoundary(fill)
        await settle()
        let fillCount = await fillProbe.requestCount()
        require(fill.sourceText == codeA + "\n\n---\n\n" && fill.canCopy && fillCount == 1, "⌘↩ completes two dashes without a request")
        let (dashProbe, dashes) = await seeded(a, "첫 문단.")
        await type(["\n\n--", "\n\n" + bring], into: dashes)
        require((await dashProbe.nextRequest()).input == "--\n\n" + bring, "two dashes followed by a paragraph are not lost")
        let (keepProbe, keep) = await seeded(a, "첫 문단.")
        keep.invokeCopiedText(a + "\n\n" + bring + "\n\n--")
        let pending = await keepProbe.nextRequest()
        require(pending.input == bring, "dashes at the end are not requested")
        await type(["-"], into: keep)
        let cancelled = await keepProbe.wasCancelled(pending.id)
        require(!cancelled && keep.status == .translating, "completing the line keeps B")
        // I5: the snapshot ends at B, so deleting the line after a pending B keeps it too.
        for edit in [a + "\n\n" + bring + "\n\n", a + "\n\n" + bring] {
            let (probe, store) = await seeded(a, "첫 문단.")
            store.invokeCopiedText(a + "\n\n" + bring + "\n\n---")
            let held = await probe.nextRequest()
            store.editSource(edit, isComposing: false)
            await settle()
            let heldCancelled = await probe.wasCancelled(held.id), count = await probe.requestCount()
            require(held.input == bring && !heldCancelled && store.status == .translating && count == 2,
                    "deleting the line after a pending B keeps it: \(edit.debugDescription)")
            await probe.complete(held.id, with: bringT)
            await settle()
            require(store.resultText == "첫 문단.\n\n" + bringT && store.canCopy, "B completes: \(edit.debugDescription)")
        }
        await keepProbe.complete(pending.id, with: bringT)
        await settle()
        require(keep.canCopy && keep.resultText == "첫 문단.\n\n" + bringT && keep.display.unitBreaks.isEmpty
                    && keep.sourceBoundaryLines == [NSRange(location: (a + "\n\n" + bring + "\n\n").utf16.count, length: 3)],
                "a line after the last unit draws nothing in the result")
    }

    private static func explicitBoundaryRaces() async {
        // c2: a blank-line tail is pending when ⌘↩ and a code block follow it.
        let (probe, store) = await seeded(a, "첫 문단.")
        store.invokeCopiedText(ab)
        let second = await probe.nextRequest()
        appendBoundary(store)
        store.editSource(store.sourceText + codeA, isComposing: false)
        await settle()
        let secondCancelled = await probe.wasCancelled(second.id)
        require(!secondCancelled && store.display.text == "첫 문단." && !store.display.isStale, "c2: B keeps its request")
        await probe.complete(second.id, with: "둘째.")
        let code = await probe.nextRequest()
        require(code.input == codeA, "c2: the code block follows B")
        await probe.complete(code.id, with: codeT)
        await settle()
        let count = await probe.requestCount()
        require(store.resultText == "첫 문단.\n\n둘째.\n\n" + codeT && store.display.unitBreaks == ["첫 문단.\n\n둘째.".utf16.count]
                    && count == 3, "c2: three requests and one line")

        // c3: [A---B] completed, a blank-line tail C pending, then ⌘↩ and code D.
        let (raceProbe, race) = await seeded(a, "첫 문단.")
        race.invokeCopiedText(a + "\n\n---\n\nSecond paragraph.")
        await completeAll(raceProbe, ["둘째."])
        race.invokeCopiedText(race.sourceText + "\n\nThird paragraph.")
        let third = await raceProbe.nextRequest()
        func requireAligned(_ step: String) {
            let covered = race.displaySegments.map { $0.separator + $0.input + $0.trailing }.joined()
            require(race.sourceText.utf8.starts(with: covered.utf8) && race.testCacheIsConsistent,
                    "c3 \(step): the document is a prefix of the source")
        }
        requireAligned("pending")
        appendBoundary(race)
        await settle()
        requireAligned("⌘↩")
        race.editSource(race.sourceText + codeA, isComposing: false)
        await settle()
        requireAligned("code")
        let thirdCancelled = await raceProbe.wasCancelled(third.id)
        require(!thirdCancelled && race.status == .translating && race.display.text == "첫 문단.\n\n둘째.", "c3: C keeps its request")
        await raceProbe.complete(third.id, with: "셋째.")
        let fourth = await raceProbe.nextRequest()
        requireAligned("C completed")
        require(fourth.input == codeA && race.displaySegments.count == 3, "c3: D follows C")
        await raceProbe.complete(fourth.id, with: codeT)
        await settle()
        requireAligned("D completed")
        require(race.resultText == "첫 문단.\n\n둘째.\n\n셋째.\n\n" + codeT
                    && race.display.unitBreaks == ["첫 문단.".utf16.count, "첫 문단.\n\n둘째.\n\n셋째.".utf16.count], "c3: result")

        // t: an empty source, ⌘V A, then ⌘↩ and ⌘V B within the debounce.
        let debounced = TranslationProbe()
        let typed = make(debounced, configuration: .init(typingDebounce: .milliseconds(40), requestTimeout: nil))
        typed.setDirection(.englishToKorean)
        typed.editSource(a, isComposing: false)
        appendBoundary(typed)
        typed.editSource(typed.sourceText + bring, isComposing: false)
        let firstUnit = await debounced.nextRequest()
        require(firstUnit.input == a && firstUnit.markup == nil, "t: the first request is A")
        await debounced.complete(firstUnit.id, with: "첫 문단.")
        let next = await debounced.nextRequest()
        require(next.input == bring, "t: then B")
        await debounced.complete(next.id, with: bringT)
        await settle()
        require(typed.resultText == "첫 문단.\n\n" + bringT && typed.display.unitBreaks == ["첫 문단.".utf16.count], "t: result")

        // b2: ⌘↩ ⌘V B ⌘↩ ⌘V C while A is pending.
        let queueProbe = TranslationProbe(), queue = make(queueProbe)
        queue.setDirection(.englishToKorean)
        queue.invokeCopiedText(codeA)
        let pendingA = await queueProbe.nextRequest()
        for paste in [bring, close] {
            appendBoundary(queue)
            queue.editSource(queue.sourceText + paste, isComposing: false)
        }
        await settle()
        let queuedCancelled = await queueProbe.wasCancelled(pendingA.id), queuedCount = await queueProbe.requestCount()
        require(!queuedCancelled && queuedCount == 1, "b2: A keeps its request")
        await queueProbe.complete(pendingA.id, with: codeT)
        let pendingB = await queueProbe.nextRequest()
        await queueProbe.complete(pendingB.id, with: bringT)
        let pendingC = await queueProbe.nextRequest()
        await queueProbe.complete(pendingC.id, with: closeT)
        await settle()
        let queueTotal = await queueProbe.requestCount()
        require(pendingB.input == bring && pendingC.input == close && queueTotal == 3, "b2: A, B and C in turn")
        require(queue.resultText == codeT + "\n\n" + bringT + "\n\n" + closeT && queue.display.unitBreaks.count == 2
                    && queue.sourceBoundaryLines.count == 2, "b2: two lines")

        // n: a pasted block with a boundary inside.
        let (pasteProbe, paste) = await seeded(a, "첫 문단.")
        paste.invokeCopiedText(a + "\n\n---\n\n" + bring + "\n\n---\n\n" + close)
        let b1 = await pasteProbe.nextRequest()
        await pasteProbe.complete(b1.id, with: bringT)
        let b2 = await pasteProbe.nextRequest()
        await pasteProbe.complete(b2.id, with: closeT)
        await settle()
        let pasteCount = await pasteProbe.requestCount()
        require(b1.input == bring && b2.input == close && paste.display.unitBreaks.count == 2 && pasteCount == 3, "n: blocks in turn")

        // retainingSuffix rebases a pending explicit tail.
        let (rebaseProbe, rebase) = await seeded(a, "첫 문단.")
        rebase.invokeCopiedText(a + "\n\n---\n\n" + bring)
        await completeAll(rebaseProbe, [bringT])
        let bID = rebase.displaySegments[1].id
        rebase.invokeCopiedText(rebase.sourceText + "\n\n---\n\n" + close)
        let pendingClose = await rebaseProbe.nextRequest()
        rebase.editSource(bring + "\n\n---\n\n" + close, isComposing: false)
        await settle()
        let rebaseCancelled = await rebaseProbe.wasCancelled(pendingClose.id)
        require(!rebaseCancelled && rebase.display.text == bringT && rebase.status == .translating, "the upper block removed while C is pending")
        await rebaseProbe.complete(pendingClose.id, with: closeT)
        await settle()
        require(rebase.resultText == bringT + "\n\n" + closeT && rebase.display.unitBreaks == [bringT.utf16.count]
                    && rebase.displaySegments[0].id == bID, "the rebased C completes below B")

        // P0-2: `replanned` drops B with the tail C pending below it. C was planned against B, so it is cancelled;
        // otherwise undoing the edit within the debounce lets C complete onto [A] without B.
        let undoProbe = TranslationProbe()
        let undo = make(undoProbe, configuration: .init(typingDebounce: .milliseconds(200), requestTimeout: nil))
        undo.setDirection(.englishToKorean)
        undo.invokeCopiedText(a)
        await completeAll(undoProbe, ["첫 문단."])
        undo.invokeCopiedText(a + "\n\n---\n\nSecond paragraph.")
        await completeAll(undoProbe, ["둘째."])
        let withC = undo.sourceText + "\n\nThird paragraph."
        undo.invokeCopiedText(withC)
        let pendingThird = await undoProbe.nextRequest()
        // Code after C is not plain text: B, C and the code become one block below A.
        undo.editSource(withC + "\n\n`x`", isComposing: false)
        undo.editSource(withC, isComposing: false)
        await settle()
        let droppedCancelled = await undoProbe.wasCancelled(pendingThird.id)
        require(pendingThird.input == "Third paragraph." && droppedCancelled, "a tail planned against a dropped unit is cancelled")
        await undoProbe.complete(pendingThird.id, with: "셋째.")
        await settle()
        let undoCovered = undo.displaySegments.map { $0.separator + $0.input + $0.trailing }.joined()
        require(undo.sourceText.utf8.starts(with: undoCovered.utf8) && undo.testCacheIsConsistent && undo.display.text == "첫 문단.",
                "its late answer is ignored")
        let merged = await undoProbe.nextRequest()
        require(merged.input == "Second paragraph.\n\nThird paragraph.", "B and C go again as one block")
        await undoProbe.complete(merged.id, with: "둘째. 셋째.")
        await settle()
        require(undo.resultText == "첫 문단.\n\n둘째. 셋째." && undo.display.unitBreaks == ["첫 문단.".utf16.count], "the result covers the source")
    }

    private static func explicitBoundaryLanguage() async {
        let english = "The meeting starts at three in the afternoon.", englishT = "회의는 오후 세 시에 시작합니다."
        let korean = "오늘 회의 자료를 준비해 주세요.", koreanT = "Please prepare today's meeting materials."
        // Measured on macOS 26: unfenced `kubectl get pods -n prod` is English at 0.585, under the 0.8 threshold.
        let cases = [(english, englishT, "```bash\nkubectl get pods -n prod\n```"), (english, englishT, "x = 1 | y"),
                     (korean, koreanT, "```\nkubectl get pods\n```"), (korean, koreanT, "kubectl get pods -n prod")]
        for (first, translation, block) in cases {
            let probe = TranslationProbe(), store = make(probe)
            store.invokeCopiedText(first)
            let request = await probe.nextRequest()
            await probe.complete(request.id, with: translation)
            await settle()
            store.invokeCopiedText(first + "\n\n---\n\n" + block)
            let tail = await probe.nextRequest()
            require(tail.input == block && tail.sourceLanguage == request.sourceLanguage && !store.display.isStale
                        && store.display.text == translation, "automatic direction requests only the code block: \(block)")
            await probe.complete(tail.id, with: block)
            await settle()
        }

        // h: English A, then Korean prose. Rejected; the fallback still goes block by block without `---`.
        let probe = TranslationProbe(), store = make(probe)
        store.invokeCopiedText(english)
        let first = await probe.nextRequest()
        await probe.complete(first.id, with: englishT)
        await settle()
        store.invokeCopiedText(english + "\n\n---\n\n" + korean)
        let fallback = await probe.nextRequest()
        require(fallback.input == english && store.display.isStale, "h: the other language falls back to A first")
        await probe.complete(fallback.id, with: englishT)
        let block = await probe.nextRequest()
        require(block.input == korean && store.display.isStale && !store.hasPartialResult, "h: then the block, the old text still dimmed")
        await probe.complete(block.id, with: koreanT)
        await settle()
        require(!store.display.isStale && store.display.unitBreaks == [englishT.utf16.count], "h: one swap, with the line")

        // A rejected append ("ok" is not English to the recognizer) never drops the unchanged B above it: T(A) and
        // T(B) stay dimmed together until the fallback replaces them once (h).
        let blockB = "Please bring the quarterly report with you.", blockBT = "분기 보고서를 가져오세요."
        let shown = englishT + "\n\n" + blockBT
        let appends = [("ok", [english, blockB + "\n\nok"]), (korean, [english, blockB + "\n\n" + korean]),
                       ("---\n\n" + korean, [english, korean])]
        for (addition, expected) in appends {
            let probe = TranslationProbe(), store = make(probe)
            store.invokeCopiedText(english + "\n\n---\n\n" + blockB)
            await completeAll(probe, [englishT, blockBT])
            require(store.resultText == shown, "[A---B] in the automatic direction")
            await type(["\n\n", addition], into: store)
            require(store.display.isStale && store.display.text == shown && store.display.unitBreaks == [englishT.utf16.count],
                    "a rejected append dims T(A) and T(B) together: \(addition)")
            for input in expected {
                let request = await probe.nextRequest()
                require(request.input == input && store.display.isStale && store.display.text == shown,
                        "the fallback goes block by block from A, the old text dimmed: \(addition) \(request.input.debugDescription)")
                if input == korean, addition.hasPrefix("---") {
                    // The fallback sent the block without a language check, so whitespace after it keeps it (3.8 step 3).
                    await type([" "], into: store)
                    let cancelled = await probe.wasCancelled(request.id)
                    require(!cancelled && store.status == .translating && store.display.isStale, "whitespace after the pending block keeps it")
                }
                await probe.complete(request.id, with: "T(\(request.input.prefix(4)))")
                await settle()
            }
            let total = await probe.requestCount()
            require(store.canCopy && !store.display.isStale && total == 2 + expected.count, "one swap: \(addition)")
            guard addition.hasPrefix("---") else { continue }
            // Editing the other-language block is rejected again: everything dims, B is not dropped alone.
            let full = store.resultText
            await type([" 내일도요."], into: store)
            require(store.display.isStale && store.display.text == full, "editing the rejected block dims the whole result")
            require((await probe.nextRequest()).input == english, "and falls back from A")
        }

        // While A is pending, a block after a boundary waits for it.
        let pendingProbe = TranslationProbe(), pending = make(pendingProbe)
        pending.invokeCopiedText(english)
        let pendingA = await pendingProbe.nextRequest()
        pending.invokeCopiedText(english + "\n\n---\n\n```bash\nkubectl get pods\n```")
        await settle()
        let pendingCancelled = await pendingProbe.wasCancelled(pendingA.id)
        require(!pendingCancelled, "A keeps its request")
        await pendingProbe.complete(pendingA.id, with: englishT)
        require((await pendingProbe.nextRequest()).input == "```bash\nkubectl get pods\n```", "the block follows A")
    }

    /// Keystrokes, ⌘↩, deletions and provider events from fixed seeds. Every step must leave the store
    /// consistent; a delimiter-only tail that the document does not cover traps in `startRequest` (I1).
    private static func explicitBoundarySimulation() async {
        struct SplitMix: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        typealias P = IncrementalTranslationPlanner
        let keys = ["Alpha.", "x=1", "\n", "\n", " ", "-", "-", "```", "Beta."]
        for seed: UInt64 in [1, 2, 3] {
            var random = SplitMix(state: seed)
            let probe = TranslationProbe(), store = make(probe)
            store.setDirection(.englishToKorean)
            var seen: [TranslationRequest] = [], answered = Set<UUID>(), translations = 0
            func active() -> TranslationRequest? {
                seen.first { !answered.contains($0.id) && store.isActiveRequest($0) }
            }
            func check(_ step: Int, new requests: [TranslationRequest]) {
                let label = "seed \(seed) step \(step) \(store.sourceText.debugDescription)"
                let covered = store.displaySegments.map { $0.separator + $0.input + $0.trailing }.joined()
                require(store.sourceText.utf8.starts(with: covered.utf8), "the document is a prefix of the source: \(label)")
                for request in requests {
                    require(isClean(request.input, in: store.sourceText), "no boundary or delimiter is requested: \(request.input.debugDescription) \(label)")
                }
                let display = store.display
                require(display.unitBreaks == display.unitBreaks.sorted()
                            && display.unitBreaks.allSatisfy { $0 <= (display.text?.utf16.count ?? 0) }, "breaks lie in the text: \(label)")
                if store.status == .success { require(store.canCopy && store.result?.input == store.sourceText, "success covers the source: \(label)") }
            }
            func settled(_ step: Int) async {
                var arrived: [TranslationRequest] = []
                for _ in 0..<40 {
                    await settle()
                    let taken = await probe.takeRequests()
                    arrived += taken
                    seen += taken
                    let stuck = store.status == .waiting || (store.status == .translating && active() == nil)
                    if !stuck { break }
                }
                require(store.status != .waiting && (store.status != .translating || active() != nil),
                        "seed \(seed) step \(step): \(store.status) without a request for \(store.sourceText.debugDescription)")
                check(step, new: arrived)
            }
            for step in 0..<200 {
                switch Int.random(in: 0..<100, using: &random) {
                case 0..<55:
                    store.editSource(store.sourceText + keys.randomElement(using: &random)!, isComposing: false)
                case 55..<65:
                    store.editSource(String(store.sourceText.dropLast()), isComposing: false)
                case 65..<71:
                    appendBoundary(store)
                case 71..<74:
                    var lines = store.sourceText.components(separatedBy: "\n")
                    lines.remove(at: Int.random(in: 0..<lines.count, using: &random))
                    store.editSource(lines.joined(separator: "\n"), isComposing: false)
                case 74..<90:
                    if let request = active() {
                        translations += 1
                        answered.insert(request.id)
                        await probe.complete(request.id, with: "번역 \(translations)")
                    }
                case 90..<94:
                    if let request = active() {
                        answered.insert(request.id)
                        await probe.fail(request.id, with: TranslationStoreError.timedOut)
                    }
                default:
                    // A late response to a request the store already gave up.
                    if let stale = seen.first(where: { !answered.contains($0.id) && !store.isActiveRequest($0) }) {
                        answered.insert(stale.id)
                        await probe.complete(stale.id, with: "늦은 응답")
                    }
                }
                await settled(step)
            }
            // Retry a failure, then answer everything: the whole source ends up translated.
            if case .error = store.status { store.invokeCopiedText(store.sourceText) }
            for _ in 0..<50 {
                await settled(200)
                guard let request = active() else { break }
                translations += 1
                answered.insert(request.id)
                await probe.complete(request.id, with: "번역 \(translations)")
            }
            await settled(201)
            require(P.isBlankSource(store.sourceText) || (store.status == .success && store.canCopy),
                    "seed \(seed): the source is translated in the end: \(store.status) \(store.sourceText.debugDescription)")
        }
    }

    private static func streamingSnapshots() async {
        let probe = TranslationProbe()
        let store = make(probe)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(a)
        let first = await probe.nextRequest()
        store.receivePartialText("첫", for: first)
        store.receivePartialText("첫 문단", for: first)
        try? await Task.sleep(for: .milliseconds(80))
        require(store.displayedText == "첫 문단", "stream displays before completion")
        require(!store.canCopy && !store.canInsert && store.result == nil, "draft cannot be used as complete result")
        store.receivePartialText("첫", for: first)
        try? await Task.sleep(for: .milliseconds(80))
        require(store.displayedText == "첫 문단", "out-of-order snapshot cannot shrink output")
        await probe.complete(first.id, with: "첫 문단.")
        await settle()
        require(store.displayedText == "첫 문단." && store.canCopy && store.streamingText == nil, "completion publishes final text")
        store.invokeCopiedText(ab)
        let tail = await probe.nextRequest()
        store.receivePartialText("둘째", for: tail)
        try? await Task.sleep(for: .milliseconds(80))
        require(store.displayedText == "첫 문단.\n\n둘째" && !store.canCopy, "tail streaming retains completed prefix")
        store.setDirection(.koreanToEnglish)
        store.receivePartialText("둘째 문단 늦은 응답", for: tail)
        try? await Task.sleep(for: .milliseconds(80))
        require(store.streamingText == nil, "cancelled generation cannot publish a draft")
        await probe.complete(tail.id, with: "둘째 문단.")
        await settle()

        let failedProbe = TranslationProbe()
        let failed = make(failedProbe)
        failed.setDirection(.englishToKorean)
        failed.invokeCopiedText(a)
        let request = await failedProbe.nextRequest()
        failed.receivePartialText("미완성", for: request)
        try? await Task.sleep(for: .milliseconds(80))
        await failedProbe.fail(request.id, with: TranslationStoreError.timedOut)
        await settle()
        failed.receivePartialText("미완성 늦은 응답", for: request)
        require(failed.displayedText == nil && !failed.canCopy, "failure clears draft without caching it")
        print("Streaming snapshot tests passed")
    }

    private static let a = "First paragraph."
    private static let ab = "First paragraph.\n\nSecond paragraph."
    private static let abc = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."

    private static func make(_ probe: TranslationProbe, configuration: TranslationStore.Configuration = .init(typingDebounce: .zero, requestTimeout: nil)) -> TranslationStore {
        TranslationStore(configuration: configuration, engineReady: true, translator: { try await probe.translate($0) })
    }

    private static func seed(_ store: TranslationStore, _ probe: TranslationProbe) async {
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(a)
        let request = await probe.nextRequest()
        await probe.complete(request.id, with: "첫 문단.")
        await settle()
    }

    private static func plannerBoundaries() {
        for delimiter in ["\n\n", "\r\n\r\n", "\n\n\n"] {
            let tail = IncrementalTranslationPlanner.tail(after: a, in: a + delimiter + "Bring the report.")
            require(tail?.separator == delimiter && tail?.input == "Bring the report.", "preserve exact delimiter and tail")
        }
        for suffix in [" today.", "\nBring the report.", "\n\n- A list", "\n\n```code```", "\n\n    indented", "\n\nprint('hello')", "\n\na = b + c"] {
            require(IncrementalTranslationPlanner.tail(after: a, in: a + suffix) == nil, "unsafe boundaries must fall back")
        }
        require(IncrementalTranslationPlanner.tail(after: "A\n\n", in: "A\n\nB")?.input == "B", "separator may already be in completed source")
        require(IncrementalTranslationPlanner.tail(after: "가족 👨‍👩‍👧‍👦", in: "가족 👨‍👩‍👧‍👦\n\n다음 문단")?.input == "다음 문단", "Unicode must not corrupt source offsets")
        require(IncrementalTranslationPlanner.tail(after: "é", in: "e\u{301}\n\nB") == nil, "source coverage uses exact bytes")

        // Ordinary prose punctuation must not disable appending.
        for paragraph in [
            "We're hiring engineers who'll own the stack.", "Remote (or hybrid) is fine.", "Use and/or as needed.",
            "C++ and 3+ years required.", "See https://example.com/jobs?id=42&ref=x for details.",
            "내일(목요일) 오후에 \"공유 폴더\"를 확인하세요.", "문서 및/또는 파일."
        ] {
            require(IncrementalTranslationPlanner.tail(after: a, in: a + "\n\n" + paragraph)?.input == paragraph,
                    "prose punctuation is appendable: \(paragraph)")
        }
        let parenthesized = "Copilot auto-completions (which never worked for me) came first."
        require(IncrementalTranslationPlanner.tail(after: parenthesized, in: parenthesized + "\n\nNext.")?.input == "Next.",
                "a closed parenthesis in completed prose keeps appending enabled")
        for suffix in ["\n\nfoo(bar)", "\n\nx == y", "\n\n* item", "\n\n> quote", "\n\n# Heading", "\n\n1. step",
                       "\n\n<b>tag</b>", "\n\nC:\\path", "\n\n{json}", "\n\n[link](url)", "\n\nSay \"hi",
                       "\n\nEngineer(s) wanted.", "\n\nAPI(응용 프로그램) 문서"] {
            require(IncrementalTranslationPlanner.tail(after: a, in: a + suffix) == nil, "code-like or open text falls back: \(suffix)")
        }
        require(IncrementalTranslationPlanner.tail(after: "Note (see", in: "Note (see\n\nbelow) here") == nil,
                "a parenthesis may not close across paragraphs")

        // An explicit `---` line separates independent units, whatever the text around it.
        typealias Tail = IncrementalTranslationPlanner.Tail
        let code = "x = 1 | y", b = "Bring the report."
        require(IncrementalTranslationPlanner.tail(after: code, in: code + "\n\n---\n\n" + b)
                    == Tail(separator: "\n\n---\n\n", input: b, explicit: true), "an explicit boundary after code")
        require(IncrementalTranslationPlanner.tail(after: a, in: a + "\n\n---\n\n" + code)
                    == Tail(separator: "\n\n---\n\n", input: code, explicit: true), "an explicit tail need not be plain text")
        for suffix in ["---" + b, "\n\n- item", "\n\n  ---\n\n" + b, "\n\n--- x", "\n\n- - -\n\n" + b, "\n\n***\n\n" + b,
                       "\n\n\u{2014}\n\n" + b, "\n\n|---|\n\n" + b] {
            require(IncrementalTranslationPlanner.tail(after: code, in: code + suffix) == nil, "not an explicit boundary: \(suffix)")
            require(IncrementalTranslationPlanner.tail(after: a, in: a + suffix)?.explicit != true, "not explicit after prose: \(suffix)")
        }
    }

    private static func explicitBoundaryPlanner() {
        typealias P = IncrementalTranslationPlanner
        typealias Tail = P.Tail
        let code = "x = 1 | y", b = "Bring the report."

        // Every intermediate state of typing a boundary keeps the completed prefix and requests nothing.
        for prefix in [a, code] {
            for suffix in ["\n", "\n\n", "\n\n-", "\n\n--", "\n\n---", "\n\n---\n", "\n\n--- ", "\n-", "\n---", "\n\n---\n\n",
                           "\n\n---\n\n---\n\n", "\n\n-----"] {
                let tail = P.tail(after: prefix, in: prefix + suffix)
                require(tail?.input == "" && tail?.separator == suffix, "typing a boundary keeps the prefix: \(prefix) \(suffix.debugDescription)")
            }
            require(P.tail(after: prefix, in: prefix + "\n---\n" + b) == Tail(separator: "\n---\n", input: b, explicit: true),
                    "a single newline around the line is enough")
            require(P.tail(after: prefix, in: prefix + "\n\n---\n\n---\n\n" + b)?.input == b, "several lines are one boundary")
            // CRLF, and NBSP from a web copy, use the whitespace of `TranslationDocument.isBlank`.
            require(P.tail(after: prefix, in: prefix + "\r\n\r\n---\r\n\r\n" + b)
                        == Tail(separator: "\r\n\r\n---\r\n\r\n", input: b, explicit: true), "CRLF boundary")
            require(P.tail(after: prefix + "\u{A0}", in: prefix + "\u{A0}\n\n---\n\n" + b)?.explicit == true, "A ending in NBSP")
            require(P.tail(after: prefix, in: prefix + "\n\u{A0}\n---\u{A0}\n\n" + b)?.input == b, "NBSP-only and NBSP-padded lines")
        }

        // Fences: a `---` line inside an open fence is content.
        for open in ["Run:\n```bash\nls", "Intro\n```\nls", "Run:\n```bash\nls\n```swift"] {
            require(P.tail(after: open, in: open + "\n\n---\n\n" + b) == nil, "inside an open fence: \(open)")
            require(P.tail(after: open, in: open + "\n\n---")?.input != "", "a fenced `---` is not a delimiter: \(open)")
        }
        for closed in ["Run:\n```bash\nls\n```", "```code```", "~~~\nls"] {
            require(P.tail(after: closed, in: closed + "\n\n---\n\n" + b)?.explicit == true, "outside a fence: \(closed)")
        }

        // The boundary may already be part of the completed prefix.
        require(P.tail(after: a + "\n\n---", in: a + "\n\n---\n\n" + b) == Tail(separator: "\n\n", input: b, explicit: true),
                "the separator is the suffix's share of the boundary")
        require(P.tail(after: a + "\n\n-", in: a + "\n\n---\n\n" + b) == Tail(separator: "--\n\n", input: b, explicit: true),
                "a dash typed earlier completes the boundary")
        require(P.tail(after: a + "\n\n---", in: a + "\n\n----") == Tail(separator: "-", input: "", explicit: true), "a longer line")

        // P0-1: dashes held as trailing were never translated; text that turns them into content is not a tail.
        require(P.tail(after: a + "\n\n-", in: a + "\n\n-\n") == nil, "a dash followed by a newline is content")
        require(P.tail(after: a + "\n\n--", in: a + "\n\n--\n\n" + b) == nil, "two dashes followed by a paragraph are content")
        require(P.tail(after: a + "\n\n---", in: a + "\n\n---x") == nil, "a dash line followed by text is content")
        // A unit ending with a content `-` line keeps its line break, so the snapshot is not read back as typing.
        for source in ["X\n-\n-", "X\n-\n\n---\n\nB", "X\n- \n\n---\n\nB", "X\n--\n"] {
            let unit = P.firstUnit(in: source)
            require(unit.input.hasPrefix("X\n-") && P.unitEnd(of: unit.input) == "X\n".utf8.count + unit.input.dropFirst(2).prefix { $0 == "-" }.count
                        && P.tail(after: unit.input, in: source) != nil, "a final content dash line: \(source.debugDescription)")
        }

        // D1: a tail is cut at its first explicit boundary, without the delimiter at its end.
        require(P.tail(after: a, in: a + "\n\n---\n\nB\n\n---\n\nC")?.input == "B", "first explicit block only")
        require(P.tail(after: a, in: a + "\n\nB\n\n---\n\nC") == Tail(separator: "\n\n", input: "B"), "a blank-line tail is cut too")
        require(P.tail(after: a, in: a + "\n\n---\n\nB1\n\n---\n\nB2")?.input == "B1", "a pasted block with a boundary")
        for end in ["\n\n---", "\n\n--", "\n\n-", "\n\n", " ", "\n\n---\n\n"] {
            require(P.tail(after: a, in: a + "\n\n---\n\n" + b + end)?.input == b, "the delimiter at the end is not requested: \(end.debugDescription)")
            require(P.tail(after: a, in: a + "\n\n" + b + end)?.input == b, "nor after a blank-line tail: \(end.debugDescription)")
        }
        require(P.tail(after: "Run:\n```\nls\n```", in: "Run:\n```\nls\n```\n\n---\n\n```\nA\n---\nB\n```\n\n---\n\nC")?.input
                    == "```\nA\n---\nB\n```", "a fenced `---` does not cut the tail")

        require(P.firstUnit(in: "A\n\n---\n\nB") == Tail(separator: "", input: "A"), "first unit")
        require(P.firstUnit(in: "---\n\nB") == Tail(separator: "---\n\n", input: "B"), "leading boundary with a blank line")
        require(P.firstUnit(in: "\n\n---\n\nB") == Tail(separator: "\n\n---\n\n", input: "B"), "leading blank lines and boundary")
        require(P.firstUnit(in: "---\ntitle: x\n---\n\n본문") == Tail(separator: "", input: "---\ntitle: x"), "front matter is content")
        require(P.firstUnit(in: "A\n\n") == Tail(separator: "", input: "A"), "trailing whitespace is not requested")
        require(P.firstUnit(in: "\n\nA") == Tail(separator: "", input: "\n\nA"), "leading whitespace stays for the segment")
        require(P.firstUnit(in: "Run:\n```bash\nls\n\n---\n\nB") == Tail(separator: "", input: "Run:\n```bash\nls\n\n---\n\nB"),
                "an open fence is not cut")
        require(P.firstUnit(in: "Run:\n```\n---\n```\n\n---\n\nB").input == "Run:\n```\n---\n```", "a closed fence keeps its `---`")

        // D8: the plain-text scope starts after the prefix's last explicit boundary and ends with the tail.
        let blocks = "Alpha.\n\n---\n\nBeta."
        require(P.tail(after: blocks, in: blocks + "\n\nGamma.\n\n---\n\nx = 1") == Tail(separator: "\n\n", input: "Gamma."),
                "a later block does not narrow the scope")
        require(P.tail(after: blocks, in: blocks + "\n\nx = 1\n\n---\n\nDelta.") == nil, "the scope includes the tail")
        require(P.tail(after: code + "\n\n---\n\nBeta.", in: code + "\n\n---\n\nBeta.\n\nGamma.")?.input == "Gamma.",
                "code above the boundary is not checked")
        require(P.tail(after: code + "\n\n---\n\ny = 2", in: code + "\n\n---\n\ny = 2\n\nGamma.") == nil, "code in the block is")
        require(P.tail(after: a, in: a + "\n\nB\n\n- ") == nil, "a list starting after the tail still falls back")

        // Helpers shared by the store and the views.
        for blank in ["", "\n", "---", "-", "--", "\n\n---\n\n", " \u{A0}\n---"] { require(P.isBlankSource(blank), "blank: \(blank.debugDescription)") }
        for text in ["-5", "--x", "---\ntitle", "- ", "A"] { require(!P.isBlankSource(text), "not blank: \(text.debugDescription)") }
        require(P.leadingDelimiter(of: "---\n\nB") == "---\n\n" && P.leadingDelimiter(of: "---\nB") == ""
                    && P.leadingDelimiter(of: "\n\nB") == "\n\n" && P.leadingDelimiter(of: "  \nB") == "  \n", "leading delimiter")
        require(P.unitEnd(of: a + "\n\n---\n\n") == a.utf8.count && P.unitEnd(of: "x\n```\n---") == "x\n```\n---".utf8.count,
                "unit end")
        func ranges(_ text: String, sent: Range<Int> = 0..<0) -> [[Int]] {
            P.boundaryLineRanges(in: text, excludingUTF8: sent).map { [$0.location, $0.length] }
        }
        require(ranges("가😀\n\n---\n\nB") == [[5, 3]], "UTF-16 offsets after Hangul and emoji")
        require(ranges("A\r\n\r\n---\r\n\r\nB") == [[5, 3]], "CRLF is not part of the line")
        require(ranges("A\n\n--- \u{A0}\n\nB") == [[3, 3]], "only the dashes")
        require(ranges("A\n\n---\n\nB", sent: 0..<3) == [[3, 3]] && ranges("A\n\n---\n\nB", sent: 0..<4) == []
                    && ranges("A\n\n---\n\nB", sent: 0..<11) == [], "text sent to the model")
        require(ranges("---\n\nA\n\n---\n\nB", sent: 5..<14) == [[0, 3]], "a separator before the sent text is not sent")
        require(ranges("```\n---\n```\n\n---\n\nB") == [[13, 3]], "a fenced line is content")
        require(ranges("A\n\n--") == [] && ranges("A\n\n---") == [[3, 3]], "only a completed line")
        require(ranges("---\ntitle: x\n---\n\nbody") == [[13, 3]], "front matter opener without a blank line")
        require(ranges("---\n\nB") == [[0, 3]], "a leading boundary")
        require(ranges("---") == [] && ranges("\n\n---\n\n") == [], "without content a line divides nothing and stays text")

        // ⌘↩ appends only, and the result is a delimiter of the same prefix.
        let insertions: [(String, String?)] = [
            ("A", "\n\n---\n\n"), ("A\n", "\n---\n\n"), ("A\n\n", "---\n\n"), ("A  ", "\n\n---\n\n"), ("A\n\n  ", "\n---\n\n"),
            ("A\n\n-", "--\n\n"), ("A\n\n--", "-\n\n"), ("A\n-", "--\n\n"), ("A\n\n---", "\n\n"), ("A\n\n--- ", "\n\n"),
            ("A\n\n---\n", "\n"), ("A\n\n---\n\n", ""), ("Run:\n```bash\nls", nil), ("", nil), ("---", nil), ("-", nil), ("\n\n", nil),
        ]
        for (text, expected) in insertions {
            let insertion = P.boundaryInsertion(after: text)
            require(insertion == expected, "insertion after \(text.debugDescription): \(String(describing: insertion?.debugDescription))")
            guard let insertion else { continue }
            let held = document([("", "A", "")]).covering(text)
            require(held != nil && held?.covering(text + insertion) != nil, "the inserted boundary is covered: \(text.debugDescription)")
            require(P.tail(after: text, in: text + insertion)?.input == "", "the inserted boundary is not requested: \(text.debugDescription)")
        }

        // I1–I3 over prefixes, held delimiters and typed suffixes.
        for content in [a, code] {
            for trailing in ["", "\n", "\n\n", "\n\n-", "\n\n--", "\n\n---", "\n\n---\n\n"] {
                guard let held = document([("", content, "")]).covering(content + trailing) else {
                    fatalError("IncrementalTranslationTests: a delimiter is held as trailing: \(trailing.debugDescription)")
                }
                for suffix in ["", "\n", "\n\n" + b, "-", "--", "x", "\n\n---\n\n", "\n\n---\n\n" + b, "\n\n```\n", "\n\n---\n\n" + b + "\n\n---\n\nC"] {
                    let source = held.input + suffix
                    guard let tail = P.tail(after: held.input, in: source) else { continue }
                    let label = "\(content) \(trailing.debugDescription) \(suffix.debugDescription)"
                    if tail.input.isEmpty {
                        require(held.covering(source) != nil, "I1: an empty tail is covered: \(label)")
                        continue
                    }
                    let consumed = held.input + tail.separator + tail.input
                    require(source.utf8.starts(with: consumed.utf8), "I2: the tail continues the prefix exactly: \(label)")
                    let next = P.tail(after: consumed, in: source)
                    require(next != nil && (next!.input.isEmpty || next!.explicit), "I2: the rest is a delimiter or an explicit block: \(label)")
                    require(isClean(tail.input, in: source), "I3: no boundary or delimiter in the request: \(label)")
                }
            }
        }
    }

    private static func explicitBoundaryDocument() {
        let b = "Bring the report."
        for parts in [[("", a, ""), ("\n\n---\n\n", b, "")], [("", a, "\n\n---\n\n"), ("", b, "")], [("", a, "\n\n-"), ("--\n\n", b, "")],
                      [("", a, "\n\n"), ("---\n\n", b, " ")], [("", a, ""), ("\n---\n", b, "")]] {
            let rendered = document(parts).rendered
            require(rendered.text == "T(\(a))\n\nT(\(b))" && rendered.unitBreaks == ["T(\(a))".utf16.count],
                    "an explicit boundary joins with one blank line and a break: \(parts.map(\.0))")
        }
        let three = document([("", a, ""), ("\n\n---\n\n", b, ""), ("\n\n", "C", "\n\n---\n\n"), ("", "D", "")])
        require(three.rendered.unitBreaks == ["T(\(a))".utf16.count, "T(\(a))\n\nT(\(b))\n\nT(C)".utf16.count], "breaks only at explicit boundaries")
        require(three.text == three.rendered.text, "text is the rendered text")
        let blank = document([("", a, ""), ("\n\n\n", b, "")])
        require(blank.text == "T(\(a))\n\n\nT(\(b))" && blank.rendered.unitBreaks == [], "blank-line joins are unchanged")
        let head = document([("", a, "")])
        let preview = head.text(appending: "T(\(b))", separator: "\n\n---\n\n")
        let final = document([("", a, ""), ("\n\n---\n\n", b, "")]).text
        require(final.hasPrefix(preview.text) && preview.tailStart == "T(\(a))".utf16.count
                    && head.appendsExplicitly(separator: "\n\n---\n\n") && !head.appendsExplicitly(separator: "\n\n"), "an explicit preview")
        require(document([("", a, "\n\n-")]).appendsExplicitly(separator: "--\n\n"), "a boundary split over trailing and separator")

        for end in ["\n\n-", "\n\n--", "\n\n---", "\n\n---\n\n", "\n---", "\r\n\r\n---\r\n"] {
            let covered = head.covering(a + end)
            require(covered?.segments.count == 1 && covered?.segments[0].trailing == end, "a typed boundary is covered: \(end.debugDescription)")
        }
        require(head.covering(a + "\n\n--x") == nil && head.covering(a + "---") == nil, "dashes that are content are not covered")
        let fenced = document([("", "Run:\n```bash\nls", "")])
        require(fenced.covering("Run:\n```bash\nls\n\n---") == nil && fenced.covering("Run:\n```bash\nls\n\n") != nil, "inside a fence only whitespace")
        // A structured unit that itself ends with dashes is covered when a dash completes them (I1).
        let dashed = document([("", "Intro\n--", "")])
        require(dashed.covering("Intro\n---") != nil && dashed.covering("Intro\n--\n\n---") != nil, "dashes ending a unit")
        require(IncrementalTranslationPlanner.tail(after: "Intro\n--", in: "Intro\n---")?.input == "", "and the planner agrees")

        let two = document([("", a, ""), ("\n\n---\n\n", b, "")])
        for source in [b, "---\n\n" + b, "\n\n---\n\n" + b] {
            let kept = two.retainingSuffix(for: source)
            require(kept?.input == source && kept?.segments.count == 1 && kept?.rendered.unitBreaks == [], "upper block removed: \(source.debugDescription)")
        }
        let split = document([("", a, "\n\n---\n\n"), ("", b, "")])
        require(split.retainingSuffix(for: b)?.input == b, "the boundary held as trailing of the removed unit")

        let accept: (IncrementalTranslationPlanner.Tail) -> Bool = { !$0.input.isEmpty }
        let edited = two.replanned(for: a + "\n\n---\n\nBring the reports.", accepting: accept)
        require(edited?.0.segments.count == 1 && edited?.1.input == "Bring the reports." && edited?.1.explicit == true, "an edited lower block")
        let shortened = two.replanned(for: a + "\n\n---\n\nBring", accepting: accept)
        require(shortened?.0.input == a && shortened?.1.input == "Bring", "a shortened lower block")
        let paragraphs = document([("", a, ""), ("\n\n", b, "")])
        require(paragraphs.replanned(for: a + "\n\nBring the reports.", accepting: accept) == nil, "a blank-line unit is not cut")
        let above = document([("", a, ""), ("\n\n---\n\n", b, ""), ("\n\n", "Third.", "")])
        require(above.replanned(for: a + "\n\n---\n\n" + b + "\n\nThird!", accepting: accept)?.1.input == b + "\n\nThird!",
                "a blank-line unit is cut at the explicit boundary above it")
        let typed = document([("", a, "\n\n--")]).replanned(for: a + "\n\n--x", accepting: accept)
        require(typed?.0.input == a && typed?.1 == IncrementalTranslationPlanner.Tail(separator: "\n\n", input: "--x"), "trailing dashes became content")
        let enter = document([("", a, "\n\n-")]).replanned(for: a + "\n\n-\n", accepting: accept)
        require(enter?.0.input == a && enter?.1.input == "-\n", "a dash followed by a newline is requested as content, with its newline")
        let middle = document([("", a, ""), ("\n\n---\n\n", b, ""), ("\n\n---\n\n", "Third.", "")])
            .replanned(for: a + "\n\n---\n\nThird.", accepting: accept)
        require(middle?.0.input == a && middle?.1 == IncrementalTranslationPlanner.Tail(separator: "\n\n---\n\n", input: "Third.", explicit: true), "the middle block removed")
        // The first tail with text decides (D5): a rejected append is not cut back to send the unchanged B again.
        let rejectsOK: (IncrementalTranslationPlanner.Tail) -> Bool = { $0.input != "ok" }
        require(two.replanned(for: a + "\n\n---\n\n" + b + "\n\nok", accepting: rejectsOK) == nil, "a rejected append keeps B")
        require(two.replanned(for: a + "\n\n---\n\nBring!", accepting: rejectsOK)?.1.input == "Bring!", "an accepted edit is still replanned")
    }

    /// I3: a request holds no boundary line, and where it reaches the end of the source, no dash of the
    /// source's trailing delimiter. A `-` line followed by text is content, and a final one keeps its line break.
    private static func isClean(_ input: String, in source: String) -> Bool {
        typealias P = IncrementalTranslationPlanner
        guard P.boundaryLineRanges(in: input).isEmpty else { return false }
        guard source.utf8.reversed().starts(with: input.utf8.reversed()) else { return true }
        let held = source.utf8.dropFirst(max(P.unitEnd(of: source), source.utf8.count - input.utf8.count))
        return !held.contains(UInt8(ascii: "-"))
    }

    /// Units with `text == "T(input)"`.
    private static func document(_ parts: [(String, String, String)]) -> TranslationDocument {
        let basis = TranslationResult(id: UUID(), inputVersion: 0, input: parts.first?.1 ?? "", direction: .englishToKorean,
                                      sourceLanguage: .english, targetLanguage: .korean, text: "")
        return TranslationDocument(generation: UUID(), basis: basis, segments: parts.map {
            TranslationSegment(id: UUID(), separator: $0.0, input: $0.1, text: "T(\($0.1))", trailing: $0.2)
        })
    }

    private static func proseWithPunctuationAppends() async {
        // The recorded case: a closed parenthesis in A and apostrophes in B.
        let first = "Copilot auto-completions (which never worked for me) came first."
        let second = "I've also built agents. The model's context matters when it's writing code."
        let probe = TranslationProbe(), store = make(probe)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(first)
        let request = await probe.nextRequest()
        await probe.complete(request.id, with: "코파일럿 자동완성(내겐 작동하지 않았다)이 먼저였다.")
        await settle()
        store.invokeCopiedText(first + "\n\n" + second)
        let tail = await probe.nextRequest()
        require(tail.input == second, "only the appended prose is requested")
        require(store.displayedText == "코파일럿 자동완성(내겐 작동하지 않았다)이 먼저였다."
                    && store.display.tailStart == store.displayedText?.utf16.count,
                "the completed translation stays readable while the tail is pending")
        await probe.complete(tail.id, with: "에이전트도 만들었다.")
        await settle()
        require(store.resultText == "코파일럿 자동완성(내겐 작동하지 않았다)이 먼저였다.\n\n에이전트도 만들었다.", "tail appends below")

        // s: dashes followed by text after plain prose are a paragraph, typed key by key.
        let (dashProbe, dashStore) = await seeded(a, "첫 문단.")
        await type(["\n", "\n", "-", "-", "x"], into: dashStore)
        require((await dashProbe.nextRequest()).input == "--x", "s: `--x` is requested as a paragraph")
    }

    private static func streamingPrefixInvariant() async {
        struct Case {
            let first: String
            let firstText: String
            let appended: String
            let partials: [String]
            let final: String
        }
        let b = "Second paragraph."
        let cases = [
            Case(first: a, firstText: "첫 문단.", appended: a + "\n\n" + b, partials: ["둘", "둘째 문단"], final: "둘째 문단."),
            Case(first: a, firstText: "첫 문단.", appended: a + "\n\n\n" + b, partials: ["둘", "둘째 문단"], final: "둘째 문단."),
            Case(first: a, firstText: "첫 문단.", appended: a + "\r\n\r\n" + b, partials: ["둘", "둘째 문단"], final: "둘째 문단."),
            Case(first: a, firstText: "첫 문단.\n", appended: a + "\n\n" + b, partials: ["둘", "둘째 문단"], final: "둘째 문단."),
            Case(first: a, firstText: "첫 문단.", appended: a + "\n\n" + b, partials: ["\n", "\n둘째"], final: "\n둘째 문단."),
            Case(first: a + "\n", firstText: "첫 문단.", appended: a + "\n\n" + b, partials: ["둘", "둘째"], final: "둘째 문단."),
            Case(first: a + "\n\n", firstText: "첫 문단.", appended: a + "\n\n" + b, partials: ["둘", "둘째"], final: "둘째 문단."),
            // Claude: the final result may trim what the stream already showed.
            Case(first: a, firstText: "첫 문단.", appended: a + "\n\n" + b, partials: ["둘째 문단.\n", "둘째 문단.\n "], final: "둘째 문단."),
        ]
        for (index, item) in cases.enumerated() {
            let probe = TranslationProbe(), store = make(probe)
            store.setDirection(.englishToKorean)
            store.invokeCopiedText(item.first)
            let first = await probe.nextRequest()
            await probe.complete(first.id, with: item.firstText)
            await settle()
            let identity = store.display.identity
            let head = store.displayedText ?? ""
            store.invokeCopiedText(item.appended)
            let tail = await probe.nextRequest()
            require(tail.input == b, "case \(index): only the tail is requested")
            var shown: [String] = []
            for partial in item.partials {
                store.receivePartialText(partial, for: tail)
                try? await Task.sleep(for: .milliseconds(80))
                let display = store.display
                require(display.identity == identity && display.tailStart == head.utf16.count, "case \(index): stable identity and tail start")
                if let previous = shown.last, let text = display.text {
                    require(text.utf16.starts(with: previous.utf16), "case \(index): snapshots only grow")
                }
                shown.append(display.text ?? "")
            }
            await probe.complete(tail.id, with: item.final)
            await settle()
            let final = store.resultText ?? ""
            require(store.display.identity == identity && store.display.tailStart == head.utf16.count, "case \(index): completion keeps identity")
            for text in shown {
                require(final.utf16.starts(with: text.utf16), "case \(index): final text extends every shown snapshot")
            }
        }

        // A provider retry may replace the whole draft; only the tail changes.
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        let identity = store.display.identity
        store.invokeCopiedText(ab)
        let tail = await probe.nextRequest()
        store.receivePartialText("버려질 초안", for: tail)
        try? await Task.sleep(for: .milliseconds(80))
        await probe.complete(tail.id, with: "둘째 문단.")
        await settle()
        require(store.display.identity == identity && store.resultText == "첫 문단.\n\n둘째 문단.", "retry keeps the completed prefix and identity")

        // An explicit boundary joins with exactly one blank line, and every snapshot is a prefix of the final text.
        for boundary in ["\n\n---\n\n", "\n---\n", "\n\n\n---\n\n\n"] {
            let (explicitProbe, explicitStore) = await seeded(a, "첫 문단.\n")
            let identity = explicitStore.display.identity
            explicitStore.invokeCopiedText(a + boundary + b)
            let tail = await explicitProbe.nextRequest()
            require(tail.input == b, "\(boundary.debugDescription): only the block is requested")
            var shown: [String] = []
            for partial in ["\n둘", "\n둘째 문단"] {
                explicitStore.receivePartialText(partial, for: tail)
                try? await Task.sleep(for: .milliseconds(80))
                shown.append(explicitStore.display.text ?? "")
                require(explicitStore.display.unitBreaks == ["첫 문단.\n".utf16.count] && explicitStore.display.identity == identity,
                        "\(boundary.debugDescription): the line stays at the end of A")
            }
            await explicitProbe.complete(tail.id, with: "\n둘째 문단.")
            await settle()
            let final = explicitStore.resultText ?? ""
            require(final == "첫 문단.\n\n둘째 문단." && shown.allSatisfy { final.utf16.starts(with: $0.utf16) },
                    "\(boundary.debugDescription): one blank line, snapshots only grow")
        }
    }

    private static func trailingCoverage() async {
        let noCache = TranslationStore.Configuration(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 0)
        for suffix in ["\n", "\n\n", "  ", " \n"] {
            let probe = TranslationProbe(), store = make(probe, configuration: noCache)
            await seed(store, probe)
            let id = store.displaySegments[0].id
            store.invokeCopiedText(a + suffix)
            require(store.status == .success && store.canCopy && store.result?.input == a + suffix,
                    "whitespace after a completed unit publishes without the LRU")
            require(store.displaySegments[0].id == id && store.resultText == "첫 문단.", "the translation is unchanged")
            require(await probe.requestCount() == 1, "no request for whitespace")
        }

        let expiring = TranslationProbe()
        let expiringStore = make(expiring, configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheLifetime: .milliseconds(50)))
        await seed(expiringStore, expiring)
        try? await Task.sleep(for: .milliseconds(80))
        expiringStore.invokeCopiedText(a + "\n")
        require(expiringStore.status == .success && expiringStore.canCopy, "an expired cache entry cannot leave the document waiting")

        let typed = TranslationProbe(), typedStore = make(typed, configuration: noCache)
        await seed(typedStore, typed)
        typedStore.editSource(a + "\n", isComposing: false)
        require(typedStore.status == .success && typedStore.canCopy, "typing one delimiter keeps the result usable")
        typedStore.editSource(a + "\n\n", isComposing: false)
        require(typedStore.status == .success && typedStore.canCopy, "typing a blank line keeps the result usable")
        typedStore.editSource(ab, isComposing: false)
        let typedTail = await typed.nextRequest()
        require(typedTail.input == "Second paragraph.", "the next paragraph is requested alone")
        await typed.complete(typedTail.id, with: "둘째.")
        await settle()
        require(typedStore.result?.input == ab && typedStore.resultText == "첫 문단.\n\n둘째.", "covered delimiter joins once")

        for extra in ["\n", " "] {
            let probe = TranslationProbe(), store = make(probe, configuration: noCache)
            await seed(store, probe)
            store.invokeCopiedText(ab)
            let tail = await probe.nextRequest()
            store.editSource(ab + extra, isComposing: false)
            await settle()
            require(!(await probe.wasCancelled(tail.id)), "whitespace after a pending tail keeps its request")
            await probe.complete(tail.id, with: "둘째.")
            await settle()
            require(store.status == .success && store.result?.input == ab + extra && store.resultText == "첫 문단.\n\n둘째.",
                    "the completed tail covers trailing whitespace")
            require(await probe.requestCount() == 2, "no duplicate request for trailing whitespace")
        }

        let composing = TranslationProbe(), composingStore = make(composing, configuration: noCache)
        await seed(composingStore, composing)
        composingStore.beginComposition()
        composingStore.updateComposition(a + "\n")
        require(!composingStore.canCopy && composingStore.result == nil, "IME composition never publishes coverage")
        composingStore.endComposition(a + "\n")
        require(composingStore.status == .success && composingStore.canCopy, "composition commit publishes coverage")
        require(await composing.requestCount() == 1, "composition needs no request")

        let late = TranslationProbe(), lateStore = make(late, configuration: noCache)
        await seed(lateStore, late)
        lateStore.invokeCopiedText(ab)
        let pending = await late.nextRequest()
        lateStore.invokeCopiedText(a + "\n")
        require(lateStore.status == .success && lateStore.result?.input == a + "\n", "truncation with whitespace publishes")
        await late.complete(pending.id, with: "늦은 둘째")
        await settle()
        require(lateStore.resultText == "첫 문단." && lateStore.displaySegments.count == 1, "a late response for removed text is ignored")

        let other = TranslationProbe(), otherStore = make(other, configuration: noCache)
        await seed(otherStore, other)
        otherStore.setTranslationContext(cacheContext: "other", provider: "other", model: "model", modelLabel: "Other")
        otherStore.invokeCopiedText(a + "\n")
        let fresh = await other.nextRequest()
        require(fresh.provider == "other" && otherStore.displayedText == nil, "another selection never reuses the document")
        await other.complete(fresh.id, with: "다른 제공자")
        await settle()
    }

    private static func reviewFollowUps() async {
        // A new copied selection that only shares a word prefix is a new document.
        let copied = TranslationProbe(), copiedStore = make(copied)
        copiedStore.setDirection(.englishToKorean)
        copiedStore.invokeCopiedText("Yes")
        let yes = await copied.nextRequest()
        await copied.complete(yes.id, with: "네")
        await settle()
        let yesIdentity = copiedStore.display.identity
        copiedStore.invokeCopiedText("Yesterday I went to the store.")
        _ = await copied.nextRequest()
        require(!copiedStore.display.isStale && copiedStore.display.text == nil && copiedStore.display.identity != yesIdentity,
                "a copied word that merely starts with the old text starts a fresh surface")

        // Two different messages with the same signature are unrelated.
        let signed = TranslationProbe(), signedStore = make(signed)
        signedStore.setDirection(.englishToKorean)
        let signature = "\n\nBest regards,\nJohn Smith"
        signedStore.invokeCopiedText("Please send the quarterly report by Friday so we can review it together." + signature)
        let mail = await signed.nextRequest()
        await signed.complete(mail.id, with: "분기 보고서를 금요일까지 보내 주세요.\n\n감사합니다,\n존 스미스")
        await settle()
        signedStore.invokeCopiedText("The office will be closed on Monday because of the holiday." + signature)
        _ = await signed.nextRequest()
        require(!signedStore.display.isStale && signedStore.display.text == nil, "a shared signature does not keep the old mail")

        // A copied edit of the same text keeps the old translation dimmed.
        let edited = TranslationProbe(), editedStore = make(edited)
        editedStore.setDirection(.englishToKorean)
        editedStore.invokeCopiedText("Hello world.")
        let hello = await edited.nextRequest()
        await edited.complete(hello.id, with: "안녕 세상.")
        await settle()
        editedStore.invokeCopiedText("Hello world")
        _ = await edited.nextRequest()
        require(editedStore.display.isStale, "a copied edit of the same text keeps the old translation readable")

        // Typing keeps the looser rule so the draft does not flicker.
        let typing = TranslationProbe(), typingStore = make(typing)
        typingStore.setDirection(.englishToKorean)
        typingStore.editSource("Yes", isComposing: false)
        let typed = await typing.nextRequest()
        await typing.complete(typed.id, with: "네")
        await settle()
        typingStore.editSource("Yesterday", isComposing: false)
        _ = await typing.nextRequest()
        require(typingStore.display.isStale, "typing keeps the previous translation dimmed")

        // Retrying a failed whole retranslation repeats it instead of using the cache.
        for error in [TranslationStoreError.timedOut as Error, CancellationError() as Error] {
            let probe = TranslationProbe(), store = make(probe)
            await seed(store, probe)
            store.invokeCopiedText(ab)
            let tail = await probe.nextRequest()
            await probe.complete(tail.id, with: "둘째.")
            await settle()
            store.retranslateWholeDocument()
            let whole = await probe.nextRequest()
            await probe.fail(whole.id, with: error)
            await settle()
            require(store.isShowingSupersededText, "the old text stays while the whole retranslation failed")
            store.retry()
            let again = await probe.nextRequest()
            require(again.input == ab, "retry repeats the whole-document request")
            await probe.complete(again.id, with: "문맥을 포함한 전체 번역")
            await settle()
            require(store.resultText == "문맥을 포함한 전체 번역" && !store.lastResultWasCached, "retry is not answered from the cache")
        }
    }

    private static func firstRequestContinuity() async {
        // Appending while the first translation is still streaming keeps it.
        let probe = TranslationProbe(), store = make(probe)
        store.setDirection(.englishToKorean)
        store.invokeCopiedText(a)
        let first = await probe.nextRequest()
        store.receivePartialText("첫", for: first)
        try? await Task.sleep(for: .milliseconds(80))
        let identity = store.display.identity
        store.invokeCopiedText(ab)
        await settle()
        require(!(await probe.wasCancelled(first.id)) && store.display.text == "첫" && !store.display.isStale,
                "the first request keeps streaming while a paragraph is appended")
        await probe.complete(first.id, with: "첫 문단.")
        let second = await probe.nextRequest()
        require(second.input == "Second paragraph.", "only the appended paragraph follows")
        require(store.displayedText == "첫 문단." && store.display.identity == identity, "the first result stays on the same surface")
        await probe.complete(second.id, with: "둘째.")
        await settle()
        let firstCount = await probe.requestCount()
        require(store.resultText == "첫 문단.\n\n둘째." && firstCount == 2, "two requests in total")

        // Enter during the first request of prose with parentheses.
        let parenthesized = "Copilot auto-completions (which never worked for me) came first."
        let enter = TranslationProbe(), enterStore = make(enter)
        enterStore.setDirection(.englishToKorean)
        enterStore.invokeCopiedText(parenthesized)
        let request = await enter.nextRequest()
        enterStore.editSource(parenthesized + "\n", isComposing: false)
        await settle()
        require(!(await enter.wasCancelled(request.id)), "a trailing newline keeps the first request")
        await enter.complete(request.id, with: "코파일럿 자동완성이 먼저였다.")
        await settle()
        let enterCount = await enter.requestCount()
        require(enterStore.canCopy && enterStore.result?.input == parenthesized + "\n" && enterCount == 1,
                "the completed request covers the trailing newline")

        // An unfinished draft is not kept as the earlier translation.
        let draft = TranslationProbe(), draftStore = make(draft)
        draftStore.setDirection(.englishToKorean)
        draftStore.invokeCopiedText("The quick brown fox jumps over the lazy dog.")
        let pending = await draft.nextRequest()
        draftStore.receivePartialText("빠른 갈색", for: pending)
        try? await Task.sleep(for: .milliseconds(80))
        draftStore.invokeCopiedText("The quick brown fox jumps over the sleepy dog.")
        _ = await draft.nextRequest()
        require(!draftStore.display.isStale && draftStore.display.text == nil, "a draft is not kept dimmed")

        // Whitespace around the paragraph boundary.
        for separator in [" \n\n", "\n \n"] {
            require(IncrementalTranslationPlanner.tail(after: a, in: a + separator + "Next.")?.input == "Next.",
                    "spaces around a blank line still separate paragraphs")
        }
        let spaced = TranslationProbe(), spacedStore = make(spaced)
        await seed(spacedStore, spaced)
        spacedStore.invokeCopiedText(ab)
        let b = await spaced.nextRequest()
        for text in [ab + " ", ab + " \n", ab + " \n\n", ab + " \n\nThird."] {
            spacedStore.editSource(text, isComposing: false)
        }
        await settle()
        require(!(await spaced.wasCancelled(b.id)), "typing a spaced boundary keeps the pending paragraph")
        await spaced.complete(b.id, with: "둘째.")
        let c = await spaced.nextRequest()
        require(c.input == "Third.", "the next paragraph is requested alone")
        await spaced.complete(c.id, with: "셋째.")
        await settle()

        // Leading units removed while a tail is pending, plus a trailing space.
        let rebase = TranslationProbe(), rebaseStore = make(rebase)
        await seed(rebaseStore, rebase)
        rebaseStore.invokeCopiedText(ab)
        let rb = await rebase.nextRequest()
        await rebase.complete(rb.id, with: "둘째.")
        await settle()
        rebaseStore.invokeCopiedText(abc)
        let rc = await rebase.nextRequest()
        rebaseStore.invokeCopiedText("Second paragraph.\n\nThird paragraph. ")
        await settle()
        require(!(await rebase.wasCancelled(rc.id)), "a trailing space does not cancel the rebased tail")
        await rebase.complete(rc.id, with: "셋째.")
        await settle()
        let rebaseCount = await rebase.requestCount()
        require(rebaseStore.resultText == "둘째.\n\n셋째." && rebaseCount == 3, "rebased tail completes once")

        // A short source edited by one character keeps the earlier translation readable.
        let short = TranslationProbe(), shortStore = make(short)
        shortStore.setDirection(.englishToKorean)
        shortStore.invokeCopiedText("Hello world.")
        let hello = await short.nextRequest()
        await short.complete(hello.id, with: "안녕 세상.")
        await settle()
        let shortIdentity = shortStore.display.identity
        shortStore.invokeCopiedText("Hello world")
        _ = await short.nextRequest()
        require(shortStore.display.isStale && shortStore.display.identity == shortIdentity, "a short edit keeps the old text dimmed")

        // An unrelated source does not keep the old language label.
        let labels = TranslationProbe(), labelStore = make(labels)
        labelStore.invokeCopiedText("The meeting starts at three in the afternoon.")
        let english = await labels.nextRequest()
        await labels.complete(english.id, with: "회의는 오후 세 시에 시작합니다.")
        await settle()
        labelStore.setEngineReady(false)
        labelStore.invokeCopiedText("오늘 회의 자료를 준비해 주세요.")
        require(labelStore.displayedSourceLanguage == nil, "an unrelated source clears the language label")

        // b: a boundary and a block typed while a code-like first unit streams.
        let streamProbe = TranslationProbe(), streamStore = make(streamProbe)
        streamStore.setDirection(.englishToKorean)
        streamStore.invokeCopiedText(codeA)
        let streamed = await streamProbe.nextRequest()
        streamStore.receivePartialText("먼저", for: streamed)
        try? await Task.sleep(for: .milliseconds(80))
        await type(["\n", "\n", "-", "-", "-", "\n", "\n"], into: streamStore)
        require(streamStore.sourceBoundaryLines.count == 1 && streamStore.displaySegments.isEmpty, "b: the line is grey before A completes")
        await type([bring, "s"], into: streamStore)
        let streamedCancelled = await streamProbe.wasCancelled(streamed.id)
        require(!streamedCancelled && streamStore.display.text == "먼저" && streamStore.display.unitBreaks.isEmpty,
                "b: A keeps streaming while B is typed and edited")
        await streamProbe.complete(streamed.id, with: codeT)
        let streamTail = await streamProbe.nextRequest()
        let streamCount = await streamProbe.requestCount()
        require(streamTail.input == bring + "s" && streamCount == 2, "b: then only B")
        await streamProbe.complete(streamTail.id, with: bringT)
        await settle()
    }

    private static func coverageEdgeCases() async {
        let noCache = TranslationStore.Configuration(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 0)

        // Text already on screen needs no connection.
        let offline = TranslationProbe(), offlineStore = make(offline, configuration: noCache)
        await seed(offlineStore, offline)
        offlineStore.setEngineReady(false)
        offlineStore.invokeCopiedText(a + "\n")
        require(offlineStore.status == .success && offlineStore.canCopy, "covered whitespace publishes while disconnected")

        // Structured text is covered byte for byte, too.
        let list = "- First item\n- Second item"
        let structured = TranslationProbe(), structuredStore = make(structured, configuration: noCache)
        structuredStore.setDirection(.englishToKorean)
        structuredStore.invokeCopiedText(list)
        let listRequest = await structured.nextRequest()
        await structured.complete(listRequest.id, with: "- 첫 항목\n- 둘째 항목")
        await settle()
        structuredStore.invokeCopiedText(list + "\n")
        require(structuredStore.status == .success && structuredStore.canCopy, "a list keeps its translation for a trailing newline")
        require(await structured.requestCount() == 1, "no request for trailing whitespace after a list")

        // Leading units and trailing whitespace removed together.
        let both = TranslationProbe(), bothStore = make(both, configuration: noCache)
        await seed(bothStore, both)
        bothStore.invokeCopiedText(ab)
        let tail = await both.nextRequest()
        await both.complete(tail.id, with: "둘째.")
        await settle()
        bothStore.invokeCopiedText(ab + "\n")
        bothStore.invokeCopiedText("Second paragraph.")
        require(bothStore.resultText == "둘째." && bothStore.canCopy, "the remaining unit is reused without its trailing newline")
        require(await both.requestCount() == 2, "no request after removing leading units and whitespace")

        // A letterless paragraph appends in automatic mode.
        let automatic = TranslationProbe(), autoStore = make(automatic)
        autoStore.invokeCopiedText("The meeting starts at three in the afternoon.")
        let english = await automatic.nextRequest()
        await automatic.complete(english.id, with: "회의는 오후 세 시에 시작합니다.")
        await settle()
        autoStore.invokeCopiedText(autoStore.sourceText + "\n\n2026-10-07 15:00")
        let date = await automatic.nextRequest()
        require(date.input == "2026-10-07 15:00", "dates carry no language and append alone")
        await automatic.complete(date.id, with: "2026-10-07 15:00")
        await settle()

        // A provider change while an earlier translation is kept dimmed.
        let held = TranslationProbe(), heldStore = make(held)
        await seed(heldStore, held)
        let identity = heldStore.display.identity
        heldStore.invokeCopiedText(a + "\nMore")
        let fallback = await held.nextRequest()
        heldStore.setTranslationContext(cacheContext: "other", provider: "other", model: "model", modelLabel: "Other")
        require(heldStore.display.isStale && heldStore.requiresRetranslation, "the dimmed text stays while a new selection waits")
        await held.complete(fallback.id, with: "이전 제공자의 늦은 응답")
        await settle()
        require(heldStore.display.isStale && heldStore.display.text == "첫 문단.", "a late response from the old selection is ignored")
        heldStore.retranslateSelection()
        let fresh = await held.nextRequest()
        require(fresh.provider == "other" && fresh.input == a + "\nMore", "the new selection translates the whole source")
        await held.complete(fresh.id, with: "새 제공자의 번역")
        await settle()
        require(!heldStore.display.isStale && heldStore.display.text == "새 제공자의 번역" && heldStore.display.identity == identity,
                "the replacement appears once on the same surface")

        // e: the lower block removed, or only its delimiter left: no request, even disconnected.
        for remaining in ["", "\n\n-", "\n\n--", "\n\n---", "\n\n---\n\n"] {
            let (lowerProbe, lower) = await seeded(configuration: noCache)
            lower.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
            await completeAll(lowerProbe, [bringT])
            lower.setEngineReady(false)
            lower.editSource(codeA + remaining, isComposing: false)
            let lowerCount = await lowerProbe.requestCount()
            require(lower.status == .success && lower.resultText == codeT && lower.canCopy && lowerCount == 2,
                    "e: \(remaining.debugDescription) is covered by T(A)")
        }
        // g: a `---` line inside an open fence is content; the whole source is requested.
        let fence = "Run:\n```bash\nls"
        let (fenceProbe, fenceStore) = await seeded(fence, "실행:\n```bash\nls")
        fenceStore.invokeCopiedText(fence + "\n\n---\n\n" + bring)
        let fenceRequest = await fenceProbe.nextRequest()
        require(fenceRequest.input == fence + "\n\n---\n\n" + bring && fenceStore.sourceBoundaryLines.isEmpty, "g: inside an open fence")
        await fenceProbe.complete(fenceRequest.id, with: "실행:\n```bash\nls\n\n---\n\n보고서")
        await settle()
        // r: only dashes left is an empty source.
        for dashes in ["---", "-", "--", "\n\n---\n\n"] {
            let (dashProbe, dashStore) = await seeded(a, "첫 문단.")
            dashStore.editSource(dashes, isComposing: false)
            await settle()
            let dashCount = await dashProbe.requestCount()
            require(dashCount == 1 && dashStore.display.text == nil && dashStore.status == .idle, "r: \(dashes.debugDescription) is empty")
            // Dashes left of a document that starts with a boundary are not a continuation to keep dimmed.
            let (leadProbe, lead) = await seeded("---\n\n" + a, "첫 문단.")
            lead.editSource(dashes, isComposing: false)
            await settle()
            let leadCount = await leadProbe.requestCount()
            require(leadCount == 1 && lead.display.text == nil && !lead.display.isStale, "r: a blank source is not kept dimmed: \(dashes.debugDescription)")
            dashStore.invokeCopiedText(dashes)
            require(dashStore.status == .error(.emptyInput), "r: \(dashes.debugDescription) is an empty explicit request")
        }
    }

    private static func supersededDisplay() async {
        let autoProbe = TranslationProbe(), automatic = make(autoProbe)
        automatic.invokeCopiedText("The meeting starts at three in the afternoon.")
        let english = await autoProbe.nextRequest()
        await autoProbe.complete(english.id, with: "회의는 오후 세 시에 시작합니다.")
        await settle()
        let identity = automatic.display.identity
        automatic.invokeCopiedText(automatic.sourceText + "\n\n회의 자료를 준비해 주세요.")
        let whole = await autoProbe.nextRequest()
        require(automatic.display.isStale && automatic.display.text == "회의는 오후 세 시에 시작합니다.",
                "a whole-document fallback keeps the earlier translation readable")
        require(automatic.displayedText == nil && !automatic.canCopy, "the stale translation cannot be copied")
        require(automatic.displayedSourceLanguage == .english, "language labels stay while the replacement is pending")
        automatic.receivePartialText("전체", for: whole)
        try? await Task.sleep(for: .milliseconds(80))
        require(automatic.display.isStale && automatic.display.text == "회의는 오후 세 시에 시작합니다.",
                "a streaming replacement does not rewrite the text being read")
        await autoProbe.complete(whole.id, with: "전체 결과")
        await settle()
        require(!automatic.display.isStale && automatic.display.text == "전체 결과" && automatic.display.identity == identity,
                "the replacement appears once, on the same surface")

        let typedProbe = TranslationProbe()
        let typed = make(typedProbe, configuration: .init(typingDebounce: .milliseconds(30), requestTimeout: nil))
        await seed(typed, typedProbe)
        let typedIdentity = typed.display.identity
        typed.editSource(a + "\nMore", isComposing: false)
        typed.editSource(a + "\nMore words", isComposing: false)
        require(typed.display.isStale && typed.display.text == "첫 문단." && typed.display.identity == typedIdentity,
                "repeated invalidation keeps the original translation")
        let request = await typedProbe.nextRequest()
        require(request.input == a + "\nMore words", "a single newline still needs the whole document")
        await typedProbe.fail(request.id, with: TranslationStoreError.timedOut)
        await settle()
        require(typed.display.isStale && typed.status == .error(.timedOut), "a failed replacement keeps the earlier translation")
        typed.editSource("", isComposing: false)
        require(typed.display.text == nil && typed.display.identity != typedIdentity, "clearing the source clears the surface")

        let wholeProbe = TranslationProbe(), wholeStore = make(wholeProbe)
        await seed(wholeStore, wholeProbe)
        wholeStore.invokeCopiedText(ab)
        let second = await wholeProbe.nextRequest()
        await wholeProbe.complete(second.id, with: "둘째.")
        await settle()
        let wholeIdentity = wholeStore.display.identity
        wholeStore.retranslateWholeDocument()
        let fresh = await wholeProbe.nextRequest()
        require(wholeStore.display.isStale && wholeStore.display.text == "첫 문단.\n\n둘째.", "whole retranslation keeps the old text readable")
        await wholeProbe.complete(fresh.id, with: "문맥을 포함한 전체 번역")
        await settle()
        require(wholeStore.display.text == "문맥을 포함한 전체 번역" && wholeStore.display.identity == wholeIdentity,
                "the whole translation replaces the old text in place")

        let unrelatedProbe = TranslationProbe(), unrelated = make(unrelatedProbe)
        await seed(unrelated, unrelatedProbe)
        let unrelatedIdentity = unrelated.display.identity
        unrelated.invokeCopiedText("Completely different.")
        _ = await unrelatedProbe.nextRequest()
        require(unrelated.display.text == nil && !unrelated.display.isStale && unrelated.display.identity != unrelatedIdentity,
                "an unrelated source starts a fresh surface")

        // i: the upper block edited while B is intact: A′ alone, then B, then one swap.
        let editedA = codeA.replacingOccurrences(of: "first", with: "now")
        for capacity in [32, 0] {
            let (upperProbe, upper) = await seeded(configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: capacity))
            upper.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
            await completeAll(upperProbe, [bringT])
            let old = codeT + "\n\n" + bringT, identity = upper.display.identity
            upper.editSource(editedA + "\n\n---\n\n" + bring, isComposing: false)
            let upperA = await upperProbe.nextRequest()
            require(upperA.input == editedA && upper.display.isStale && upper.display.text == old
                        && upper.display.unitBreaks == [codeT.utf16.count], "i: A′ alone, the old text dimmed with its line")
            await upperProbe.complete(upperA.id, with: "새 A")
            await settle()
            if capacity == 0 {
                let again = await upperProbe.nextRequest()
                require(again.input == bring && upper.display.isStale && upper.display.text == old && !upper.hasPartialResult,
                        "i: B is requested again while the old text stays")
                await upperProbe.complete(again.id, with: bringT)
                await settle()
            }
            let upperCount = await upperProbe.requestCount()
            require(!upper.display.isStale && upper.resultText == "새 A\n\n" + bringT && upper.display.unitBreaks == ["새 A".utf16.count]
                        && upper.display.identity == identity && upperCount == (capacity == 0 ? 4 : 3),
                    "i: B from the paragraph cache when kept, and one swap")
        }
    }

    private static func appendAndQueue() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        let firstID = store.displaySegments[0].id
        store.invokeCopiedText(ab)
        let second = await probe.nextRequest()
        require(second.input == "Second paragraph.", "only appended paragraph goes to provider")
        require(store.displayedText == "첫 문단." && store.resultText == nil, "display prefix while composite is invalid")
        require(!store.canCopy && !store.canInsert, "partial output cannot be used as whole result")
        store.invokeCopiedText(abc)
        store.invokeCopiedText(abc)
        await settle()
        let count = await probe.requestCount(), cancelled = await probe.wasCancelled(second.id)
        require(count == 2 && !cancelled, "unchanged active tail is neither cancelled nor duplicated")
        require(store.isActiveRequest(second), "AppModel accepts active partial request")
        await probe.complete(second.id, with: "둘째 문단.")
        let third = await probe.nextRequest()
        require(third.input == "Third paragraph.", "queued payload excludes earlier paragraphs")
        require(store.displayedText == "첫 문단.\n\n둘째 문단.", "partial completion renders in order")
        await probe.complete(third.id, with: "셋째 문단.")
        await settle()
        require(store.resultText == "첫 문단.\n\n둘째 문단.\n\n셋째 문단.", "final result covers entire source")
        require(store.canCopy && store.canInsert && store.result?.input == abc, "only final snapshot enables output")
        require(store.displaySegments[0].id == firstID, "prefix identity remains stable")
        store.invokeCopiedText(a)
        require(store.resultText == "첫 문단." && store.canCopy, "completed boundary truncation restores immediately")
        require(await probe.requestCount() == 3, "truncation makes no request")

        // c: code A---plain B completed; a blank-line paragraph after B appends alone.
        let (blockProbe, blocks) = await seeded()
        blocks.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
        await completeAll(blockProbe, [bringT])
        blocks.invokeCopiedText(blocks.sourceText + "\n\n" + close)
        let blockTail = await blockProbe.nextRequest()
        require(blockTail.input == close, "c: only C")
        await blockProbe.complete(blockTail.id, with: closeT)
        await settle()
        require(blocks.resultText == codeT + "\n\n" + bringT + "\n\n" + closeT && blocks.display.unitBreaks == [codeT.utf16.count], "c: one line")
        // A non-plain B is requested again together with C; A stays, nothing is dimmed.
        let (codeProbe, code) = await seeded()
        code.invokeCopiedText(codeA + "\n\n---\n\nSet y = 2.")
        await completeAll(codeProbe, ["y = 2로 설정하세요."])
        let codeAID = code.displaySegments[0].id
        code.invokeCopiedText(code.sourceText + "\n\n" + close)
        let both = await codeProbe.nextRequest()
        require(both.input == "Set y = 2.\n\n" + close && code.displaySegments.map(\.id) == [codeAID] && !code.display.isStale
                    && code.display.text == codeT, "c: B and C together below A")
        await codeProbe.complete(both.id, with: "y = 2로 설정하고 " + closeT)
        await settle()
    }

    private static func editAndRetry() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        store.invokeCopiedText(a + "\n\nOld second.")
        let old = await probe.nextRequest()
        store.invokeCopiedText(a + "\n\nNew second.")
        let new = await probe.nextRequest()
        require(new.input == "New second.", "pending edit keeps completed prefix")
        await probe.complete(old.id, with: "오래된 응답")
        await settle()
        require(store.displayedText == "첫 문단." && !store.isActiveRequest(old), "obsolete response cannot publish")
        await probe.fail(new.id, with: TranslationStoreError.timedOut)
        await settle()
        require(store.displayedText == "첫 문단." && store.status == .error(.timedOut), "failure keeps earlier output")
        store.invokeCopiedText(store.sourceText)
        let retry = await probe.nextRequest()
        require(retry.input == "New second.", "retry excludes completed prefix")
        await probe.complete(retry.id, with: "새 둘째.")
        await settle()
        require(store.resultText == "첫 문단.\n\n새 둘째.", "retry merges once")

        // f: a completed block after an explicit boundary edited: only B′, A stays; undo uses the paragraph cache.
        for edited in [String(bring.dropLast()), "Bring the old report.", bring + "\nAnd the notes."] {
            let (lowerProbe, lower) = await seeded()
            lower.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
            await completeAll(lowerProbe, [bringT])
            let aID = lower.displaySegments[0].id
            lower.editSource(codeA + "\n\n---\n\n" + edited, isComposing: false)
            let changed = await lowerProbe.nextRequest()
            require(changed.input == edited && lower.displaySegments.map(\.id) == [aID] && lower.display.text == codeT
                        && !lower.display.isStale, "f: only \(edited.debugDescription)")
            await lowerProbe.complete(changed.id, with: "새 B")
            await settle()
            lower.editSource(codeA + "\n\n---\n\n" + bring, isComposing: false)
            await settle()
            let lowerCount = await lowerProbe.requestCount()
            require(lower.resultText == codeT + "\n\n" + bringT && lowerCount == 3, "f: undo needs no request")
        }
        let (paragraphProbe, paragraphs) = await seeded(a, "첫 문단.")
        paragraphs.invokeCopiedText(ab)
        await completeAll(paragraphProbe, ["둘째."])
        paragraphs.editSource(a + "\n\nSecond paragraph!", isComposing: false)
        require((await paragraphProbe.nextRequest()).input == a + "\n\nSecond paragraph!", "f: a blank-line unit edit is still whole")
    }

    private static func removeLeadingUnits() async {
        let probe = TranslationProbe(), store = make(probe, configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 0))
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let second = await probe.nextRequest()
        await probe.complete(second.id, with: "둘째.")
        await settle()
        let secondID = store.displaySegments[1].id
        store.invokeCopiedText("Second paragraph.")
        require(store.resultText == "둘째." && store.canCopy, "removing a completed first unit reuses the remaining translation immediately")
        require(store.displaySegments[0].id == secondID, "remaining unit retains its identity")
        require(await probe.requestCount() == 2, "prefix deletion does not need LRU or a provider request")

        store.invokeCopiedText("Second paragraph.\n\nThird paragraph.")
        let third = await probe.nextRequest()
        require(third.input == "Third paragraph.", "append after prefix deletion sends only the new unit")
        await probe.complete(third.id, with: "셋째.")
        await settle()
        store.invokeCopiedText("\n\nThird paragraph.")
        require(store.resultText == "셋째." && store.result?.input == "\n\nThird paragraph.", "leftover separators belong to current source coverage")

        // Removing text inside one atomic translation cannot be approximated by
        // slicing the target language string at the same character offset.
        store.invokeCopiedText("paragraph.")
        let partial = await probe.nextRequest()
        require(partial.input == "paragraph." && store.displayedText == nil, "partial-unit cuts must not reuse unrelated translation text")
        await probe.complete(partial.id, with: "문단.")
        await settle()

        let otherProbe = TranslationProbe(), other = make(otherProbe)
        await seed(other, otherProbe)
        other.invokeCopiedText(ab)
        let b = await otherProbe.nextRequest()
        await otherProbe.complete(b.id, with: "둘째.")
        await settle()
        other.invokeCopiedText(abc)
        let pendingC = await otherProbe.nextRequest()
        other.invokeCopiedText("Second paragraph.\n\nThird paragraph.\n\nFourth paragraph.")
        await settle()
        require(other.displayedText == "둘째." && !other.canCopy, "prefix deletion preserves completed remainder while tail is pending")
        require(!(await otherProbe.wasCancelled(pendingC.id)), "removing A must not cancel unchanged C")
        await otherProbe.complete(pendingC.id, with: "셋째.")
        let fourth = await otherProbe.nextRequest()
        require(fourth.input == "Fourth paragraph.", "rebased active response queues only the later tail")
        await otherProbe.complete(fourth.id, with: "넷째.")
        await settle()
        require(other.resultText == "둘째.\n\n셋째.\n\n넷째." && other.canCopy, "rebased results assemble in the new source order")
        require(await otherProbe.requestCount() == 4, "rebasing must not duplicate any request")

        let repeatedProbe = TranslationProbe(), repeated = make(repeatedProbe)
        await seed(repeated, repeatedProbe)
        repeated.invokeCopiedText(a + "\n\n" + a)
        let duplicate = await repeatedProbe.nextRequest()
        await repeatedProbe.complete(duplicate.id, with: "반복된 첫 문단.")
        await settle()
        let originalIDs = repeated.displaySegments.map(\.id)
        repeated.invokeCopiedText(a + "\n\n" + a + "\n\nNew paragraph.")
        let addition = await repeatedProbe.nextRequest()
        require(addition.input == "New paragraph." && repeated.displaySegments.map(\.id) == originalIDs,
                "repeated paragraphs must prefer original prefix rather than falsely dropping a unit")
        await repeatedProbe.complete(addition.id, with: "추가 문단.")
        await settle()

        // d: the upper block of an explicit pair removed, with the boundary held by either unit.
        for heldByA in [false, true] {
            for remaining in [bring, "---\n\n" + bring, "\n\n---\n\n" + bring] {
                let (upperProbe, upper) = await seeded(configuration: noCache)
                if heldByA { await type(["\n\n---\n\n"], into: upper) }
                upper.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
                await completeAll(upperProbe, [bringT])
                let bID = upper.displaySegments[1].id
                upper.invokeCopiedText(remaining)
                let upperCount = await upperProbe.requestCount()
                require(upper.resultText == bringT && upper.displaySegments.map(\.id) == [bID] && upperCount == 2 && upper.canCopy
                            && upper.display.unitBreaks.isEmpty, "d: \(remaining.debugDescription), held by A: \(heldByA)")
            }
        }
        // d2: the middle block removed; C comes back from the paragraph cache when it is kept.
        for capacity in [32, 0] {
            let (middleProbe, middle) = await seeded(configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: capacity))
            middle.invokeCopiedText(codeA + "\n\n---\n\n" + bring + "\n\n---\n\n" + close)
            await completeAll(middleProbe, [bringT, closeT])
            middle.invokeCopiedText(codeA + "\n\n---\n\n" + close)
            if capacity == 0 {
                let again = await middleProbe.nextRequest()
                require(again.input == close && middle.display.text == codeT, "d2: without the cache only C")
                await middleProbe.complete(again.id, with: closeT)
                await settle()
            }
            let middleCount = await middleProbe.requestCount()
            require(middle.resultText == codeT + "\n\n" + closeT && middle.display.unitBreaks == [codeT.utf16.count]
                        && middleCount == (capacity == 0 ? 4 : 3), "d2: A, a line and C")
        }
    }

    private static func cacheAlignment() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let second = await probe.nextRequest()
        await probe.complete(second.id, with: "둘째.")
        await settle()
        let ids = store.displaySegments.map(\.id)
        store.editSource("", isComposing: false)
        store.invokeCopiedText(ab)
        require(store.lastResultWasCached && store.displaySegments.map(\.id) == ids, "whole cache restores alignment")
        store.invokeCopiedText(a)
        store.invokeCopiedText(ab)
        require(store.canCopy && store.lastResultWasCached, "tail cache reuses without replacing prefix")
        require(await probe.requestCount() == 2, "known tail needs no network")

        let disabledProbe = TranslationProbe()
        let disabled = make(disabledProbe, configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheCapacity: 0, cacheLifetime: .zero))
        await seed(disabled, disabledProbe)
        disabled.invokeCopiedText(ab)
        let tail = await disabledProbe.nextRequest()
        require(tail.input == "Second paragraph." && disabled.displayedText == "첫 문단.", "current document does not depend on LRU lifetime/capacity")
        await disabledProbe.complete(tail.id, with: "추가.")
        await settle()

        // An explicit document restored from the whole cache keeps its line.
        let (explicitProbe, explicit) = await seeded()
        explicit.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
        await completeAll(explicitProbe, [bringT])
        explicit.invokeCopiedText("Completely different.")
        await completeAll(explicitProbe, ["완전히 다른 글."])
        explicit.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
        let explicitCount = await explicitProbe.requestCount()
        require(explicit.lastResultWasCached && explicitCount == 3 && explicit.display.unitBreaks == [codeT.utf16.count],
                "the cached document keeps its line")
    }

    private static func compositionAndLimits() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        store.beginComposition()
        store.updateComposition(a + "\n\n다음")
        await settle()
        require(store.displayedText == "첫 문단." && !store.canCopy, "IME preserves display, disables output actions")
        require(await probe.requestCount() == 1, "composition does not call provider")
        store.endComposition(ab)
        let next = await probe.nextRequest()
        require(next.input == "Second paragraph.", "IME commit sends only tail")
        store.invokeCopiedText(a + "\n\n" + String(repeating: "x", count: 4_000))
        require(store.status == .error(.inputTooLong(limit: 4_000)) && store.displayedText == "첫 문단.", "whole source limit preserves valid prefix")
        await probe.complete(next.id, with: "늦은 결과")
        await settle()
        require(!store.canCopy && store.displaySegments.count == 1, "overlong input rejects old response")

        // Composing a block after a boundary keeps T(A) and requests nothing until it is committed.
        let (imeProbe, ime) = await seeded()
        await type(["\n\n---\n\n"], into: ime)
        ime.beginComposition()
        ime.updateComposition(codeA + "\n\n---\n\n보고")
        await settle()
        let imeCount = await imeProbe.requestCount()
        require(ime.display.text == codeT && !ime.display.isStale && imeCount == 1, "composing after the boundary")
        ime.endComposition(codeA + "\n\n---\n\n보고서")
        require((await imeProbe.nextRequest()).input == "보고서", "the committed block alone")
    }

    private static func selectionAndReplacement() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let old = await probe.nextRequest()
        store.setTranslationContext(cacheContext: "new", provider: "other", model: "model", modelLabel: "Other")
        require(store.displayedText == "첫 문단." && store.requiresRetranslation, "selection change retains display")
        store.retranslateSelection()
        let fresh = await probe.nextRequest()
        require(fresh.input == ab && fresh.provider == "other", "new context requests entire source")
        await probe.complete(old.id, with: "이전 제공자")
        await probe.complete(fresh.id, with: "전체 새 번역")
        await settle()
        require(store.displaySegments.count == 1 && store.resultText == "전체 새 번역", "providers cannot be mixed")
        store.invokeCopiedText("Completely different.")
        let replacement = await probe.nextRequest()
        require(store.displayedText == nil, "unrelated input resets coverage")
        await probe.complete(replacement.id, with: "다른 문서")
        await settle()
    }

    private static func reconnect() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let old = await probe.nextRequest()
        store.setEngineReady(false)
        require(store.displayedText == "첫 문단." && store.status == .disconnected, "disconnect keeps prefix")
        store.setEngineReady(true)
        let fresh = await probe.nextRequest()
        require(fresh.input == "Second paragraph.", "reconnect resumes tail only")
        await probe.complete(old.id, with: "오래된 응답")
        await probe.complete(fresh.id, with: "둘째.")
        await settle()
        require(store.resultText == "첫 문단.\n\n둘째.", "only reconnected request publishes")
    }

    private static func wholeRetranslation() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let tail = await probe.nextRequest()
        await probe.complete(tail.id, with: "둘째.")
        await settle()
        store.retranslateWholeDocument()
        let whole = await probe.nextRequest()
        require(whole.input == ab, "whole action bypasses document and LRU")
        await probe.complete(whole.id, with: "문맥을 포함한 전체 번역")
        await settle()
        require(store.displaySegments.count == 1 && store.resultText == "문맥을 포함한 전체 번역", "whole result replaces alignment atomically")
        require(store.testCacheEntryCount == 3 && store.testCacheIsConsistent, "replacing a cached key keeps the byte total exact")

        // q: '전체 다시 번역' with an explicit boundary goes block by block, bypassing the cache, and swaps once.
        let (blockProbe, blocks) = await seeded()
        blocks.invokeCopiedText(codeA + "\n\n---\n\n" + bring)
        await completeAll(blockProbe, [bringT])
        let identity = blocks.display.identity
        blocks.retranslateWholeDocument()
        let first = await blockProbe.nextRequest()
        require(first.input == codeA && blocks.display.isStale && blocks.display.unitBreaks == [codeT.utf16.count],
                "q: A first, the old text dimmed with its line")
        await blockProbe.complete(first.id, with: "새 A")
        let second = await blockProbe.nextRequest()
        require(second.input == bring && blocks.display.isStale, "q: B again, not from the cache")
        await blockProbe.fail(second.id, with: TranslationStoreError.timedOut)
        await settle()
        blocks.retry()
        let again = await blockProbe.nextRequest()
        require(again.input == codeA && blocks.display.isStale, "q: retry starts again from the first block")
        await blockProbe.complete(again.id, with: "새 A")
        await completeAll(blockProbe, ["새 B"])
        require(!blocks.display.isStale && blocks.resultText == "새 A\n\n새 B" && blocks.display.unitBreaks == ["새 A".utf16.count]
                    && blocks.display.identity == identity, "q: one swap, the line kept")
        blocks.setTranslationContext(cacheContext: "other", provider: "other", model: "model", modelLabel: "Other")
        blocks.retranslateSelection()
        let provider = await blockProbe.nextRequest()
        require(provider.input == codeA && provider.provider == "other", "q: a provider change, block by block")
        await blockProbe.complete(provider.id, with: "다른 A")
        let providerB = await blockProbe.nextRequest()
        require(providerB.input == bring, "q: then B")
        await blockProbe.complete(providerB.id, with: "다른 B")
        await settle()
        blocks.setDirection(.koreanToEnglish)
        let direction = await blockProbe.nextRequest()
        require(direction.input == codeA, "q: a direction change, block by block")
        await blockProbe.complete(direction.id, with: "A")
        let directionB = await blockProbe.nextRequest()
        require(directionB.input == bring, "q: then B")
        await blockProbe.complete(directionB.id, with: "B")
        await settle()
    }

    private static func byteLimits() async {
        let probe = TranslationProbe()
        let store = make(probe, configuration: .init(typingDebounce: .zero, requestTimeout: nil, maximumResultBytes: 80, maximumCacheBytes: 1))
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let tail = await probe.nextRequest()
        await probe.complete(tail.id, with: String(repeating: "x", count: 81))
        await settle()
        require(store.status == .error(.resultTooLong) && store.displayedText == "첫 문단.", "oversized result retains prefix")
        store.editSource("", isComposing: false)
        store.invokeCopiedText(a)
        let uncached = await probe.nextRequest()
        require(await probe.requestCount() == 3, "oversized cache entry is not stored")
        await probe.complete(uncached.id, with: "새 결과")
        await settle()
        require(store.testCacheEntryCount == 0 && store.testCacheIsConsistent, "rejected entries leave no bytes behind")
    }

    private static func expiredCachePurge() async {
        // A whole retranslation looks nothing up; saving its result still drops expired entries.
        let probe = TranslationProbe()
        let store = make(probe, configuration: .init(typingDebounce: .zero, requestTimeout: nil, cacheLifetime: .milliseconds(200)))
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let tail = await probe.nextRequest()
        await probe.complete(tail.id, with: "둘째.")
        await settle()
        require(store.testCacheEntryCount == 3 && store.testCacheIsConsistent, "A, the B paragraph and A+B are cached")
        try? await Task.sleep(for: .milliseconds(250))
        store.retranslateWholeDocument()
        let whole = await probe.nextRequest()
        require(whole.input == ab && store.testCacheEntryCount == 3, "a whole retranslation looks nothing up")
        await probe.complete(whole.id, with: "문맥을 포함한 전체 번역")
        await settle()
        require(store.testCacheEntryCount == 1 && store.testCacheIsConsistent, "saving drops expired entries without a lookup")
    }

    private static func pinnedPrefixAndDirection() async {
        let probe = TranslationProbe(), store = make(probe)
        await seed(store, probe)
        store.invokeCopiedText(ab)
        let second = await probe.nextRequest()
        await probe.complete(second.id, with: "둘째.")
        await settle()
        store.invokeCopiedText(a)
        store.retranslateWholeDocument()
        let fresh = await probe.nextRequest()
        await probe.complete(fresh.id, with: "새로 번역한 첫 문단.")
        await settle()
        store.invokeCopiedText(ab)
        require(store.resultText == "새로 번역한 첫 문단.\n\n둘째.", "older whole-cache entry cannot replace fresh pinned prefix")
        require(await probe.requestCount() == 3, "known tail can use cache with a new prefix translation")
        store.invokeCopiedText(abc)
        let third = await probe.nextRequest()
        store.setDirection(.koreanToEnglish)
        let changed = await probe.nextRequest()
        require(changed.input == abc && store.displayedText == nil, "direction change resets all source coverage")
        await probe.complete(third.id, with: "늦은 셋째")
        await probe.complete(changed.id, with: "Whole document in the new direction")
        await settle()
        require(store.result?.id == changed.id && store.displaySegments.count == 1, "late tail cannot cross direction generations")
        require(store.testCacheIsConsistent, "replaced and direction-separated entries keep the byte total exact")
    }

    private static func debounceAndLanguage() async {
        let probe = TranslationProbe()
        let store = make(probe, configuration: .init(typingDebounce: .milliseconds(30), requestTimeout: nil))
        await seed(store, probe)
        store.editSource(a + "\n\nSecond", isComposing: false)
        store.editSource(abc, isComposing: false)
        require(store.displayedText == "첫 문단." && store.status == .waiting, "debounce keeps prefix visible")
        require(await probe.requestCount() == 1, "no request before debounce")
        let combined = await probe.nextRequest()
        require(combined.input == "Second paragraph.\n\nThird paragraph.", "unrequested tail may batch")
        await probe.complete(combined.id, with: "둘째.\n\n셋째.")
        await settle()

        let autoProbe = TranslationProbe(), automatic = make(autoProbe)
        automatic.invokeCopiedText("The meeting starts at three in the afternoon.")
        let english = await autoProbe.nextRequest()
        await autoProbe.complete(english.id, with: "회의는 오후 세 시에 시작합니다.")
        await settle()
        automatic.invokeCopiedText(automatic.sourceText + "\n\n회의 자료를 준비해 주세요.")
        let mixed = await autoProbe.nextRequest()
        require(mixed.input == automatic.sourceText && automatic.displayedText == nil, "opposite-language append falls back")
        await autoProbe.complete(mixed.id, with: "전체 결과")
        await settle()
    }

    private static func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "IncrementalTranslationTests: \(message)")
    }

    private static func report(_ name: String) {
        FileHandle.standardOutput.write(Data("Incremental test: \(name)\n".utf8))
    }
}
