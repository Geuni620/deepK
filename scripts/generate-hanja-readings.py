#!/usr/bin/env python3
"""Unihan의 kHangul로 한자 → 한글 독음 표 DeepK/Translation/HanjaReadingData.swift를 만든다.

한국어 결과에 섞인 한자(确保 → 확보)를 결정적으로 고칠 때 쓴다. 표준 라이브러리만 쓴다.

  # Unihan.zip은 새 빈 디렉터리에 받는다.
  d=$(mktemp -d); curl -fL -o "$d/Unihan.zip" https://www.unicode.org/Public/18.0.0/ucd/Unihan.zip
  python3 -I scripts/generate-hanja-readings.py --unihan "$d/Unihan.zip"           # 생성
  python3 -I scripts/generate-hanja-readings.py --unihan "$d/Unihan.zip" --check   # 커밋본과 비교

버전 고정: 생성 시점(2026-10-12)에 unicode.org/Public에 공개된 최신 정식판이 18.0.0이다
(ucd/ReadMe.txt "final data files for version 18.0.0", Unihan.zip 2026-08-05). draft는 쓰지 않는다.
다른 해시의 zip은 --allow-unpinned 없이는 거절한다. 판을 올리면 버전과 해시를 함께 바꾸고 --check로 차이를 본다.

독음 고르기(UAX #38 rev. 41의 kHangul: 출처 0 = KS X 1001, 1 = KS X 1002, E = 한문 교육용 기초 한자,
N = 인명용 한자, X = 삭제된 K 출처. 값은 조합형 자모라 NFC로 합친다):
  1. 다른 독음의 두음법칙 형태(량 → 양)는 버린다. 앱이 실행 중에 다시 만든다.
  2. OVERRIDES에 있으면 그것을 쓴다. MERGED에 있으면 그 번체 글자의 독음을 쓴다.
  3. 남은 독음은 E 출처, 0 출처, 그 밖의 순서이고 같으면 먼저 적힌 것이다.
  4. 고른 독음에 E 출처가 없고 번체 변형(kTraditionalVariant와 kSimplifiedVariant의 역방향)이 있으면
     변형의 독음을 쓴다. 결과에 섞이는 간체는 중국어로 쓰인 것이라 번체의 뜻으로 읽는다
     (确은 KS X 1002의 '학'이 아니라 確 '확', 价는 '개'가 아니라 價 '가'). 변형끼리 독음이 다르면
     OVERRIDES나 E 출처인 변형, 0 출처인 변형, 먼저 적힌 변형 순으로 고르고 경고한다(恶 → 惡 '악').
  5. 그래도 없으면 의미·자형 변형(kSemanticVariant, kZVariant)이 모두 같은 독음일 때만 쓴다.
"""
import argparse
import hashlib
import io
import sys
import unicodedata
import zipfile
from pathlib import Path

UNICODE_VERSION = "18.0.0"
UNIHAN_SHA256 = "4c93ea9c1f636451729a840978f1667a53886af37ba854fdcce109721c63d43e"
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "DeepK" / "Translation" / "HanjaReadingData.swift"

# 표가 덮는 범위: 확장 A와 기본 블록. TranslationOutputLint.isHan과 같다.
RANGES = ((0x3400, 0x4DBF), (0x4E00, 0x9FFF))
ROW = 64

# 현대 한자어에서 가장 흔한 독음. 출처 순서로 고른 것과 다를 수 있어 직접 정한다.
OVERRIDES = {
    "樂": "락", "說": "설", "率": "률", "行": "행", "便": "편", "度": "도", "復": "복", "讀": "독",
    "參": "참", "宅": "택", "切": "절", "北": "북", "金": "금", "車": "차", "布": "포", "殺": "살",
    "省": "성", "識": "식", "惡": "악", "易": "역", "更": "경", "暴": "폭", "洞": "동", "狀": "상",
    "畫": "화", "見": "견", "降": "강", "數": "수", "索": "색", "否": "부", "不": "불",
}

# 간체 한 글자가 번체 여러 글자를 합친 경우, 중국어 결과에서 흔히 쓰는 쪽 번체 글자의 독음을 쓴다.
# 간체 자신의 kHangul(征 정, 于 우)이나 번체 변형 순서(么 → 幺 요)를 따르면 뜻이 다른 낱말이 되거나(特征 → 특정),
# 독음이 없다(净). 독음은 그 번체 글자의 kHangul에서 가져오며, 번체 글자에 독음이 없으면 생성이 실패한다.
#   征 → 徵 징(特征 특징), 于 → 於 어(关于 관어), 么 → 麽 마(什么 십마), 净 → 淨 정(干净 간정)
MERGED = {"征": "徵", "于": "於", "么": "麽", "净": "淨"}

# 생성 결과가 반드시 지켜야 하는 독음.
SANITY = {"确": "확", "保": "보", "点": "점", "量": "량", "不": "불", "李": "리", "征": "징", "于": "어", "么": "마", "净": "정"}

Y_VOWELS = {2, 3, 6, 7, 12, 17, 20}  # ㅑ ㅒ ㅕ ㅖ ㅛ ㅠ ㅣ

LICENSE = """\
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.
"""


def fail(message):
    print(f"generate-hanja-readings: {message}", file=sys.stderr)
    sys.exit(1)


def covered(code):
    return any(low <= code <= high for low, high in RANGES)


def word_initial(syllable):
    """한글 맞춤법 제10·12항의 두음법칙 형태(량 → 양, 락 → 낙, 녀 → 여)."""
    index = ord(syllable) - 0xAC00
    initial, vowel, final = index // 588, index % 588 // 28, index % 28
    if initial == 5:
        initial = 11 if vowel in Y_VOWELS else 2
    elif initial == 2 and vowel in Y_VOWELS:
        initial = 11
    return chr(0xAC00 + (initial * 21 + vowel) * 28 + final)


def records(archive, name):
    """(코드 포인트, 필드, 값). 머리말의 Unicode 버전도 함께 돌려준다."""
    version = None
    rows = []
    for line in archive.read(name).decode("utf-8").splitlines():
        if line.startswith("# Unicode Version "):
            version = line.removeprefix("# Unicode Version ").strip()
        if not line or line.startswith("#"):
            continue
        code, field, value = line.split("\t", 2)
        rows.append((int(code[2:], 16), field, value))
    return version, rows


def variant_targets(value):
    """"U+70B9 U+9EDE<kLau,kMatthews" 같은 값에서 코드 포인트만."""
    return [int(item.split("<", 1)[0][2:], 16) for item in value.split()]


def load(path, allow_unpinned):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        version, readings = records(archive, "Unihan_Readings.txt")
        _, variants = records(archive, "Unihan_Variants.txt")
    if (digest, version) != (UNIHAN_SHA256, UNICODE_VERSION):
        if not allow_unpinned:
            fail(f"고정한 Unihan {UNICODE_VERSION} ({UNIHAN_SHA256})이 아닙니다: {version} ({digest}). "
                 "판을 올리려면 --allow-unpinned로 확인한 뒤 UNICODE_VERSION과 UNIHAN_SHA256을 바꾸세요.")
        print(f"고정하지 않은 Unihan: version {version}, sha256 {digest}")

    hangul = {}
    for code, field, value in readings:
        if field != "kHangul":
            continue
        entries = []
        for item in value.split():
            jamo, sources = item.split(":")
            syllable = unicodedata.normalize("NFC", jamo)
            if len(syllable) != 1 or not 0xAC00 <= ord(syllable) <= 0xD7A3:
                fail(f"U+{code:04X}의 kHangul '{item}'이 한 음절로 합쳐지지 않습니다")
            entries.append((syllable, sources))
        hangul[code] = entries

    fields = {"kTraditionalVariant": {}, "kSimplifiedVariant": {}, "kSemanticVariant": {}, "kZVariant": {}}
    for code, field, value in variants:
        if field in fields:
            fields[field][code] = variant_targets(value)
    return version, digest, hangul, fields


def own_reading(code, hangul):
    """kHangul에서 고른 독음과 그 출처. 두음법칙 형태는 버린다."""
    entries = hangul.get(code)
    if not entries:
        return None
    syllables = {syllable for syllable, _ in entries}
    kept = [(index, syllable, sources) for index, (syllable, sources) in enumerate(entries)
            if not any(other != syllable and word_initial(other) == syllable for other in syllables)]

    def rank(entry):
        index, _, sources = entry
        return (0 if "E" in sources else 1 if "0" in sources else 2, index)

    _, syllable, sources = min(kept, key=rank)
    return syllable, sources


def direct_reading(code, hangul):
    override = OVERRIDES.get(chr(code))
    if override:
        return override
    own = own_reading(code, hangul)
    return own[0] if own else None


def source_rank(code, hangul):
    """변형끼리 독음이 다를 때 쓸 순위: OVERRIDES나 E 출처, 0 출처, 그 밖."""
    if chr(code) in OVERRIDES:
        return 0
    own = own_reading(code, hangul)
    sources = own[1] if own else ""
    return 0 if "E" in sources else 1 if "0" in sources else 2


def build(hangul, fields):
    simplified_of = {}
    for traditional, targets in fields["kSimplifiedVariant"].items():
        for target in targets:
            simplified_of.setdefault(target, []).append(traditional)

    for character, reading in OVERRIDES.items():
        listed = [syllable for syllable, _ in hangul.get(ord(character), [])]
        if reading not in listed:
            fail(f"OVERRIDES의 {character} {reading}이 kHangul {listed}에 없습니다")
        own = own_reading(ord(character), hangul)
        if own and own[0] != reading:
            print(f"override {character}: {own[0]} → {reading}")
    merged = {}
    for character, traditional in MERGED.items():
        reading = direct_reading(ord(traditional), hangul)
        if not reading:
            fail(f"MERGED의 {character} → {traditional}에 kHangul 독음이 없습니다")
        merged[ord(character)] = reading

    table = {}
    stats = {"kHangul": 0, "override": 0, "merged": 0, "traditional": 0, "traditional over own": 0, "split": 0, "semantic": 0}
    for low, high in RANGES:
        for code in range(low, high + 1):
            character = chr(code)
            if character in OVERRIDES:
                table[code] = OVERRIDES[character]
                stats["override"] += 1
                continue
            if code in merged:
                table[code] = merged[code]
                stats["merged"] += 1
                continue
            own = own_reading(code, hangul)
            if own and "E" in own[1]:
                table[code] = own[0]
                stats["kHangul"] += 1
                continue
            traditional = [target for target in fields["kTraditionalVariant"].get(code, []) if target != code]
            traditional += [target for target in sorted(simplified_of.get(code, [])) if target != code and target not in traditional]
            readable = [target for target in traditional if direct_reading(target, hangul)]
            if readable:
                chosen = direct_reading(min(readable, key=lambda target: (source_rank(target, hangul), readable.index(target))), hangul)
                table[code] = chosen
                stats["traditional"] += 1
                if own and own[0] != chosen:
                    stats["traditional over own"] += 1
                if len({direct_reading(target, hangul) for target in readable}) > 1:
                    stats["split"] += 1
                    listed = ", ".join(f"{chr(t)} {direct_reading(t, hangul) or '-'}" for t in traditional)
                    print(f"warning: {character} U+{code:04X} 번체 변형의 독음이 다릅니다({listed}) → {chosen}")
                continue
            if own:
                table[code] = own[0]
                stats["kHangul"] += 1
                continue
            others = [target for name in ("kSemanticVariant", "kZVariant") for target in fields[name].get(code, []) if target != code]
            readings = {direct_reading(target, hangul) for target in others}
            if len(readings) == 1 and None not in readings:
                table[code] = readings.pop()
                stats["semantic"] += 1

    for character, reading in SANITY.items():
        if table.get(ord(character)) != reading:
            fail(f"확인 실패: {character} → {table.get(ord(character))}, 기대 {reading}")
    return table, stats


def summary(stats):
    return (f"kHangul {stats['kHangul']}, OVERRIDES {stats['override']}, MERGED {stats['merged']}, "
            f"번체 변형 {stats['traditional']}(자기 독음 대신 {stats['traditional over own']}, 변형끼리 다름 {stats['split']}), "
            f"의미·자형 변형 {stats['semantic']}")


def render(version, digest, table, stats):
    rows = []
    for low, high in RANGES:
        for start in range(low, high + 1, ROW):
            rows.append(f"{start:04X}:" + "".join(table.get(code, ".") for code in range(start, start + ROW)))
    lines = [
        "// 이 파일은 scripts/generate-hanja-readings.py가 만든다. 직접 고치지 않는다.",
        f"// 원본: Unicode {version} Unihan.zip (SHA-256 {digest})",
        f"// 독음 {len(table)}자: {summary(stats)}",
        "//",
        "// Contains data derived from the Unicode Character Database (Unihan), used under the following license.",
        "//",
    ]
    lines += [f"// {line}".rstrip() for line in LICENSE.splitlines()]
    lines += [
        "",
        "/// 한자 → 한글 독음 표. `HanjaReading`이 처음 쓸 때 읽어 들인다.",
        "enum HanjaReadingData {",
        f"    static let unicodeVersion = \"{version}\"",
        "    /// 64 코드 포인트마다 한 줄이다. 줄 첫 코드 포인트의 16진수, 콜론, 코드 포인트마다 한 글자(한글 독음, 없으면 \".\").",
        "    /// U+3400–4DBF 다음에 U+4E00–9FFF가 온다.",
        "    static let rows = \"\"\"",
    ]
    lines += [f"        {row}" for row in rows]
    lines += ["        \"\"\"", "}", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Unihan kHangul로 HanjaReadingData.swift를 만든다.")
    parser.add_argument("--unihan", required=True, help="Unihan.zip 경로")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="생성할 Swift 파일")
    parser.add_argument("--check", action="store_true", help="쓰지 않고 커밋된 파일과 같은지만 확인한다")
    parser.add_argument("--allow-unpinned", action="store_true", help="고정하지 않은 판·해시를 허용하고 해시를 출력한다")
    args = parser.parse_args()

    version, digest, hangul, fields = load(args.unihan, args.allow_unpinned)
    table, stats = build(hangul, fields)
    source = render(version, digest, table, stats)
    print(f"{summary(stats)}, 합계 {len(table)}자, {len(source.encode())} bytes")

    out = Path(args.out)
    if args.check:
        if not out.exists() or out.read_text(encoding="utf-8") != source:
            fail(f"{out}이 Unihan {version}에서 생성한 결과와 다릅니다. --check 없이 다시 생성하세요.")
        print(f"{out}: 최신")
        return
    out.write_text(source, encoding="utf-8")
    print(f"{out}: 생성")


if __name__ == "__main__":
    main()
