import AppKit
import SwiftUI

/// Changes the display settings in place; `AppModel.updateResultDisplay` saves them and repaints open result windows.
typealias ResultDisplayUpdate = ((inout ResultDisplaySettings) -> Void) -> Void

/// The 표시 tab (S6′ stage 1): the code style drill-down and the behaviors that apply to every style.
struct DisplaySettingsTab: View {
    let display: ResultDisplaySettings
    let update: ResultDisplayUpdate
    let openPicker: () -> Void
    @State private var hoversStyleRow = false

    var body: some View {
        VStack(spacing: 0) {
            codeStyleRow
            Divider().padding(.horizontal, 20)
            foldRow
            Divider().padding(.horizontal, 20)
            SettingsToggleRow(title: "링크 출처 표시", subtitle: "링크 뒤에 사이트 주소를 작게 붙입니다",
                              isOn: binding(\.showsLinkSource))
            Divider().padding(.horizontal, 20)
            SettingsToggleRow(title: "문법 색", subtitle: "키워드·문자열·주석에 색을 입힙니다", isOn: binding(\.colorsSyntax))
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var codeStyleRow: some View {
        Button(action: openPicker) {
            // Tight trailing gaps leave the subtitle its full width next to a long style name.
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("코드 스타일")
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(display.style.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                HStack(spacing: 6) {
                    CodeStyleSwatch(style: display.style)
                    Text(display.style.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(hoversStyleRow ? Color(nsColor: .quaternarySystemFill) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoversStyleRow = $0 }
        .accessibilityLabel("코드 스타일 \(display.style.name)")
        .accessibilityHint("스타일 목록과 미리보기를 엽니다")
    }

    private var foldRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("긴 코드 접기")
                Text(CodeStylePickerModel.foldSubtitle(display))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            foldCountMenu
                .padding(.trailing, 8)
            Toggle("긴 코드 접기", isOn: binding(\.foldsLongCode))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .controlSize(.mini)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }

    /// A compact popup (S6′: 46×20, "5줄" and up-down chevrons); the system popup is too wide for the row's subtitle.
    private var foldCountMenu: some View {
        Menu {
            ForEach(ResultDisplaySettings.foldLineChoices, id: \.self) { count in
                Button {
                    chooseFoldLines(count)
                } label: {
                    if count == display.foldLineCount {
                        Label(CodeStylePickerModel.foldChoiceTitle(count), systemImage: "checkmark")
                    } else {
                        Text(CodeStylePickerModel.foldChoiceTitle(count))
                    }
                }
            }
        } label: {
            Text(CodeStylePickerModel.foldChoiceTitle(display.foldLineCount))
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .frame(height: 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(red: 0xD1 / 255, green: 0xD1 / 255, blue: 0xD6 / 255)))
        .disabled(!display.foldsLongCode)
        .opacity(display.foldsLongCode ? 1 : 0.5)
        .accessibilityLabel("접을 때 보이는 줄 \(CodeStylePickerModel.foldChoiceTitle(display.foldLineCount))")
    }

    /// The line count menu's choice; the menu builds its items only while open, so the tests call this.
    func chooseFoldLines(_ count: Int) {
        update { $0.foldLineCount = count }
    }

    private func binding(_ keyPath: WritableKeyPath<ResultDisplaySettings, Bool>) -> Binding<Bool> {
        Binding(get: { display[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }
}

/// A settings row with a title, a one-line subtitle and a switch; the look every settings tab shares.
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .controlSize(.mini)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }
}

/// The picker (S6′ stage 2): styles on the left, the real result view drawing a sample on the right. ↑↓ switches the
/// style at once; the window's root handles Esc, so there is one way back besides '‹ 표시'.
struct CodeStylePickerView: View {
    let display: ResultDisplaySettings
    var styles = ResultStyle.builtIns
    let update: ResultDisplayUpdate
    let back: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    private var sections: [CodeStylePickerModel.Section] { CodeStylePickerModel.sections(styles: styles, query: query) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1)
                previewPane
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: CodeStylePickerModel.pickerSize.width)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .onAppear { focused = true }
    }

    private var topBar: some View {
        ZStack {
            Text("코드 스타일")
                .font(.system(size: 13, weight: .semibold))
            HStack {
                Button(action: back) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("표시")
                    }
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.leading, 4)
                    .padding(.trailing, 8)
                    .frame(height: 24)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("표시 탭으로 돌아가기")
                Spacer(minLength: 0)
            }
            // Clears the window's traffic lights.
            .padding(.leading, 78)
        }
        .frame(height: 44)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if CodeStylePickerModel.showsSearch(styleCount: styles.count) {
                TextField("스타일 검색", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        HStack {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            Spacer(minLength: 4)
                            Text("\(section.styles.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .accessibilityElement(children: .combine)
                        ForEach(section.styles) { style in
                            row(style)
                        }
                    }
                }
            }
            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
            Text("↑↓로 바로 바꾸기")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 16)
                .frame(height: 34)
        }
        .frame(width: CodeStylePickerModel.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255))
    }

    private func row(_ style: ResultStyle) -> some View {
        let selected = style.id == display.style.id
        return Button {
            update { $0.style = style }
        } label: {
            HStack(spacing: 8) {
                CodeStyleSwatch(style: style, selected: selected)
                Text(style.name)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color(nsColor: .labelColor))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel(style.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.style.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(display.style.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
            // The scroller gutter is the well's right padding, so the text wraps at 366 as in the small result window.
            CodeStylePreview(display: display)
                .frame(width: CodeStylePickerModel.previewWidth, height: CodeStylePickerModel.previewHeight)
                .padding(.leading, 10)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.12)))
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Text("표시 탭의 동작 설정이 반영됨:")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                ForEach(CodeStylePickerModel.statusChips(display), id: \.text) { chip in
                    StatusChipView(chip: chip)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        guard let style = CodeStylePickerModel.style(offset: offset, from: display.style, in: styles, query: query) else { return .ignored }
        update { $0.style = style }
        return .handled
    }
}

/// The real result view with the style picker's sample: a line with chips and a link, and a 7-line TypeScript block
/// that the default fold limit (5) folds.
struct CodeStylePreview: NSViewRepresentable {
    let display: ResultDisplaySettings

    static let content = TranslationResultContent(
        identity: UUID(uuidString: "C0DE5717-0000-4000-8000-000000000001")!,
        text: """
        `read`, `bash`만 씁니다 · <a1>하네스 찾기</a1>

        ```typescript
        // wire only two tools
        import { getModel } from 'ai';
        const claude = getModel('anthropic');
        const ctx = await loadContext(repo);
        const res = await complete(claude, ctx);
        console.log(res.text);
        export default res;
        ```
        """,
        tailStart: nil, isStreaming: false, isStale: false,
        inline: InlineOptions(code: .only(["read", "bash"]), links: [
            SourceLink(url: URL(string: "https://blog.example.com/harness")!, text: "Finding the best harness")
        ])
    )

    func makeNSView(context: Context) -> NSScrollView {
        TranslationResultTextView.makeScrollView(preview: true)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        TranslationResultTextView.update(scroll, content: Self.content, lineSpacing: 3, display: display)
    }
}

/// A style in miniature, from its values: the card fill and border (or rail), a header band when the header has a
/// separator, and two bars in the keyword and string colors.
struct CodeStyleSwatch: View {
    let style: ResultStyle
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        ZStack(alignment: .topLeading) {
            Color.white
            if let fill = style.box.fill { Color(nsColor: fill.nsColor) }
            if let separator = style.header.separator {
                Color(nsColor: separator.nsColor).opacity(0.5).frame(height: 4)
            }
            if let rule = style.box.rule {
                Color(nsColor: rule.color.nsColor).frame(width: 2)
            }
            bar(style.syntax?.keyword ?? style.code.color, width: 10).offset(x: 5, y: 7)
            bar(style.syntax?.string ?? style.code.color, width: 7).offset(x: 5, y: 11)
        }
        .frame(width: 22, height: 16)
        .clipShape(shape)
        .overlay(shape.strokeBorder(selected ? Color.white : style.box.border.map { Color(nsColor: $0.color.nsColor) }
                 ?? Color.black.opacity(0.1)))
        .accessibilityHidden(true)
    }

    private func bar(_ color: StyleColor, width: CGFloat) -> some View {
        Capsule().fill(Color(nsColor: color.nsColor)).frame(width: width, height: 2)
    }
}

private struct StatusChipView: View {
    let chip: CodeStylePickerModel.StatusChip

    var body: some View {
        Text(chip.text)
            .font(.system(size: 10))
            .foregroundStyle(chip.isOn ? Color(red: 0x1E / 255, green: 0x7B / 255, blue: 0x34 / 255)
                             : Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(chip.isOn ? Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255).opacity(0.12)
                        : Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
    }
}
