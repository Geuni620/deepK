import AppKit

/// 일반 클립보드를 읽기만 해서 타입·크기를 출력하고 `.string`과 `public.html`을 파일로 저장한다.
/// 웹 수식 복사와 코드 블록 복사(scripts/inspect-copied-source.sh로 읽음) 확인용이다. 클립보드에 쓰지 않는다.
/// usage: swift scripts/dump-pasteboard.swift <output-dir> [name]
let arguments = CommandLine.arguments.dropFirst()
guard let directory = arguments.first else {
    FileHandle.standardError.write(Data("usage: swift scripts/dump-pasteboard.swift <output-dir> [name]\n".utf8))
    exit(64)
}
let name = arguments.dropFirst().first ?? "capture"
let output = URL(fileURLWithPath: directory, isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let pasteboard = NSPasteboard.general
let changeCount = pasteboard.changeCount
print("changeCount: \(changeCount)")
for (index, item) in (pasteboard.pasteboardItems ?? []).enumerated() {
    print("item \(index)")
    for type in item.types { print("  \(type.rawValue): \(item.data(forType: type)?.count ?? 0) bytes") }
}

let text = pasteboard.string(forType: .string)
let html = pasteboard.string(forType: .html)
guard pasteboard.changeCount == changeCount else {
    FileHandle.standardError.write(Data("클립보드가 읽는 중에 바뀌었습니다. 다시 실행하세요.\n".utf8))
    exit(1)
}
if let text { try text.write(to: output.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8) }
if let html { try html.write(to: output.appendingPathComponent("\(name).html"), atomically: true, encoding: .utf8) }

func count(_ needle: String, in haystack: String?) -> Int { (haystack?.components(separatedBy: needle).count ?? 1) - 1 }
print("string: \(text.map { "\($0.utf16.count) UTF-16" } ?? "없음")")
print("html: \(html.map { "\($0.utf16.count) UTF-16" } ?? "없음")")
print("html 시작: \(html.map { String($0.prefix(60)).debugDescription } ?? "-")")
for marker in ["<math", "katex-mathml", "katex-html", "application/x-tex", "<msqrt", "mjx-container", "data-latex"] {
    print("  \(marker): \(count(marker, in: html))")
}
// 코드 블록과 페이지 조작 글자(탭·선택된 탭·복사 버튼·줄 번호·화면 낭독기용 글자)의 근거.
for marker in ["<pre", "<code", "<button", "role=\"tab", "aria-selected=\"true\"", "aria-pressed=\"true\"", "data-state=\"active\"",
               "role=\"button\"", "role=\"status\"", "aria-hidden=\"true\"", "data-language",
               "class=\"language-", "sr-only", "visually-hidden", "clip-path", "clip: rect", "user-select: none", "lineno"] {
    print("  \(marker): \(count(marker, in: html))")
}
print("string의 U+200B 줄: \(text?.split(separator: "\n", omittingEmptySubsequences: false).filter { $0 == "\u{200B}" }.count ?? 0)")
print("저장 위치: \(output.path)")
