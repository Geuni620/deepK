#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
@preconcurrency import libxml2

enum ClipboardImageReference: Sendable, Equatable {
    case embedded(Data)
    case remote(URL)
}

/// Reads the selected fragment only. HTML is parsed as data; no page, CSS, scripts or resources execute.
struct ClipboardImageSelection: Sendable {
    let references: [ClipboardImageReference]
    let unavailable: Int
    var containsImages: Bool { !references.isEmpty || unavailable > 0 }

    /// Image-object drags may also publish their resource URL as plain text. It is not document prose.
    func documentText(from plain: String) -> String {
        let resources = Set(references.compactMap { reference -> String? in
            if case .remote(let url) = reference { return url.absoluteString }; return nil
        })
        return plain.components(separatedBy: "\n").filter { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !resources.contains(value) && !value.lowercased().hasPrefix("data:image/")
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ html: String) -> Self {
        guard html.utf8.count <= 1 << 20 else { return Self(references: [], unavailable: 1) }
        var fragment = html
        if let start = html.range(of: "<!--StartFragment-->"), let end = html.range(of: "<!--EndFragment-->"), start.upperBound <= end.lowerBound {
            fragment = String(html[start.upperBound..<end.lowerBound])
        }
        let flags = HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue
        guard let document = fragment.withCString({ htmlReadMemory($0, Int32(fragment.utf8.count), nil, "UTF-8", Int32(flags)) }) else {
            return Self(references: [], unavailable: 0)
        }
        defer { xmlFreeDoc(document) }
        var references: [ClipboardImageReference] = [], seen = Set<String>(), unavailable = 0, visited = 0
        func attribute(_ node: xmlNodePtr, _ name: String) -> String? {
            let value = name.utf8CString.withUnsafeBufferPointer { buffer in
                buffer.baseAddress!.withMemoryRebound(to: xmlChar.self, capacity: buffer.count) { xmlGetProp(node, $0) }
            }
            guard let value else { return nil }
            defer { xmlFree(value) }
            return String(cString: value)
        }
        func add(_ raw: String) {
            let source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(source).inserted else { return }
            guard references.count < 8 else { unavailable += 1; return }
            if source.lowercased().hasPrefix("data:image/"), let comma = source.firstIndex(of: ","),
               source[..<comma].lowercased().hasSuffix(";base64"),
               let data = Data(base64Encoded: String(source[source.index(after: comma)...])), data.count <= 8_000_000 {
                references.append(.embedded(data))
            } else if let url = URL(string: source), MemoryImageDownload.permits(url) {
                references.append(.remote(url))
            } else { unavailable += 1 }
        }
        func walk(_ first: xmlNodePtr?, depth: Int) {
            guard depth < 100 else { return }
            var cursor = first
            while let node = cursor, visited < 12_000 {
                visited += 1; cursor = node.pointee.next
                guard node.pointee.type == XML_ELEMENT_NODE else { continue }
                let name = String(cString: node.pointee.name).lowercased()
                guard !["script", "style", "template", "iframe", "object", "input", "textarea", "select", "noscript"].contains(name) else { continue }
                let style = attribute(node, "style") ?? ""
                let visibility = style.split(separator: ";").reduce(into: [String: String]()) { result, declaration in
                    let pair = declaration.split(separator: ":", maxSplits: 1)
                    guard pair.count == 2 else { return }
                    result[pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = pair[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                // ARIA controls accessibility, not visible pixels. Match CSS property names exactly;
                // backface-visibility:hidden must never be mistaken for visibility:hidden.
                guard attribute(node, "hidden") == nil,
                      visibility["display"] != "none", visibility["visibility"] != "hidden", visibility["visibility"] != "collapse" else { continue }
                if name == "img", let source = attribute(node, "src"), !source.isEmpty { add(source) }
                // X uses a non-selectable IMG over a selectable DIV with this inline CSS property.
                if let regex = try? NSRegularExpression(pattern: #"(?i)(?:^|;)\s*background-image\s*:\s*url\(\s*(?:"([^"]+)"|'([^']+)'|([^\s)]+))\s*\)"#) {
                    let value = style as NSString
                    for match in regex.matches(in: style, range: NSRange(location: 0, length: value.length)) {
                        if let range = (1...3).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) { add(value.substring(with: range)) }
                    }
                }
                walk(node.pointee.children, depth: depth + 1)
            }
        }
        walk(document.pointee.children, depth: 0)
        return Self(references: references, unavailable: unavailable)
    }

    func load(fetch: @Sendable (URL) async throws -> POCImage = MemoryImageDownload.fetch) async throws -> POCImage {
        guard unavailable == 0, !references.isEmpty else {
            throw ImagePOCError.message("일부 이미지 주소를 안전하게 읽지 못했습니다. 현재 자동 불러오기는 X 이미지와 복사된 이미지 데이터를 지원합니다.")
        }
        var images: [POCImage] = []
        for reference in references {
            try Task.checkCancellation()
            switch reference {
            case .embedded(let data): images.append(try POCImage.decode(data, name: "선택한 이미지"))
            case .remote(let url): images.append(try await fetch(url))
            }
        }
        return try stack(images)
    }

    private func stack(_ images: [POCImage]) throws -> POCImage {
        if images.count == 1 { return images[0] }
        let width = images.map { $0.pixels.width }.max() ?? 0
        let height = images.reduce(0) { $0 + $1.pixels.height }
        guard width > 0, height > 0, width * height <= 12_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImagePOCError.message("선택한 이미지가 너무 큽니다. 구간을 나누어 선택해 주세요.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = height
        for image in images {
            y -= image.pixels.height
            context.draw(image.pixels, in: CGRect(x: 0, y: y, width: image.pixels.width, height: image.pixels.height))
        }
        return POCImage(pixels: context.makeImage()!, name: "선택한 이미지 \(images.count)개")
    }
}

/// Bounded, memory-only image GET. Automatic fetching is limited to the observed X image CDN.
final class MemoryImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    static func permits(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "pbs.twimg.com" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func fetch(_ url: URL) async throws -> POCImage {
        guard permits(url) else { throw ImagePOCError.message("지원하지 않는 이미지 주소입니다.") }
        let download = MemoryImageDownload()
        let bytes = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in download.start(url, continuation: continuation) }
        } onCancel: { download.cancel() }
        try Task.checkCancellation()
        return try POCImage.decode(bytes, name: "X에서 선택한 이미지")
    }
    private func start(_ url: URL, continuation: CheckedContinuation<Data, Error>) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url); request.setValue("image/*", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        let wasCancelled = lock.withLock { self.continuation = continuation; self.session = session; self.task = task; return cancelled }
        if wasCancelled { finish(.failure(CancellationError())) } else { task.resume() }
    }
    private func cancel() { lock.withLock { cancelled = true }; finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Data, Error>) {
        let state = lock.withLock { () -> (CheckedContinuation<Data, Error>?, URLSession?) in
            let state = (continuation, session); continuation = nil; session = nil; task = nil; data = Data(); return state
        }
        state.0?.resume(with: result); state.1?.invalidateAndCancel()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true, response.expectedContentLength <= 8_000_000 else {
            completionHandler(.cancel); finish(.failure(ImagePOCError.message("원본 이미지 서버에서 이미지를 읽지 못했습니다."))); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        let overflow = lock.withLock { () -> Bool in
            guard continuation != nil else { return false }
            if data.count + bytes.count > 8_000_000 { return true }; data.append(bytes); return false
        }
        if overflow { finish(.failure(ImagePOCError.message("외부 이미지는 8MB 이하만 읽습니다."))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) } else { finish(.success(lock.withLock { data })) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.permits) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
#endif
