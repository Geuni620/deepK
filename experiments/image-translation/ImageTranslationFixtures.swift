#if DEEPK_IMAGE_TRANSLATION || DEEPK_IMAGE_TRANSLATION_POC
import AppKit
@MainActor enum POCFixtures {
    static let labels: [(String, String, CGRect)] = [
        ("STATION GUIDE", "역 이용 안내", CGRect(x: 80, y: 565, width: 650, height: 58)),
        ("Tickets", "승차권", CGRect(x: 100, y: 395, width: 220, height: 50)),
        ("Information", "안내", CGRect(x: 665, y: 395, width: 320, height: 50)),
        ("Platform 2", "2번 승강장", CGRect(x: 100, y: 178, width: 320, height: 50)),
        ("Exit", "출구", CGRect(x: 665, y: 178, width: 220, height: 50))
    ]

    static func sample() -> POCImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 700, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1200, height: 700)).fill()
        for rect in [CGRect(x: 65, y: 325, width: 510, height: 155), CGRect(x: 630, y: 325, width: 510, height: 155),
                     CGRect(x: 65, y: 105, width: 510, height: 155), CGRect(x: 630, y: 105, width: 510, height: 155)] {
            NSColor.white.setFill(); NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
        }
        NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.7, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 80, y: 525, width: 1040, height: 8)).fill()
        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: 980, y: 148)); arrow.line(to: CGPoint(x: 1070, y: 148))
        arrow.move(to: CGPoint(x: 1040, y: 175)); arrow.line(to: CGPoint(x: 1070, y: 148)); arrow.line(to: CGPoint(x: 1040, y: 121))
        arrow.lineWidth = 10; NSColor.systemBlue.setStroke(); arrow.stroke()
        for (text, _, rect) in labels {
            (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: rect.minY > 500 ? 48 : 40, weight: .semibold),
                                                            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)])
        }
        NSGraphicsContext.restoreGraphicsState()
        return POCImage(pixels: rep.cgImage!, name: "역 안내판 · 직접 만든 샘플")
    }

    static func translations(for regions: [ImageTextRegion]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: regions.compactMap { region in
            labels.first(where: { $0.0.caseInsensitiveCompare(region.text) == .orderedSame }).map { (region.id, $0.1) }
        })
    }
}
#endif
