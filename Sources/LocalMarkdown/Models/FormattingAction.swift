import SwiftUI

struct FormattingAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let key: String
    static let all: [Self] = (1...6).map { Self(id: "heading\($0)", title: "\($0) 级标题", symbol: "textformat.size", key: "Mod-\($0)") } + [
        .init(id: "heading0", title: "正文", symbol: "text.alignleft", key: "Mod-0"),
        .init(id: "bold", title: "加粗", symbol: "bold", key: "Mod-b"),
        .init(id: "italic", title: "斜体", symbol: "italic", key: "Mod-i"),
        .init(id: "underline", title: "下划线", symbol: "underline", key: "Mod-u"),
        .init(id: "strike", title: "删除线", symbol: "strikethrough", key: "Control-Shift-`"),
        .init(id: "highlight", title: "高亮", symbol: "highlighter", key: "Mod-Shift-h"),
        .init(id: "inlineCode", title: "行内代码", symbol: "chevron.left.forwardslash.chevron.right", key: "Mod-Shift-`"),
        .init(id: "link", title: "链接", symbol: "link", key: "Mod-k"),
        .init(id: "image", title: "图片", symbol: "photo", key: "Mod-Control-i"),
        .init(id: "quote", title: "引用", symbol: "text.quote", key: "Mod-Option-q"),
        .init(id: "unordered", title: "无序列表", symbol: "list.bullet", key: "Mod-Option-u"),
        .init(id: "ordered", title: "有序列表", symbol: "list.number", key: "Mod-Option-o"),
        .init(id: "task", title: "任务列表", symbol: "checklist", key: "Mod-Option-x"),
        .init(id: "codeBlock", title: "代码块", symbol: "curlybraces", key: "Mod-Option-c"),
        .init(id: "mathBlock", title: "公式块", symbol: "function", key: "Mod-Option-b"),
        .init(id: "rule", title: "分隔线", symbol: "minus", key: "Mod-Option-r"),
        .init(id: "table", title: "表格", symbol: "tablecells", key: "Mod-Option-t")
    ]
}

struct FormattingPreferences: Codable {
    var overrides: [String: String] = [:]
    var toolbar: Set<String> = ["heading1", "bold", "italic", "inlineCode"]
    var controlHeadings = true

    init(json: String = "") {
        if let data = json.data(using: .utf8), let saved = try? JSONDecoder().decode(Self.self, from: data) { self = saved }
    }
    var json: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "" }
    func key(for action: FormattingAction) -> String { overrides[action.id] ?? action.key }
    var webKeys: [String: String] {
        Dictionary(uniqueKeysWithValues: FormattingAction.all.compactMap { action in
            let key = key(for: action)
            return key.isEmpty ? nil : (action.id, key.replacingOccurrences(of: "Control", with: "Ctrl").replacingOccurrences(of: "Option", with: "Alt"))
        })
    }
    func shortcut(for action: FormattingAction) -> KeyboardShortcut? {
        let parts = key(for: action).split(separator: "-").map(String.init)
        guard let last = parts.last, let character = last.first else { return nil }
        var modifiers: EventModifiers = []
        if parts.contains("Mod") { modifiers.insert(.command) }
        if parts.contains("Control") { modifiers.insert(.control) }
        if parts.contains("Option") { modifiers.insert(.option) }
        if parts.contains("Shift") { modifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
    func label(for action: FormattingAction) -> String {
        let key = key(for: action)
        if key.isEmpty { return "未设置" }
        return key.replacingOccurrences(of: "Mod-", with: "⌘").replacingOccurrences(of: "Control-", with: "⌃").replacingOccurrences(of: "Option-", with: "⌥").replacingOccurrences(of: "Shift-", with: "⇧").uppercased()
    }
    func conflict(_ key: String, for action: FormattingAction) -> String? {
        guard !key.isEmpty else { return nil }
        let reserved = ["Mod-n", "Mod-o", "Mod-s", "Mod-q", "Mod-w", "Mod-a", "Mod-c", "Mod-v", "Mod-x", "Mod-z", "Mod-f", "Mod-h", "Mod-m", "Mod-Shift-z", "Mod-Shift-s", "Mod-Shift-m", "Mod-Option-1", "Mod-Shift-q", "Mod-Control-q", "Mod-Control-f", "Mod-Option-h", "Mod-Option-m"]
        if reserved.contains(key) { return "此组合用于文件、系统或编辑操作。" }
        if controlHeadings && (0...6).contains(where: { key == "Control-\($0)" }) { return "此组合用于标题兼容快捷键，请先关闭兼容选项。" }
        if let other = FormattingAction.all.first(where: { $0.id != action.id && self.key(for: $0) == key }) { return "已被「\(other.title)」使用。" }
        return nil
    }
}
