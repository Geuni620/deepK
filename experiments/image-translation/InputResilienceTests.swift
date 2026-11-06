#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import SwiftUI

@MainActor enum InputResilienceTests {
    actor Probe {
        var payloads: [String] = []
        func add(_ value:String) { payloads.append(value) }
    }
    static func run() async throws {
        let image = POCFixtures.sample()
        let png = NSBitmapImageRep(cgImage:image.pixels).representation(using:.png,properties:[:])!.base64EncodedString()
        let plain = "Hello, my name is Morgan.\n\nPlease check the platform before boarding."
        let first = "<p>Hello, my name is ",last = "Morgan.</p><p>Please check the platform before boarding.</p>"
        let icon = "<img src='data:image/png;base64,\(png)' width='18' height='18'>"
        let source = URL(string:"https://raw.githubusercontent.com/Geuni620/deepK/main/README.md")!
        let input = NativeImageInput(),probe = Probe()
        let host = NSHostingView(rootView:HStack(spacing:1) {
            NativeImageSource(input:input).frame(width:499)
            NativeImageResult(input:input).frame(width:499)
        }.background(Color.white).environment(\.colorScheme,.light))
        let window = NSWindow(contentRect:CGRect(x:0,y:0,width:1000,height:620),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.aqua);window.contentView = host
        defer { window.close() }
        input.makeTranslator = {
            NativeImageTranslator(label:"Synthetic resilience test",run:{ batch,_,_,partial in
                await probe.add(batch.payload)
                let result = batch.regions.map { region -> String in
                    let value = ["STATION GUIDE":"역 이용 안내","Tickets":"승차권","Information":"안내","Platform 2":"2번 승강장","Exit":"출구"][region.text] ?? "준비된 번역문"
                    return "<r\(region.id)>\(value)</r\(region.id)>"
                }.joined(separator:"\n")
                partial(result);return result
            })
        }
        input.fetchImage = { _ in image }
        func finish() async throws {
            let end = ContinuousClock.now.advanced(by:.seconds(20))
            while input.busy && ContinuousClock.now < end { try await Task.sleep(for:.milliseconds(10)) }
            check(!input.busy,"bounded synthetic request finishes")
        }

        let rejectedIcon = ClipboardImageSelection.parse(first+"<img src='file:///synthetic-icon.jpg' width='18' height='18'>"+last)
        input.loadSelection(rejectedIcon,plain:plain,direction:.englishToKorean);try await finish()
        check(input.textReady && input.image == nil && input.failedIcons == 1,"unreadable icon does not block selected text")
        check(input.translations.count == 2,"icon anchor splits text into stable translation blocks")

        let tiny = ClipboardImageSelection.parse(first+icon+last)
        input.loadSelection(tiny,plain:plain,direction:.englishToKorean);try await finish()
        check(input.complete && input.regions.isEmpty && input.image == nil,"inline icon never enters OCR")
        check(input.inlineImages.count == 1 && input.inlineImages[0].size == CGSize(width:18,height:18),"18px icon stays18px despite1200px source")
        check(input.inlineImages[0].offset == "Hello, my name is ".utf16.count,"icon stays after source prefix including whitespace")
        check(SelectionTextView.iconImage(input.inlineImages[0]).size == CGSize(width:18,height:18),"inline rendering image keeps display size")

        let mixed = ClipboardImageSelection.parse(first+icon+last+"<img src='data:image/png;base64,\(png)'><img src='http://example.invalid/missing.png'>")
        input.loadSelection(mixed,plain:plain,direction:.englishToKorean);try await finish()
        check(input.textReady && input.failedImages == 1 && input.renderedRegionIDs.count == 5,"one failed resource preserves five translated image regions and text")
        check(!input.complete && input.status.contains("이미지 1개"),"partial success is never announced as full completion")
        try await verifyVisible(host)

        let relative = ClipboardImageSelection.parse(first+icon+last+"<img src='images/synthetic.png'>",sourceURL:source)
        check(relative.references.contains(.remote(URL(string:"https://raw.githubusercontent.com/Geuni620/deepK/main/images/synthetic.png")!)),"relative URL resolves only with supplied document origin")
        for host in ["cdn.bsky.app","ogcard.cdn.bsky.app","camo.githubusercontent.com","raw.githubusercontent.com","docs.github.com","haeinjung.com"] {
            check(MemoryImageDownload.permits(URL(string:"https://"+host+"/synthetic.png")!),"observed public CDN is supported")
        }
        for value in ["http://pbs.twimg.com/a","https://pbs.twimg.com.evil.invalid/a","https://user:pass@pbs.twimg.com/a","https://127.0.0.1/a","https://localhost/a","https://raw.githubusercontent.com:444/a","file:///synthetic.png"] {
            check(!MemoryImageDownload.permits(URL(string:value)!),"unsafe destination remains blocked")
        }
        input.loadSelection(relative,plain:plain,direction:.englishToKorean);try await finish()
        check(input.complete && input.renderedRegionIDs.count == 5,"relative CDN resource reaches OCR and native renderer")

        input.fetchImage = { _ in throw ImagePOCError.message("Synthetic transport failure") }
        let missing = ClipboardImageSelection.parse(first+icon+last+"<img src='https://raw.githubusercontent.com/synthetic/missing.png'>")
        input.loadSelection(missing,plain:plain,direction:.englishToKorean);try await finish()
        let board = NSPasteboard.withUniqueName();defer { board.releaseGlobally() }
        check(input.copySelectedText(to:board) && board.string(forType:.string) == input.textLayout.translatedText(input.translations),"selected translation remains copyable after all body images fail")
        check(input.failedImages == 1 && !input.complete,"all-images-failed state remains explicitly partial")
        check(input.sourceLanguage == "en" && input.targetLanguage == "ko","displayed image-session languages match the actual request")
        try await verifyVisible(host)

        let unclassified = ClipboardImageSelection.parse("<p>Words<img src='https://pbs.twimg.com/a.png' alt='' aria-hidden='true'></p>")
        check(unclassified.items.first?.inlineSize == nil && unclassified.references.count == 1,"unknown geometry and accessibility attributes alone never discard media")
        let zero = ClipboardImageSelection.parse("<p>Words<img src='https://pbs.twimg.com/a.png' width='0' height='0'></p>")
        check(!zero.containsImages,"explicitly invisible zero geometry cannot hijack text input")
        let cssOverride = ClipboardImageSelection.parse("<p>Words<img src='https://pbs.twimg.com/a.png' width='18' height='18' style='width:240px;height:180px'></p>")
        check(cssOverride.items.first?.inlineSize == nil,"inline CSS geometry overrides stale HTML size attributes")
        let noSource = ClipboardImageSelection.parse("<p>Synthetic words</p><img srcset='https://pbs.twimg.com/a.png 2x'><img src=''>")
        let noSourceReport = try await noSource.loadReport(plain:"Synthetic words",fetch:{ _ in throw ImagePOCError.message("Must not fetch unknown source") })
        check(noSource.containsImages && noSourceReport.failedImages == 2,"unknown IMG resources are explicit partial failures and never fetch the document URL")
        let imageOnly = ClipboardImageSelection.parse("<img srcset='https://pbs.twimg.com/a.png 2x'>")
        check(imageOnly.documentText(from:"https://pbs.twimg.com/a.png").isEmpty,"image-only resource URL is never treated as document prose")
        let imageDocument = ClipboardImageSelection.parse("<html><head><title>Synthetic title metadata</title></head><body><img srcset='https://pbs.twimg.com/a.png 2x'></body></html>")
        check(imageDocument.documentText(from:"https://pbs.twimg.com/a.png").isEmpty,"document title metadata cannot turn an image-only URL into prose")
        let actualURLText = ClipboardImageSelection.parse("<p>https://example.com</p><img>")
        check(actualURLText.documentText(from:"https://example.com") == "https://example.com","explicit document URL text is retained")
        let metadataBoard = NSPasteboard.withUniqueName();defer { metadataBoard.releaseGlobally() }
        let sourceType = NSPasteboard.PasteboardType("org.chromium.source-url")
        let testHTML = "<p>Synthetic metadata</p>"
        metadataBoard.declareTypes([.html,sourceType],owner:nil)
        metadataBoard.setString(testHTML,forType:.html);metadataBoard.setString(source.absoluteString,forType:sourceType)
        check(ImagePOCIntegration.sourceURL(for:testHTML,board:metadataBoard) == source,"origin comes from the matching clipboard HTML")
        check(ImagePOCIntegration.sourceURL(for:"different",board:metadataBoard) == nil,"origin from another clipboard generation is rejected")
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        metadataBoard.addTypes([concealed],owner:nil);metadataBoard.setData(Data(),forType:concealed)
        check(ImagePOCIntegration.sourceURL(for:testHTML,board:metadataBoard) == nil,"sensitive clipboard metadata is rejected before import")
        let payloads = await probe.payloads
        check(payloads.allSatisfy { !$0.contains("file:") && !$0.contains("https:") && !$0.contains("data:image") && !$0.contains("base64") },"only selected text and local OCR reach translator")
        input.clear()
        check(!input.isActive && input.inlineImages.isEmpty && input.translations.isEmpty,"clear releases inline pixels, text, failures and current session")
        print("PASS: resilience cases1-5, inline placement, partial loading, origin/CDN policy, copy and content boundary; synthetic only")
    }
    private static func check(_ value:Bool,_ message:String) {
        guard value else { fputs("FAIL: \(message)\n",stderr);exit(1) }
    }
    private static func verifyVisible(_ view:NSView) async throws {
        try await Task.sleep(for:.milliseconds(150));view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw ImagePOCError.message("Synthetic view did not allocate pixels") }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let pixels = bitmap.cgImage else { throw ImagePOCError.message("Synthetic view did not render") }
        let text = try POCTextRecognition.recognize(POCImage(pixels:pixels,name:"synthetic text visibility check")).map(\.text).joined().lowercased()
        check(text.contains("hello") && text.contains("준비"),"source and translated text remain visibly rendered across image/failure layout transitions")
    }
}
#endif
