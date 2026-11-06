#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
@preconcurrency import libxml2

enum ClipboardImageReference: Sendable, Equatable, Hashable {
    case embedded(Data)
    case remote(URL)
}

struct ClipboardSelectedImage: Sendable {
    let id: Int
    let reference: ClipboardImageReference?
    let inlineSize: CGSize?
    let textPrefix: String
}

struct ClipboardImageLoad: @unchecked Sendable {
    var images: [POCImage] = []
    var icons: [SelectionInlineImage] = []
    var failedImages = 0
    var failedIcons = 0
}

/// HTML is parsed as inert data. Resource addresses and placement never enter provider input.
struct ClipboardImageSelection: Sendable {
    let items: [ClipboardSelectedImage]
    let overflow: Int
    let resourceText: Set<String>
    var references: [ClipboardImageReference] {
        var seen = Set<ClipboardImageReference>()
        return items.compactMap(\.reference).filter { seen.insert($0).inserted }
    }
    var unavailable: Int { overflow + items.filter { $0.reference == nil }.count }
    var containsImages: Bool { !items.isEmpty || overflow > 0 }

    func documentText(from plain: String) -> String {
        plain.components(separatedBy:"\n").filter {
            let text = $0.trimmingCharacters(in:.whitespacesAndNewlines)
            return !resourceText.contains(text) && !text.lowercased().hasPrefix("data:image/")
        }.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
    }
    func inlinePlaceholders(in plain: String) -> [SelectionInlineImage] {
        items.compactMap { item in
            guard let size = item.inlineSize else { return nil }
            return SelectionInlineImage(id:item.id,offset:Self.offset(after:item.textPrefix,in:plain),size:size,pixels:nil)
        }
    }
    private static func offset(after prefix: String, in plain: String) -> Int {
        let wanted = prefix.filter { !$0.isWhitespace }
        guard !wanted.isEmpty else { return 0 }
        var compact = "", offsets: [Int] = []
        var position = 0
        for char in plain {
            position += String(char).utf16.count
            if !char.isWhitespace { compact.append(char);offsets.append(position) }
        }
        func includingTrailingSpace(_ end:Int) -> Int {
            guard prefix.last?.isWhitespace == true else { return end }
            let value = plain as NSString
            var position = end
            while position < value.length,let scalar = UnicodeScalar(value.character(at:position)),CharacterSet.whitespacesAndNewlines.contains(scalar) { position += 1 }
            return position
        }
        if compact.hasPrefix(wanted), wanted.count <= offsets.count { return includingTrailingSpace(offsets[wanted.count-1]) }
        let suffix = String(wanted.suffix(80))
        guard let range = compact.range(of:suffix) else { return 0 }
        let end = compact.distance(from:compact.startIndex,to:range.upperBound)
        return end > 0 && end <= offsets.count ? includingTrailingSpace(offsets[end-1]) : 0
    }

    static func parse(_ html: String, sourceURL: URL? = nil) -> Self {
        guard html.utf8.count <= 1 << 20 else { return Self(items:[],overflow:1,resourceText:[]) }
        var fragment = html
        if let start = html.range(of:"<!--StartFragment-->"),let end = html.range(of:"<!--EndFragment-->"),start.upperBound <= end.lowerBound {
            fragment = String(html[start.upperBound..<end.lowerBound])
        }
        let flags = HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue
        guard let doc = fragment.withCString({ htmlReadMemory($0,Int32(fragment.utf8.count),nil,"UTF-8",Int32(flags)) }) else {
            return Self(items:[],overflow:0,resourceText:[])
        }
        defer { xmlFreeDoc(doc) }
        var items: [ClipboardSelectedImage] = [], overflow = 0, visited = 0, prefix = ""
        var resources = Set<String>(), seenContent = Set<String>()
        func attribute(_ node:xmlNodePtr,_ key:String) -> String? {
            let value = key.utf8CString.withUnsafeBufferPointer { buffer in buffer.baseAddress!.withMemoryRebound(to:xmlChar.self,capacity:buffer.count) { xmlGetProp(node,$0) } }
            guard let value else { return nil };defer { xmlFree(value) };return String(cString:value)
        }
        func dimension(_ value:String?) -> CGFloat? {
            guard let value else { return nil }
            let clean = value.lowercased().trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"px",with:"")
            guard let number = Double(clean),number.isFinite,number >= 0 else { return nil };return CGFloat(number)
        }
        func add(_ raw:String,inline:CGSize?) {
            let source = raw.trimmingCharacters(in:.whitespacesAndNewlines)
            resources.insert(source)
            if inline == nil && !seenContent.insert(source).inserted { return }
            guard items.count < 24 else { overflow += 1;return }
            var reference: ClipboardImageReference?
            if source.lowercased().hasPrefix("data:image/"),let comma = source.firstIndex(of:","),
               source[..<comma].lowercased().hasSuffix(";base64"),let data = Data(base64Encoded:String(source[source.index(after:comma)...])),data.count <= 8_000_000 {
                reference = .embedded(data)
            } else {
                let base = sourceURL.flatMap { $0.scheme?.lowercased() == "https" && $0.user == nil && $0.password == nil ? $0 : nil }
                if let url = URL(string:source,relativeTo:base)?.absoluteURL,MemoryImageDownload.permits(url) {
                    resources.insert(url.absoluteString);reference = .remote(url)
                }
            }
            items.append(.init(id:items.count,reference:reference,inlineSize:inline,textPrefix:prefix))
        }
        func walk(_ first:xmlNodePtr?,depth:Int) {
            guard depth < 100 else { return }
            var cursor = first
            while let node = cursor,visited < 12_000 {
                cursor = node.pointee.next;visited += 1
                if node.pointee.type == XML_TEXT_NODE {
                    if let text = node.pointee.content { prefix += String(cString:text) }
                    continue
                }
                guard node.pointee.type == XML_ELEMENT_NODE else { continue }
                let name = String(cString:node.pointee.name).lowercased()
                guard !["script","style","template","iframe","object","input","textarea","select","noscript"].contains(name) else { continue }
                let style = attribute(node,"style") ?? ""
                let css = style.split(separator:";").reduce(into:[String:String]()) { values,declaration in
                    let pair = declaration.split(separator:":",maxSplits:1);guard pair.count == 2 else { return }
                    values[pair[0].trimmingCharacters(in:.whitespacesAndNewlines).lowercased()] = pair[1].replacingOccurrences(of:"!important",with:"").trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                }
                guard attribute(node,"hidden") == nil,css["display"] != "none",css["visibility"] != "hidden",css["visibility"] != "collapse" else { continue }
                let width = css["width"] != nil ? dimension(css["width"]) : dimension(attribute(node,"width"))
                let height = css["height"] != nil ? dimension(css["height"]) : dimension(attribute(node,"height"))
                // Only explicit zero geometry is skipped. Missing geometry is not a zero-size image.
                if width == 0 || height == 0 { continue }
                let parent = node.pointee.parent.flatMap { $0.pointee.name }.map { String(cString:$0).lowercased() } ?? ""
                let inlineContext = ["span","p","a","em","strong","b","i","label"].contains(parent) || ["inline","inline-block"].contains(css["display"] ?? "")
                let inline: CGSize?
                if let width,let height,width > 0,height > 0,width <= 24,height <= 24,inlineContext {
                    inline = CGSize(width:width,height:height)
                } else { inline = nil }
                if name == "img",let src = attribute(node,"src"),!src.isEmpty { add(src,inline:inline) }
                if let expression = try? NSRegularExpression(pattern:#"(?i)(?:^|;)\s*background-image\s*:\s*url\(\s*(?:"([^"]+)"|'([^']+)'|([^\s)]+))\s*\)"#) {
                    let value = style as NSString
                    for match in expression.matches(in:style,range:NSRange(location:0,length:value.length)) {
                        if let range = (1...3).map({match.range(at:$0)}).first(where:{$0.location != NSNotFound}) { add(value.substring(with:range),inline:inline) }
                    }
                }
                walk(node.pointee.children,depth:depth+1)
                if ["p","div","br","li","h1","h2","h3"].contains(name) { prefix += "\n" }
            }
        }
        walk(doc.pointee.children,depth:0)
        return Self(items:items,overflow:overflow,resourceText:resources)
    }

    func loadReport(plain:String,fetch:@Sendable (URL) async throws -> POCImage = MemoryImageDownload.fetch) async throws -> ClipboardImageLoad {
        var result = ClipboardImageLoad(),cache: [ClipboardImageReference:POCImage] = [:]
        result.failedImages = overflow
        var contentWidth = 0,contentHeight = 0
        for item in items {
            try Task.checkCancellation()
            var image: POCImage?
            if let reference = item.reference {
                do {
                    if let cached = cache[reference] { image = cached }
                    else {
                        switch reference {
                        case .embedded(let bytes): image = try POCImage.decode(bytes,name:"선택한 이미지")
                        case .remote(let url): image = try await fetch(url)
                        }
                        cache[reference] = image
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {}
            }
            if let size = item.inlineSize {
                result.icons.append(.init(id:item.id,offset:Self.offset(after:item.textPrefix,in:plain),size:size,pixels:image?.pixels))
                if image == nil { result.failedIcons += 1 }
            } else if let image {
                let width = max(contentWidth,image.pixels.width),height = contentHeight + image.pixels.height
                if result.images.count < 8,width * height <= 12_000_000 {
                    result.images.append(image);contentWidth = width;contentHeight = height
                } else { result.failedImages += 1 }
            } else { result.failedImages += 1 }
        }
        return result
    }
    func load(fetch:@Sendable (URL) async throws -> POCImage = MemoryImageDownload.fetch) async throws -> POCImage {
        let report = try await loadReport(plain:"",fetch:fetch)
        return try Self.stack(report.images)
    }
    static func stack(_ images:[POCImage]) throws -> POCImage {
        guard !images.isEmpty else { throw ImagePOCError.message("읽을 수 있는 본문 이미지가 없습니다.") }
        if images.count == 1 { return images[0] }
        let width = images.map { $0.pixels.width }.max()!,height = images.reduce(0) { $0 + $1.pixels.height }
        guard width * height <= 12_000_000,let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImagePOCError.message("이미지 표시 공간을 준비하지 못했습니다.")
        }
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
        var y = height
        for image in images { y -= image.pixels.height;context.draw(image.pixels,in:CGRect(x:0,y:y,width:image.pixels.width,height:image.pixels.height)) }
        return POCImage(pixels:context.makeImage()!,name:"선택한 본문 이미지")
    }
}

/// Bounded, memory-only image GET. Fetching is limited to explicitly observed public image hosts.
final class MemoryImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    static func permits(_ url: URL) -> Bool {
        let hosts: Set<String> = [
            "pbs.twimg.com", "cdn.bsky.app", "ogcard.cdn.bsky.app", "github.com", "camo.githubusercontent.com",
            "raw.githubusercontent.com", "private-user-images.githubusercontent.com", "media.githubusercontent.com",
            "developer.apple.com", "docs.docker.com", "docs.github.com", "docusaurus.io", "kubernetes.io",
            "lh3.googleusercontent.com", "nextjs.org", "react.dev", "sponsors.vite.dev", "storage.googleapis.com",
            "tailwindcss.com", "www.notion.com", "haeinjung.com"
        ]
        return url.scheme?.lowercased() == "https" && url.host.map { hosts.contains($0.lowercased()) } == true &&
            url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func fetch(_ url: URL) async throws -> POCImage {
        guard permits(url) else { throw ImagePOCError.message("지원하지 않는 이미지 주소입니다.") }
        let download = MemoryImageDownload()
        let bytes = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in download.start(url, continuation: continuation) }
        } onCancel: { download.cancel() }
        try Task.checkCancellation()
        return try POCImage.decode(bytes, name: "선택한 이미지")
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
