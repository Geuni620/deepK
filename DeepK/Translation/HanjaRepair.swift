/// 한국어 결과에 섞인 한자를 한글 독음으로 바꾼다(보안이 确保된 → 보안이 확보된).
///
/// - 원문(모델 입력)에 있는 한자는 그대로 둔다. 이어진 한자 묶음에 원문 한자가 하나라도 있으면 묶음 전체를 둔다.
/// - 코드 블록, 인라인 코드, URL 안은 고치지 않는다(`TranslationOutputLint.CodeScanner`의 인과 모드).
///   `<aN>` 링크 태그 사이의 글자는 번역된 산문이므로 고친다.
/// - 4자 이하 묶음이고, 결과의 앞쪽 어디든(앞 줄 포함) 한글이 있었거나 공백·탭 3개 이내로 바로 뒤가 한글일 때만 고친다.
///   목록·표·제목 줄에 혼자 놓인 낱말도 고친다. 중국어 문단이 통째로 나온 결과는 한글 음 나열로 바꾸지 않고 그대로 두며 센다.
/// - 앞이 가나이거나 뒤가 가나·전각 문장 부호인 묶음(한국어 뒤의 중국어·일본어 문장), 괄호에 꼭 맞게 든 묶음(예(禮))은 둔다.
/// - 단어 첫머리는 두음법칙(年末 → 연말, 2015年 → 2015년), 모음·ㄴ 받침 뒤의 렬·률은 열·율, 不은 ㄷ·ㅈ 앞에서 부.
///
/// 한자와 한글 음절은 모두 UTF-16 한 단위라 길이와 모든 위치가 그대로이고 ASCII는 바뀌지 않는다.
/// 그래서 `TranslationMarkup`의 블록·스팬·보류 판정이 고치기 전과 같다.
struct HanjaRepair: Sendable {
    struct Counts: Equatable, Sendable {
        /// 독음으로 바꾼 글자
        var replaced = 0
        /// 고칠 묶음이지만 독음이 없어 둔 글자
        var unreadable = 0
        /// 범위 조건에 맞지 않거나 원문 한자와 이어져 둔 글자
        var kept = 0
        /// 코드·URL 안이라 둔 글자
        var inCode = 0
    }

    private let protected: Set<Unicode.Scalar>

    init(protecting sources: [String]) {
        protected = Set(sources.flatMap { $0.unicodeScalars.filter(TranslationOutputLint.isHan) })
    }

    /// 완료한 결과 전체를 고친다.
    func apply(to text: String) -> (text: String, counts: Counts) {
        var pass = Pass(protected: protected)
        for scalar in text.unicodeScalars { pass.consume(scalar) }
        pass.finish()
        return (pass.output, pass.counts)
    }

    /// 스트리밍 조각용. 판정이 남은 끝 묶음(4자를 넘을 수도, 판정할 다음 글자가 아직 없을 수도, 끝의 不이 다음
    /// 음절을 기다릴 수도 있다)은 뒤따르는 공백 3개까지 함께 다음 조각까지 보류한다. 한자가 없으면 늦추지 않는다.
    /// 보이는 글은 뒤에만 붙고, 같은 글의 완료 결과(`apply`)의 앞부분과 같다.
    struct Stream: Sendable {
        private let protected: Set<Unicode.Scalar>
        private var raw = ""
        private var pass: Pass

        init(_ repair: HanjaRepair) {
            protected = repair.protected
            pass = Pass(protected: repair.protected)
        }

        mutating func repairedPrefix(of snapshot: String) -> String {
            var start = snapshot.startIndex
            if snapshot.utf8.starts(with: raw.utf8) {
                start = snapshot.utf8.index(snapshot.utf8.startIndex, offsetBy: raw.utf8.count)
            } else {
                pass = Pass(protected: protected)
            }
            for scalar in snapshot.unicodeScalars[start...] { pass.consume(scalar) }
            raw = snapshot
            return pass.output
        }
    }
}

/// 왼쪽에서 오른쪽으로 한 번 읽으며 고친다. 판정한 글자만 `output`에 쓰고 쓴 글자는 다시 고치지 않는다.
private struct Pass: Sendable {
    let protected: Set<Unicode.Scalar>
    private(set) var output = ""
    private(set) var counts = HanjaRepair.Counts()
    private var scanner = TranslationOutputLint.CodeScanner(urls: true)
    /// 마지막으로 쓴 글자(고친 독음 포함). 두음법칙과 렬·률 판정에 쓴다.
    private var previous: Unicode.Scalar?
    /// 앞의 산문에 한글 음절이 있었는지. 모델이 쓴 글 기준이며 고친 독음은 세지 않는다.
    private var hangulSeen = false
    /// 판정 중인 한자 묶음과 시작할 때의 `hangulSeen`, 묶음 바로 앞 글자
    private var run: [Unicode.Scalar] = []
    private var runAfterHangul = false
    private var runBefore: Unicode.Scalar?
    /// 묶음이 공백으로 끝나 다음 글자를 기다리는 중이면 그 공백들
    private var spaces: [Unicode.Scalar] = []
    /// 그대로 두기로 정한 묶음이 아직 이어지는 중
    private var keeping = false

    init(protected: Set<Unicode.Scalar>) {
        self.protected = protected
    }

    mutating func consume(_ scalar: Unicode.Scalar) {
        let code = scanner.isCode(scalar)
        let han = !code && TranslationOutputLint.isHan(scalar)
        if keeping {
            if han { keep(scalar); return }
            keeping = false
        } else if !spaces.isEmpty {
            if !code, scalar == " " || scalar == "\t", spaces.count < 3 { spaces.append(scalar); return }
            settle(accept: accepts(next: scalar, afterSpaces: true), next: spaces[0])
        } else if !run.isEmpty {
            if han {
                run.append(scalar)
                if protected.contains(scalar) || run.count > 4 {
                    settle(accept: false, next: nil)
                    keeping = true
                }
                return
            }
            if !code, scalar == " " || scalar == "\t" {
                spaces = [scalar]
                return
            }
            settle(accept: accepts(next: scalar, afterSpaces: false), next: scalar)
        }
        if han {
            if protected.contains(scalar) {
                emit(scalar)
                keeping = true
            } else {
                run = [scalar]
                runAfterHangul = hangulSeen
                runBefore = previous
            }
            return
        }
        if code, TranslationOutputLint.isHan(scalar), !protected.contains(scalar) { counts.inCode += 1 }
        if !code, HanjaReading.isSyllable(scalar) { hangulSeen = true }
        emit(scalar)
    }

    /// 글이 끝났다. 뒤 글자로 판정할 묶음은 판정할 글자가 없으므로 그대로 둔다.
    mutating func finish() {
        guard !run.isEmpty else { return }
        settle(accept: accepts(next: nil, afterSpaces: !spaces.isEmpty), next: nil)
    }

    /// 묶음을 고칠지. `next`는 묶음 뒤(공백 3개까지 건너뛴) 글자이고, 글이 끝났으면 nil이다.
    /// - 앞에 한글이 있었으면 고치고, 없었으면 `next`가 한글일 때만 고친다(범위 조건).
    /// - 앞 글자나 `next`가 가나이거나 `next`가 전각 문장 부호(、。「」，：；！？)면 둔다. 한국어 결과 뒤에 온 중국어·일본어
    ///   문장이다. 한국어 문장은 보통 ASCII 문장 부호를 쓰므로 "보안이 确保된", "确保."는 그대로 고친다.
    /// - 괄호 안에 꼭 맞게 놓인 묶음(예(禮), 정명（正名）)은 한글 낱말에 붙인 한자 병기라 둔다.
    private func accepts(next: Unicode.Scalar?, afterSpaces: Bool) -> Bool {
        if let runBefore, TranslationOutputLint.isKana(runBefore) { return false }
        if let next, TranslationOutputLint.isKana(next) || Self.isFullWidthPunctuation(next) { return false }
        if !afterSpaces, let runBefore, let next, runBefore == "(" || runBefore == "（", next == ")" || next == "）" { return false }
        guard let next else { return runAfterHangul }
        return runAfterHangul || HanjaReading.isSyllable(next)
    }

    /// CJK 기호와 문장 부호(U+3000–303F)와 전각 ，：；！？
    private static func isFullWidthPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        (0x3000...0x303F).contains(scalar.value) || [0xFF0C, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F].contains(scalar.value)
    }

    /// 묶음을 고치거나 그대로 쓰고, 기다리며 모은 공백을 쓴다. `next`는 묶음 바로 뒤 글자다(끝의 不 판정).
    private mutating func settle(accept: Bool, next: Unicode.Scalar?) {
        for (offset, han) in run.enumerated() {
            guard accept else { keep(han); continue }
            guard var reading = HanjaReading.reading(of: han) else {
                counts.unreadable += 1
                emit(han)
                continue
            }
            if han == "不" {
                reading = HanjaReading.bu(next: offset + 1 < run.count ? HanjaReading.reading(of: run[offset + 1]) : next)
            }
            if let previous, previous.properties.isAlphabetic || previous.properties.numericType != nil {
                reading = HanjaReading.afterSyllable(previous: previous, reading)
            } else {
                reading = HanjaReading.wordInitial(reading)
            }
            counts.replaced += 1
            emit(reading)
        }
        run.removeAll()
        for space in spaces { emit(space) }
        spaces.removeAll()
    }

    private mutating func keep(_ han: Unicode.Scalar) {
        if !protected.contains(han) { counts.kept += 1 }
        emit(han)
    }

    private mutating func emit(_ scalar: Unicode.Scalar) {
        output.unicodeScalars.append(scalar)
        previous = scalar
    }
}
