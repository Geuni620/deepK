import Foundation

/// 픽스처는 직접 쓴 글(scripts/math-copy/page.mjs)을 Chrome 154 헤드리스에서 ⌘C로 복사한
/// text/plain과 text/html이다. macOS Chrome처럼 HTML 앞에 `<meta charset='utf-8'>`를 붙였다.
@main
struct CopiedMathNormalizerTests {
    typealias Normalizer = CopiedMathNormalizer

    static func main() {
        repairsKaTeXArticle()
        keepsUnmatchedFormulasRaw()
        keepsOtherCopiesIdentical()
        isDeterministic()
        respectsHTMLSizeLimit()
        neverLosesWordsOrReturnsEmpty()
        refusesAmbiguousShortLines()
        matchesEachLineOncePerTokenList()
        requiresScreenGlyphsInHTML()
        keepsLineBreaksAroundFormulas()
        groupsScriptsAndFunctionNames()
        print("CopiedMathNormalizerTests passed")
    }

    private static let article = """
    1. Recipes Scale by ×k, Pans by k²
    A loaf needs 500 g of flour and 10 g of salt. To bake for a crowd you multiply every line by the same factor (k), so k = 3 gives 1500 g and 30 g.

    Bakers keep the dough ratio w/f fixed, where w is water and f is flour. A ratio of 13/20 is a soft dough; anything above 4/5 is closer to batter.

    A round pan of radius r holds πr² of batter per centimetre of depth, so a pan twice as wide needs four times the dough. Its diameter is d = 2√(A/π), and going the other way, the radius for a target area A is

    r = √(A/π)
    With several pans p_1, …, p_n the total area is ∑_(i=1)^n πr_i², and the scale factor is that sum divided by the area of the original pan:

    k = (1/A_0) ∑_(i=1)^n πr_i²
    If batch i uses i cups, the first n batches use ∑_(i=1)^n i = (n(n + 1))/2 cups in total.

    Two flours can be tracked per batch as a grid (300, 200; 450, 300) with one row per batch, and scaling only the second batch is the matrix

    S = (1, 0; 0, k)
    x marks the starting weight in this paragraph, and t in minutes keeps its label as text, and a pan tilted by θ fills to a depth of h cos θ along its wall.

    Proofing time does not scale with the batch size, which is the one rule that surprises most home bakers.
    """

    private static func repairsKaTeXArticle() {
        let copy = fixture("katex-article")
        let result = Normalizer.normalize(plain: copy.plain, html: copy.html)
        require(result.text == article, "inline, heading, display, fraction, script, sum and matrix formulas become one line each")
        require(result.formulas == 31, "every formula in the article is repaired")
    }

    private static func keepsUnmatchedFormulasRaw() {
        // 첫 수식의 화면 글자 중간에서 시작한 선택: HTML에 그 수식의 MathML이 없어 남은 "g"를 그대로 둔다.
        let partial = fixture("katex-partial")
        let result = Normalizer.normalize(plain: partial.plain, html: partial.html)
        require(result.text == "g of flour and 10 g of salt. To bake for a crowd you multiply every line by the same factor (k), so k = 3 gives 1500 g and 30 g.",
                "a selection starting inside a formula keeps its remains")
        require(result.formulas == 5, "the formulas after the cut are repaired")

        // 화면 글자가 토큰과 다른 수식은 원래 줄을 그대로 두고, 나머지 수식은 정리한다.
        let copy = fixture("katex-article")
        let broken = "A ratio of \n13\n20\n21\n13\n\u{200B}\n  is a soft dough"
        let plain = copy.plain.replacingOccurrences(of: "A ratio of \n13\n20\n20\n13\n\u{200B}\n  is a soft dough", with: broken)
        require(plain != copy.plain, "the echo was altered")
        let mismatched = Normalizer.normalize(plain: plain, html: copy.html)
        require(mismatched.text == article.replacingOccurrences(of: "A ratio of 13/20 is a soft dough", with: broken), "an unmatched echo stays raw")
        require(mismatched.formulas == 30, "only the unmatched formula is skipped")
    }

    private static func keepsOtherCopiesIdentical() {
        // copy-tex는 HTML에 katex-mathml이 남지만 text/plain에 토큰 줄이 없다.
        for name in ["copytex-article", "mathml-article", "mathjax3-article", "control"] {
            let copy = fixture(name)
            requireIdentical(Normalizer.normalize(plain: copy.plain, html: copy.html), copy.plain, name)
        }
        let katex = fixture("katex-article")
        requireIdentical(Normalizer.normalize(plain: katex.plain, html: nil), katex.plain, "a copy without HTML")
        requireIdentical(Normalizer.normalize(plain: fixture("control").plain, html: katex.html), fixture("control").plain,
                         "text that does not contain the HTML formulas")
        requireIdentical(Normalizer.normalize(plain: "  \n\t", html: katex.html), "  \n\t", "whitespace-only text")
    }

    private static func isDeterministic() {
        let copy = fixture("katex-article")
        let first = Normalizer.normalize(plain: copy.plain, html: copy.html)
        let second = Normalizer.normalize(plain: copy.plain, html: copy.html)
        require(first.text.utf8.elementsEqual(second.text.utf8), "the same copy always gives the same bytes")
        requireIdentical(Normalizer.normalize(plain: first.text, html: copy.html), first.text, "normalized text has no formula lines left")
    }

    private static func respectsHTMLSizeLimit() {
        let copy = fixture("katex-article")
        let padded = copy.html + String(repeating: " ", count: Normalizer.maximumHTMLBytes)
        requireIdentical(Normalizer.normalize(plain: copy.plain, html: padded), copy.plain, "HTML over the limit is ignored")
    }

    private static func neverLosesWordsOrReturnsEmpty() {
        let n = katexHTML(#"<mrow><mi>n</mi></mrow>"#, screen: "n")
        require(Normalizer.normalize(plain: "Set \nn\nn to one.", html: n).text == "Set n to one.", "a single-letter formula joins its sentence")
        // 수식 뒤 글자가 붙어 단어가 바뀌면 정리하지 않는다.
        requireIdentical(Normalizer.normalize(plain: "Set \nn\nnabc to one.", html: n), "Set \nn\nnabc to one.", "a glued word")

        // 선택 전체가 디스플레이 수식이어도 빈 글이 되지 않는다(shud.in 2절의 근호).
        let propto = katexHTML(#"<mrow><mi>T</mi><mo>∝</mo><msqrt><mrow><mi>L</mi><mi mathvariant="normal">/</mi><mi>g</mi></mrow></msqrt></mrow>"#,
                               screen: "T∝L/g\u{200B}", display: true)
        let display = Normalizer.normalize(plain: "T\n∝\nL\n/\ng\nT∝ \nL/g\n\u{200B}\n ", html: propto)
        require(display.text == "T ∝ √(L/g)" && display.formulas == 1, "a lone display formula becomes its linear form")
    }

    private static func refusesAmbiguousShortLines() {
        // 코드 블록의 "1\n1", 제목 "A", 목록 "x"도 한 글자 수식과 똑같이 맞는다. 그런 줄은 그대로 두고,
        // 같은 토큰의 수식은 어느 자리인지 알 수 없어 원래 글자로 남긴다. 뒤 수식이 앞 수식 자리를 가져가지 않는다.
        let copy = fixture("katex-code")
        let result = Normalizer.normalize(plain: copy.plain, html: copy.html)
        require(result.text == """
        The program prints the first Fibonacci numbers:

        1
        1
        2
        3
        5
        8
        Each term after \n1\n1 is the sum of the two before it, so the sixth is 8.

        A
        A short section about sets: the set S = {1, 2} has size 2, and \nA\nA is any subset.

        x
        x-axis label shown below the chart
        The speed is v = d/t and the kinetic energy is (1/2)mv², where \nx\nx is the position.
        """, "code, heading and list lines stay; formulas that share their tokens stay raw")
        require(result.formulas == 5, "the unambiguous formulas are repaired")
    }

    private static func matchesEachLineOncePerTokenList() {
        // 맞지 않는 같은 수식이 많아도 줄마다 한 번만 맞춰 본다(512KB 근처에서 수식마다 다시 맞추면 수백 ms가 걸렸다).
        let count = 1200
        let formula = #"<mrow><mi>z</mi><mo>+</mo><mi>w</mi></mrow>"#
        let html = String(repeating: katexHTML(formula, screen: "z+w"), count: count + 1)
        let unmatched = (0..<count).map { "Step \($0): \nz\n+\nw\nz+v here." }.joined(separator: "\n\n")
        let result = Normalizer.normalize(plain: unmatched + "\n\nLast: \nz\n+\nw\nz+w end.", html: html)
        require(result.text == unmatched + "\n\nLast: z + w end." && result.formulas == 1, "only the formula whose echo matches is repaired")
    }

    private static func requiresScreenGlyphsInHTML() {
        // \widehat·\widetilde·\overrightarrow는 악센트를 SVG로 그려 화면 글자에 없다. 뒤 글의 ^ ~ →를
        // 화면 글자로 삼키지 않도록 그 수식은 원래 글자로 둔다.
        let accents = fixture("katex-accents")
        let result = Normalizer.normalize(plain: accents.plain, html: accents.html)
        require(result.text == accents.plain.replacingOccurrences(of: "then \nz\nz follows.", with: "then z follows.") && result.formulas == 1,
                "formulas with SVG accents stay raw and the prose ^ ~ → remain")

        // 숨은 MathML의 "+"에서 시작한 선택: <math>는 잘렸지만 화면 글자는 온전하다.
        let cut = fixture("katex-cut")
        requireIdentical(Normalizer.normalize(plain: cut.plain, html: cut.html), cut.plain, "a selection starting inside the hidden MathML")
    }

    private static func keepsLineBreaksAroundFormulas() {
        // 수식 뒤의 <pre> 코드 줄, pre-wrap의 줄바꿈, <br>은 Chrome이 MathML 줄바꿈과 하나로 써도 원래 글의 줄바꿈이다.
        // <kbd>, <img>, <wbr> 같은 인라인 요소는 줄을 나누지 않으므로 수식을 뒤 문장에 잇는다.
        let copy = fixture("katex-breaks")
        let result = Normalizer.normalize(plain: copy.plain, html: copy.html)
        require(result.text == """
        Compute the ratio a/b
            ratio = a / b
        Step one is done. \np is the next value.
        Then (\nq) follows, and the value is w
          indented second line
        Line one
        u is next
        and (\ny) end.

        Press x² Enter to square, the value c/d  is shown, and v²is the square.
        """, "real line breaks before and after formulas stay")
        require(result.formulas == 9, "every formula is repaired")
    }

    private static func groupsScriptsAndFunctionNames() {
        // 함수 이름이 첨자의 밑이면 "(log )_2n"이 되고, 첨자 뒤 항이 붙거나 여러 글자 위첨자가 풀려 뜻이 바뀌었다.
        let copy = fixture("katex-linear")
        let result = Normalizer.normalize(plain: copy.plain, html: copy.html)
        let items = ["e^(iπ) + 1 = 0", "A^T A", "log_2 n", "x^(ab)", "sin² x", "cos² θ + sin² θ = 1", "max_i x_i", "u_n v_n", "∑_i a_i b_i",
                     "(x − x_0)² + (y − y_0)² = r²", "(1 + r_t)^n", "∥w − w*∥²"]
        let expected = items.map { "Item \($0) end." }.joined(separator: "\n\n")
            + "\n\nThe largest is\n\nmax_i x_i\nThe limit is\n\nlim_(x→0)((sin x)/x) = 1"
        require(result.text == expected, "scripts and function names keep their grouping")
        require(result.formulas == 14, "every formula is repaired")
    }

    private static func katexHTML(_ mathML: String, screen: String = "", display: Bool = false) -> String {
        let math = #"<math xmlns="http://www.w3.org/1998/Math/MathML"\#(display ? #" display="block""# : "")><semantics>\#(mathML)</semantics></math>"#
        return #"<meta charset='utf-8'><span class="katex"><span class="katex-mathml">\#(math)</span><span class="katex-html" aria-hidden="true">\#(screen)</span></span>"#
    }

    private static func fixture(_ name: String) -> (plain: String, html: String) {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("DeepKTests/Fixtures/MathCopy")
        guard let plain = try? String(contentsOf: directory.appendingPathComponent("\(name).txt"), encoding: .utf8),
              let html = try? String(contentsOf: directory.appendingPathComponent("\(name).html"), encoding: .utf8)
        else { fatalError("CopiedMathNormalizerTests: missing fixture \(name); run from the project root") }
        return (plain, html)
    }

    private static func requireIdentical(_ result: (text: String, formulas: Int), _ plain: String, _ message: String) {
        require(result.text.utf8.elementsEqual(plain.utf8) && result.formulas == 0, "byte-identical: \(message)")
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, "CopiedMathNormalizerTests: \(message)")
    }
}
