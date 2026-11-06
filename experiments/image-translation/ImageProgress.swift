#if DEEPK_IMAGE_TRANSLATION_POC
import AppKit
import SwiftUI

enum ImageProcessingStage { case idle, importing, reading, waiting, generating, applying, finished, failed }

/// pen.dev Final · Main Window uses 16pt for translation text. Keep image typography intact;
/// enlarge the viewport instead of shrinking the whole image back to fit after every zoom.
enum ImageReadingGeometry {
    static let readablePoints: CGFloat = 16
    static func magnification(imageWidth: Int, viewportWidth: CGFloat, bodyFontPixels: CGFloat, readable: Bool, zoom: Double) -> CGFloat {
        let fit = max(1, viewportWidth - 12) / CGFloat(max(1, imageWidth))
        let automatic = readable && bodyFontPixels > 0 ? max(1, readablePoints / (bodyFontPixels * fit)) : 1
        return min(8, max(1, automatic * zoom))
    }
    static func imageRect(size: CGSize, in bounds: CGRect) -> CGRect {
        let scale = max(1, bounds.width - 12) / size.width
        return CGRect(x: 6, y: 6, width: size.width * scale, height: size.height * scale)
    }
    static func textRect(_ box: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + box.minX * imageRect.width, y: imageRect.minY + (1 - box.maxY) * imageRect.height,
               width: box.width * imageRect.width, height: box.height * imageRect.height)
    }
}

@MainActor struct NativeImageProgressHeader: View {
    let input: NativeImageInput
    private var title: String {
        if !input.busy { return input.complete ? "이미지 번역 완료" : (input.warning != nil ? "일부 영역은 원본을 유지했어요" : input.status) }
        switch input.stage {
        case .importing: return "선택한 이미지를 가져오고 있어요"
        case .reading: return "이미지에서 글자를 읽고 있어요"
        case .waiting: return "글자를 읽었어요 · 번역 응답을 기다려요"
        case .applying: return "번역을 원래 배경에 반영하고 있어요"
        default: return input.activeRegionID == 0 ? "이미지 번역 완료 · 선택한 글 생성 중" : "이미지 속 번역문을 만들고 있어요"
        }
    }
    private var detail: String {
        switch input.stage {
        case .importing: "선택에 포함된 이미지가 같은 번역창에 표시됩니다."
        case .reading: "이 Mac에서 글자와 위치를 읽고 있어요."
        case .waiting: "인식한 \(input.regions.count)개 영역을 선택한 번역기로 보냈어요."
        case .applying: "완성된 문장부터 배경과 배치를 보존해 표시해요."
        default: "완성된 영역부터 이미지에 반영하고 있어요."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: input.complete ? "checkmark.circle.fill" : "viewfinder").foregroundStyle(input.complete ? Color.green : Color.accentColor)
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if input.busy { ProgressView().controlSize(.small) }
                Spacer(minLength: 4)
                if !input.regions.isEmpty {
                    Text("\(input.renderedRegionIDs.count)/\(input.regions.count)개 반영")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if input.busy {
                Group {
                    if input.draftText.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
                    else { Text(input.draftText).font(.system(size: 16)).foregroundStyle(.primary) }
                }
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .topLeading)
                if !input.regions.isEmpty {
                    ProgressView(value: Double(input.renderedRegionIDs.count), total: Double(input.regions.count)).controlSize(.small)
                        .accessibilityLabel("이미지에 반영한 번역 영역")
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, input.busy ? 10 : 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .combine)
    }
}
#endif
