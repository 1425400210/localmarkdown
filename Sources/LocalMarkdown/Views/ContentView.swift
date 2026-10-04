import SwiftUI

struct EditorActions {
    var undo: () -> Void
    var redo: () -> Void
    var find: () -> Void
    var toggleOutline: () -> Void
    var format: (String) -> Void
}

struct EditorActionsKey: FocusedValueKey {
    typealias Value = EditorActions
}

extension FocusedValues {
    var editorActions: EditorActions? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?
    @State private var controller = EditorController()
    @AppStorage("defaultSourceMode") private var sourceMode = false
    @State private var showOutline: Bool
    @AppStorage("formattingPreferences") private var formattingStored = ""
    private var formatting: FormattingPreferences { FormattingPreferences(json: formattingStored) }
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("editorFontSize") private var fontSize = 16.0
    @AppStorage("editorWidth") private var editorWidth = 800.0

    init(document: Binding<MarkdownDocument>, fileURL: URL? = nil) {
        self.fileURL = fileURL
        _document = document
        _showOutline = State(initialValue: UserDefaults.standard.object(forKey: "defaultShowOutline") as? Bool ?? true)
    }

    private var headings: [EditorHeading] { controller.headings }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showOutline {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("文档大纲")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        if headings.isEmpty {
                            Text("写下一个标题，\n让思路有迹可循。")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .lineSpacing(5)
                                .padding(.horizontal, 20)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(headings) { heading in
                                    Button { controller.jump(to: heading.location) } label: {
                                        Text(heading.title)
                                            .font(.system(size: 12, weight: heading.level == 1 ? .semibold : .regular))
                                            .foregroundStyle(heading.level == 1 ? .primary : .secondary)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 7)
                                            .padding(.leading, 20 + CGFloat(min(heading.level - 1, 3) * 10))
                                            .padding(.trailing, 16)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("跳转到 \(heading.title)")
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Label("本地 Markdown", systemImage: "doc.plaintext")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(20)
                    }
                    .frame(width: 210)
                    .background(.regularMaterial)
                    Divider()
                }
                VStack(spacing: 0) {
                    if let error = controller.errorMessage {
                        Text("编辑器提示：\(error)")
                            .font(.caption).foregroundStyle(.orange)
                            .padding(8).textSelection(.enabled)
                    }
                    MarkdownEditor(text: $document.text, sourceMode: sourceMode, controller: controller,
                                   fileURL: fileURL, fontSize: fontSize, editorWidth: editorWidth, formattingJSON: formattingStored)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Text("\(document.text.filter { !$0.isWhitespace }.count) 字符")
                Text("UTF-8")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 30)
        }
        .frame(minWidth: 680, minHeight: 440)
        .preferredColorScheme(appearance.colorScheme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showOutline.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help("显示或隐藏大纲 ⌥⌘1")
            }
            ForEach(FormattingAction.all.filter { formatting.toolbar.contains($0.id) }) { action in
                ToolbarItem(id: action.id, placement: .primaryAction) {
                    Button { controller.command("format", argument: action.id) } label: {
                        if action.id.hasPrefix("heading") {
                            Text(action.id == "heading0" ? "正文" : "H" + String(action.id.suffix(1)))
                        } else { Image(systemName: action.symbol) }
                    }
                    .help(action.title + " " + formatting.label(for: action))
                    .accessibilityLabel(action.title)
                }
            }
            ToolbarItem(id: "settings", placement: .primaryAction) {
                SettingsLink { Image(systemName: "gearshape") }
                    .accessibilityLabel("设置")
                    .help("设置 ⌘,")
            }
        }
        .focusedSceneValue(\.editorActions, EditorActions(
            undo: { controller.command("undo") },
            redo: { controller.command("redo") },
            find: { controller.find() },
            toggleOutline: { showOutline.toggle() },
            format: { controller.command("format", argument: $0) }
        ))
    }
}
