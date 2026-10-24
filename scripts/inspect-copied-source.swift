import Foundation

/// 복사 캡처 폴더의 `<name>.txt`·`<name>.html` 쌍마다 앱의 복사 가져오기(수식 정리 포함)를 돌려 정리본, 모델 입력,
/// 코드 블록, 링크, 칩과 가져오기 보고를 출력한다. 요청을 보내지 않고 파일을 쓰지 않는다.
/// usage: inspect-copied-source <dir>
@main
struct InspectCopiedSource {
    static func main() throws {
        guard let path = CommandLine.arguments.dropFirst().first else {
            FileHandle.standardError.write(Data("usage: inspect-copied-source <dir>\n".utf8))
            exit(64)
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
        for name in names {
            let plain = try String(contentsOf: directory.appendingPathComponent(name + ".txt"), encoding: .utf8)
            let html = try? String(contentsOf: directory.appendingPathComponent(name + ".html"), encoding: .utf8)
            print("== \(name)")
            // 앱(copiedSource)처럼 수식 정리가 글을 바꾸면 구조 없이 번역하고, 4,000자를 넘으면 파싱하지 않는다.
            let normalized = CopiedMathNormalizer.normalize(plain: plain, html: html).text
            if normalized != plain { print("수식 정리로 글이 바뀜: 앱은 구조 없이 번역한다") }
            if plain.count > 4_000 { print("4,000자 초과(\(plain.count)자): 앱은 파싱하지 않는다") }
            let (source, report) = RichSourceImporter.captureWithReport(plain: plain, html: html)
            print("보고: misses \(report.misses)/\(report.budget), 꾸밈 일치 \(report.chromeMatched) 없음 \(report.chromeSkipped), "
                  + "지운 줄 \(report.removedLines)(언어 라벨 \(report.labelLines)), 정리 포기 \(report.cleaningAbandoned), "
                  + "펜스 \(report.fences), 인라인 \(report.inline.isEmpty ? "-" : report.inline), 대체 \(report.fallback ?? "-")")
            for block in report.blocks { print("  <pre> \(block.language ?? "언어 없음"): \(block.reason)") }
            print("지운 부분: \(source.removed.map { (plain as NSString).substring(with: $0) })")
            if let markup = source.markup {
                for block in markup.blocks {
                    print("블록 \(block.language ?? "맨 펜스")\(block.title.map { " 제목 \($0.debugDescription)" } ?? ""): \(block.code.debugDescription)")
                }
                for link in markup.links { print("링크 \(link.text.debugDescription) → \(link.url.absoluteString)") }
                print("칩: \(markup.code.sorted())")
            }
            print("--- 정리본")
            print(source.plain)
            print("--- 모델 입력")
            print(source.markup?.text ?? "(정리본 그대로)")
            print()
        }
    }
}
