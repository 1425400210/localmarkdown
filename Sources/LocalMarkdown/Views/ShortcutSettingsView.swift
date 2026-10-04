import SwiftUI

struct ShortcutSettingsView: View {
    @AppStorage("formattingPreferences") private var stored = ""
    @State private var editing: FormattingAction?
    @State private var conflictMessage: String?
    private var preferences: FormattingPreferences { FormattingPreferences(json: stored) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("同时支持 Control + 0～6（正文与标题）", isOn: Binding(get: { preferences.controlHeadings }, set: { enabled in
                var value = preferences
                if enabled, let conflict = FormattingAction.all.first(where: { action in
                    (0...6).contains(where: { value.key(for: action) == "Control-\($0)" })
                }) {
                    conflictMessage = "请先修改「\(conflict.title)」占用的 Control 数字快捷键。"
                    return
                }
                conflictMessage = nil
                value.controlHeadings = enabled
                stored = value.json
            }))
            Text("点击快捷键修改。勾选后显示在工具栏；窗口较窄时可从「格式」菜单使用。系统可能优先占用部分 Control 组合。")
                .font(.caption).foregroundStyle(.secondary)
            if let conflictMessage { Text(conflictMessage).font(.caption).foregroundStyle(.red) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(FormattingAction.all) { action in
                        HStack {
                            Text(action.title).frame(width: 100, alignment: .leading)
                            Button(preferences.label(for: action)) { editing = action }.frame(width: 130)
                            Spacer()
                            Toggle("工具栏", isOn: Binding(get: { preferences.toolbar.contains(action.id) }, set: { enabled in
                                var value = preferences
                                if enabled { value.toolbar.insert(action.id) } else { value.toolbar.remove(action.id) }
                                stored = value.json
                            }))
                            .toggleStyle(.checkbox)
                        }
                    }
                }.padding(8)
            }
            Button("恢复默认快捷键与工具栏") { stored = "" }
        }
        .padding(20)
        .sheet(item: $editing) { action in
            ShortcutEditView(action: action, stored: $stored)
        }
    }
}

private struct ShortcutEditView: View {
    let action: FormattingAction
    @Binding var stored: String
    @Environment(\.dismiss) private var dismiss
    @State private var modifier = "Mod"
    @State private var key = ""
    @State private var error: String?
    private let modifiers = ["Mod", "Mod-Shift", "Mod-Option", "Mod-Control", "Control", "Control-Shift"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置「\(action.title)」快捷键").font(.headline)
            Picker("修饰键", selection: $modifier) {
                ForEach(modifiers, id: \.self) { value in
                    Text(value.replacingOccurrences(of: "Mod", with: "⌘ Command").replacingOccurrences(of: "Shift", with: "⇧ Shift").replacingOccurrences(of: "Option", with: "⌥ Option").replacingOccurrences(of: "Control", with: "⌃ Control").replacingOccurrences(of: "-", with: " + ")).tag(value)
                }
            }
            TextField("一个英文字母、数字或 `", text: $key).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("清除") { save("") }
                Spacer()
                Button("保存") {
                    let normalized = key.lowercased()
                    guard normalized.count == 1, normalized.range(of: "^[a-z0-9`]$", options: .regularExpression) != nil else { error = "请输入一个英文字母、数字或 `。"; return }
                    save(modifier + "-" + normalized)
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 430)
        .onAppear {
            let parts = FormattingPreferences(json: stored).key(for: action).split(separator: "-")
            key = parts.last.map(String.init) ?? ""
            let savedModifier = parts.dropLast().joined(separator: "-")
            if modifiers.contains(savedModifier) { modifier = savedModifier }
        }
    }
    private func save(_ value: String) {
        var preferences = FormattingPreferences(json: stored)
        if let conflict = preferences.conflict(value, for: action) { error = conflict; return }
        preferences.overrides[action.id] = value
        stored = preferences.json
        dismiss()
    }
}
