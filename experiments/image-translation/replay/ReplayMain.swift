import AppKit
import AVFoundation
import SwiftUI

@main @MainActor enum ReplayMain {
    static let prose = "Hello, my name is Morgan.\n\nI share notes and pictures.\n\nPlease keep the original layout."
    static let labels = ["1 글 번역 보호", "2 작은 아이콘 분류", "3 이미지별 부분 성공", "4 상대 주소와 다른 CDN", "5 부분 실패 안내와 글 복사"]
    static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        Task {
            do {
                #if ISSUE_AFTER
                if CommandLine.arguments.contains("--tests") {
                    await NativeImageTests.run();await ImageFeedbackBenchmark.run();try ScreenScannerTests.run();ImageTranslationTests.run();exit(0)
                }
                #endif
                try await run();exit(0)
            } catch { fputs("FAIL: synthetic replay (no user content)\n",stderr);exit(1) }
        }
        RunLoop.main.run()
    }
    static func run() async throws {
        let out = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let app = AppModel.shared
        app.store.setDirection(.englishToKorean)
        app.imageInput.makeTranslator = { NativeImageTranslator(label:"합성 시연 · 준비된 번역 · 제공자 호출 없음",run:{ batch,_,_,partial in
            var value = ""
            for region in batch.regions {
                let translated: String
                if region.id == 0 { translated = region.text.contains("Morgan") ? "안녕하세요, 제 이름은 Morgan입니다.\n\n저는 글과 사진을 공유합니다.\n\n원래 배치를 유지해 주세요." : "안녕하세요, 제 이름은" }
                else if region.id >= 100000 { translated = "Morgan입니다.\n\n저는 글과 사진을 공유합니다.\n\n원래 배치를 유지해 주세요." }
                else { translated = ["STATION GUIDE":"역 이용 안내","Tickets":"승차권","Information":"안내","Platform 2":"2번 승강장","Exit":"출구"][region.text] ?? region.text }
                value += "<r\(region.id)>"
                for char in translated { value.append(char);partial(value);try await Task.sleep(for:.milliseconds(7)) }
                value += "</r\(region.id)>";partial(value)
            }
            return value
        }) }
        #if ISSUE_AFTER
        app.imageInput.fetchImage = { url in
            try await Task.sleep(for:.milliseconds(250))
            if url.path.contains("missing") { throw ImagePOCError.message("합성 실패 표본") }
            return await POCFixtures.sample()
        }
        #endif
        let png = NSBitmapImageRep(cgImage:POCFixtures.sample().pixels).representation(using:.png,properties:[:])!.base64EncodedString()
        let prefix = "<p>Hello, my name is ", suffix = "Morgan.</p><p>I share notes and pictures.</p><p>Please keep the original layout.</p>"
        let icon = "<img src='data:image/png;base64,\(png)' width='18' height='18'>"
        let scenes = [
            prefix + "<img src='file:///synthetic-only-icon.jpg' width='18' height='18'>" + suffix,
            prefix + icon + suffix,
            prefix + icon + suffix + "<img src='data:image/png;base64,\(png)'><img src='http://example.invalid/missing.jpg'>",
            prefix + icon + suffix + "<img src='evidence/chat-original.png'>",
            prefix + icon + suffix + "<img src='https://raw.githubusercontent.com/synthetic/missing.png'>"
        ]
        var checks: [[String:Any]] = []
        let movie = try ReplayWriter(url:out.appendingPathComponent("replay.mp4"),width:1120,height:840)
        var seconds = 0.0
        for (index,html) in scenes.enumerated() {
            app.imageInput.clear()
            #if ISSUE_AFTER
            _ = ImagePOCIntegration.shared.accept(plain:prose,html:html,sourceURL:URL(string:"https://raw.githubusercontent.com/Geuni620/deepK/596fea1507ee11c26332e91dc086a39c4eeb83c8/experiments/image-translation/README.md"))
            #else
            _ = ImagePOCIntegration.shared.accept(plain:prose,html:html)
            #endif
            guard let panel = NSApp.windows.first(where:{$0 is TranslationPanel}),let view=panel.contentView else { throw ImagePOCError.message("Synthetic translation panel unavailable") }
            panel.setContentSize(CGSize(width:1000,height:720))
            let start = ContinuousClock.now
            let sceneStart = seconds
            var readyAt: ContinuousClock.Instant?
            while start.duration(to:.now) < .seconds(30) {
                try await Task.sleep(for:.milliseconds(200));view.layoutSubtreeIfNeeded()
                guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { continue }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                guard let image=bitmap.cgImage else { continue }
                #if ISSUE_AFTER
                let version="AFTER"
                #else
                let version="BEFORE · 596fea1"
                #endif
                let frame = annotated(image,caption:"\(version)   \(labels[index])")
                try movie.append(frame,seconds:seconds);seconds += 0.2
                try NSBitmapImageRep(cgImage:frame).representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent("scene-\(index+1)-last.png"))
                if !app.imageInput.busy {
                    if readyAt == nil { readyAt = .now }
                    if readyAt!.duration(to:.now) > .seconds(2) { break }
                }
            }
            #if ISSUE_AFTER
            let board = NSPasteboard.withUniqueName()
            let copied = app.imageInput.copySelectedText(to:board) && board.string(forType:.string) == app.imageInput.textLayout.translatedText(app.imageInput.translations)
            board.releaseGlobally()
            let extra: [String:Any] = ["textReady":app.imageInput.textReady,"copiedText":copied,"failedImages":app.imageInput.failedImages,"failedIcons":app.imageInput.failedIcons,"inlineIcons":app.imageInput.inlineImages.count,"ocrRegions":app.imageInput.regions.count]
            guard app.imageInput.textReady,copied,!app.imageInput.busy else { throw ImagePOCError.message("Synthetic text result did not finish") }
            if index == 2 || index == 3 { guard app.imageInput.regions.count == 5,app.imageInput.renderedRegionIDs.count == 5 else { throw ImagePOCError.message("Synthetic image result did not finish") } }
            #else
            let extra: [String:Any] = [:]
            #endif
            var record: [String:Any] = ["scene":index+1,"busy":app.imageInput.busy,"complete":app.imageInput.complete,
                           "movieStartSeconds":sceneStart,"movieEndSeconds":seconds,
                           "translatedBlocks":app.imageInput.translations.count,"imagePresent":app.imageInput.image != nil,
                           "translationPanelCount":NSApp.windows.filter{$0 is TranslationPanel}.count]
            record.merge(extra) { _,new in new };checks.append(record)
        }
        guard await movie.finish() else { throw ImagePOCError.message("Synthetic video encoding failed") }
        let metadata: [String:Any] = ["syntheticOnly":true,"preparedTranslationResponses":true,"physicalShortcutExercised":false,"providerRequests":0,"scenes":checks]
        try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("checks.json"))
        await ImagePOCIntegration.shared.shutdown();await app.shutdown()
        print("PASS: five synthetic runtime replay scenes; no user content, global shortcut or provider calls")
    }
    static func annotated(_ image: CGImage,caption:String) -> CGImage {
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1120,pixelsHigh:840,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        NSColor(calibratedWhite:0.94,alpha:1).setFill();NSBezierPath(rect:CGRect(x:0,y:0,width:1120,height:840)).fill()
        (caption as NSString).draw(at:CGPoint(x:24,y:795),withAttributes:[.font:NSFont.systemFont(ofSize:21,weight:.semibold),.foregroundColor:NSColor.black])
        ("동일 합성 입력 · 준비된 번역 응답 · 실제 앱 뷰 실행 · 물리적 단축키 제외" as NSString).draw(at:CGPoint(x:24,y:770),withAttributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.darkGray])
        NSImage(cgImage:image,size:CGSize(width:image.width,height:image.height)).draw(in:CGRect(x:60,y:30,width:1000,height:720))
        NSGraphicsContext.restoreGraphicsState();return rep.cgImage!
    }
}

@MainActor final class ReplayWriter {
    let writer:AVAssetWriter,input:AVAssetWriterInput,adaptor:AVAssetWriterInputPixelBufferAdaptor
    let width:Int,height:Int
    init(url:URL,width:Int,height:Int)throws{
        self.width=width;self.height=height
        writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height]);input.expectsMediaDataInRealTime=true
        adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height])
        writer.add(input);guard writer.startWriting() else{throw ImagePOCError.message("Video start failed")};writer.startSession(atSourceTime:.zero)
    }
    func append(_ image:CGImage,seconds:Double)throws{
        guard input.isReadyForMoreMediaData,let pool=adaptor.pixelBufferPool else{return}
        var value:CVPixelBuffer?;guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&value)==kCVReturnSuccess,let value else{throw ImagePOCError.message("Video buffer failed")}
        CVPixelBufferLockBaseAddress(value,[]);defer{CVPixelBufferUnlockBaseAddress(value,[])}
        let context=CGContext(data:CVPixelBufferGetBaseAddress(value),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(value),space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        guard adaptor.append(value,withPresentationTime:CMTime(seconds:seconds,preferredTimescale:600))else{throw ImagePOCError.message("Video append failed")}
    }
    func finish()async->Bool{input.markAsFinished();await writer.finishWriting();return writer.status == .completed}
}
