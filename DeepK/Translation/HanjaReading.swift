/// 한자의 한글 독음과 한자어 소리 규칙. 독음 표는 `HanjaReadingData`(Unihan kHangul에서 생성)를 처음 쓸 때 읽는다.
enum HanjaReading {
    /// 확장 A(U+3400–4DBF) 6,592자 다음에 기본 블록(U+4E00–9FFF) 20,992자. 0은 독음 없음.
    /// 생성 데이터가 깨졌으면 빈 표가 되어 치환을 하지 않는다.
    private static let table: [UInt16] = parse(HanjaReadingData.rows)
    static let entryCount = 27_584

    static func reading(of scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let index: Int
        switch scalar.value {
        case 0x3400...0x4DBF: index = Int(scalar.value - 0x3400)
        case 0x4E00...0x9FFF: index = 6_592 + Int(scalar.value - 0x4E00)
        default: return nil
        }
        guard index < table.count, table[index] != 0 else { return nil }
        return Unicode.Scalar(UInt32(table[index]))
    }

    /// 줄마다 첫 코드 포인트가 이어지는지, 칸이 64개인지, 독음이 한글 음절인지 확인한다.
    static func parse(_ rows: String) -> [UInt16] {
        var table: [UInt16] = []
        table.reserveCapacity(entryCount)
        var expected: UInt32 = 0x3400
        for row in rows.split(separator: "\n") {
            guard let colon = row.firstIndex(of: ":"), UInt32(row[..<colon], radix: 16) == expected else { return malformed() }
            let cells = row.unicodeScalars[row.index(after: colon)...]
            guard cells.count == 64 else { return malformed() }
            for cell in cells {
                guard cell == "." || isSyllable(cell) else { return malformed() }
                table.append(cell == "." ? 0 : UInt16(cell.value))
            }
            expected = expected + 64 == 0x4DC0 ? 0x4E00 : expected + 64
        }
        return table.count == entryCount ? table : malformed()
    }

    private static func malformed() -> [UInt16] {
        assertionFailure("HanjaReadingData.rows is malformed; regenerate it with scripts/generate-hanja-readings.py")
        return []
    }

    static func isSyllable(_ scalar: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value)
    }

    /// 단어 첫머리의 두음법칙(한글 맞춤법 제10·12항): 량 → 양, 력 → 역, 락 → 낙, 로 → 노, 녀 → 여.
    static func wordInitial(_ syllable: Unicode.Scalar) -> Unicode.Scalar {
        guard let (initial, vowel, final) = parts(of: syllable) else { return syllable }
        switch initial {
        case 5: return compose(yVowels.contains(vowel) ? 11 : 2, vowel, final)
        case 2 where yVowels.contains(vowel): return compose(11, vowel, final)
        default: return syllable
        }
    }

    /// 모음이나 ㄴ 받침 뒤의 렬·률은 열·율이다(제11항 붙임 1): 비율, 선율, 규율. 확률은 그대로다.
    static func afterSyllable(previous: Unicode.Scalar, _ syllable: Unicode.Scalar) -> Unicode.Scalar {
        guard let (initial, vowel, final) = parts(of: syllable), initial == 5, vowel == 6 || vowel == 17, final == 8,
              let before = parts(of: previous), before.final == 0 || before.final == 4
        else { return syllable }
        return compose(11, vowel, final)
    }

    /// 不은 ㄷ·ㅈ으로 시작하는 음절 앞에서 부(부족, 부정, 부당), 그 밖에는 불(불안, 불가)이다.
    static func bu(next: Unicode.Scalar?) -> Unicode.Scalar {
        let initial = next.flatMap(parts(of:))?.initial
        return compose(7, 13, initial == 3 || initial == 12 ? 0 : 8)
    }

    /// ㅑ ㅒ ㅕ ㅖ ㅛ ㅠ ㅣ
    private static let yVowels: Set<UInt32> = [2, 3, 6, 7, 12, 17, 20]

    private static func parts(of syllable: Unicode.Scalar) -> (initial: UInt32, vowel: UInt32, final: UInt32)? {
        guard isSyllable(syllable) else { return nil }
        let index = syllable.value - 0xAC00
        return (index / 588, index % 588 / 28, index % 28)
    }

    private static func compose(_ initial: UInt32, _ vowel: UInt32, _ final: UInt32) -> Unicode.Scalar {
        Unicode.Scalar(0xAC00 + (initial * 21 + vowel) * 28 + final)!
    }
}
