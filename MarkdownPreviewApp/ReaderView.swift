import SwiftUI

/// One document window: TOC sidebar + rendered markdown, with an optional
/// source editor pane on the left when editing.
struct ReaderView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @AppStorage("theme") private var theme = "auto"
    @AppStorage("zoom") private var zoom = 1.0
    @AppStorage("editorFraction") private var editorFraction = 0.42
    @State private var isEditing: Bool
    @State private var selection: TextSelection?
    @State private var syncedHeading: Int?
    @State private var toc: [Heading] = []
    @State private var currentHeadingID: String?
    @State private var scrollTarget: String?

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        // New, never-saved documents open straight into the editor.
        _isEditing = State(initialValue: fileURL == nil)
    }

    var body: some View {
        NavigationSplitView {
            ScrollViewReader { proxy in
                List(toc) { heading in
                    TOCRow(
                        heading: heading,
                        isCurrent: heading.id == currentHeadingID,
                        onTap: { scrollTarget = heading.id }
                    )
                    .id(heading.id)
                }
                .listStyle(.sidebar)
                .onChange(of: currentHeadingID) { id in
                    if let id { withAnimation { proxy.scrollTo(id) } }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 230, max: 360)
            .overlay {
                if toc.isEmpty {
                    Text("No Headings")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        } detail: {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if isEditing {
                        SourceEditor(text: $document.text, selection: $selection)
                            .frame(width: editorWidth(total: geo.size.width))
                        SplitHandle(fraction: $editorFraction, totalWidth: geo.size.width)
                    }
                    MarkdownWebView(
                        text: document.text,
                        baseDir: fileURL.map { $0.deletingLastPathComponent().path },
                        theme: theme,
                        zoom: zoom,
                        toc: $toc,
                        currentHeadingID: $currentHeadingID,
                        scrollTarget: $scrollTarget
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .frame(minWidth: 960, minHeight: 600)
        .onChange(of: selection) { sel in
            syncPreviewToCursor(sel)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $isEditing.animation()) {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .toggleStyle(.button)
                .help(isEditing ? "隐藏编辑器" : "编辑 Markdown 源文件")
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Theme", selection: $theme) {
                    Label("Auto", systemImage: "circle.lefthalf.filled").tag("auto")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }
                .pickerStyle(.segmented)
                .help("Preview theme")
            }
        }
    }

    private func editorWidth(total: CGFloat) -> CGFloat {
        min(max(240, total * editorFraction), total * 0.6)
    }

    /// While editing, keep the preview scrolled to the section under the cursor.
    private func syncPreviewToCursor(_ sel: TextSelection?) {
        guard isEditing, let sel, case .selection(let range) = sel.indices else { return }
        guard let index = headingIndex(before: range.lowerBound),
              index != syncedHeading else { return }
        syncedHeading = index
        scrollTarget = "heading-\(index)"
    }

    /// Index (in TOC order) of the last h1–h4 heading at or above the cursor,
    /// matching the `heading-N` ids assigned in preview.html. Skips fenced
    /// code blocks so `#` comments inside them don't shift the count.
    private func headingIndex(before cursor: String.Index) -> Int? {
        let text = document.text
        var count = 0
        var inFence = false
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
            } else if !inFence {
                let hashes = line.prefix(while: { $0 == "#" }).count
                if (1...4).contains(hashes), line.dropFirst(hashes).first == " " {
                    count += 1
                }
            }
            if cursor <= lineEnd { break }
            lineStart = text.index(after: lineEnd)
        }
        return count > 0 ? count - 1 : nil
    }
}

private struct TOCRow: View {
    let heading: Heading
    let isCurrent: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Capsule()
                    .fill(isCurrent ? Color.accentColor : .clear)
                    .frame(width: 3, height: 13)
                Text(heading.text)
                    .font(font)
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
            .padding(.trailing, 6)
            .padding(.vertical, 4.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.top, heading.level == 1 ? 10 : 0)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0.5, leading: 6, bottom: 0.5, trailing: 6))
    }

    private var indent: CGFloat {
        switch heading.level {
        case 1: return 4
        case 2: return 16
        case 3: return 28
        default: return 38
        }
    }

    private var font: Font {
        switch heading.level {
        case 1: return .system(size: 13, weight: .semibold)
        case 2: return .system(size: 12.5)
        default: return .system(size: 11.5)
        }
    }

    private var textColor: Color {
        if isCurrent { return .accentColor }
        switch heading.level {
        case 1: return .primary
        case 2: return .primary.opacity(0.85)
        default: return .secondary
        }
    }

    private var rowBackground: Color {
        if isCurrent { return Color.accentColor.opacity(0.14) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

/// Plain-text markdown source editor.
private struct SourceEditor: View {
    @Binding var text: String
    @Binding var selection: TextSelection?

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .font(.system(size: 13, design: .monospaced))
            .lineSpacing(3)
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .padding(.leading, 20)
            .padding(.top, 12)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Draggable divider between the editor and the preview.
private struct SplitHandle: View {
    @Binding var fraction: Double
    let totalWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 9)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        guard totalWidth > 0 else { return }
                        let delta = value.translation.width / totalWidth
                        fraction = min(0.6, max(0.25, dragStart + delta))
                    }
                    .onEnded { _ in dragStart = fraction }
            )
            .onAppear { dragStart = fraction }
    }

    @State private var dragStart = 0.42
}
