import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("editorFontSize") private var fontSize = 16.0
    @AppStorage("editorWidth") private var editorWidth = 800.0
    @AppStorage("defaultSourceMode") private var defaultSourceMode = false
    @AppStorage("defaultShowOutline") private var defaultShowOutline = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var defaultApplication: URL?
    @State private var isSettingDefault = false
    @State private var associationMessage: String?

    private var isDefaultApplication: Bool {
        defaultApplication?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    var body: some View {
        TabView {
            Form {
                Section("关于") {
                    LabeledContent("应用", value: "LocalMarkdown")
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本")
                }
                Section("外观") {
                    Picker("应用外观", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                }
                Section {
                    LabeledContent("当前默认应用", value: defaultApplication?.deletingPathExtension().lastPathComponent ?? "未找到默认应用")
                    HStack {
                        if isDefaultApplication {
                            Label("已设为默认 Markdown 编辑器", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("设为默认 Markdown 编辑器") {
                                Task { await setDefaultApplication() }
                            }
                            .disabled(isSettingDefault)
                        }
                        if isSettingDefault { ProgressView().controlSize(.small) }
                    }
                    if let associationMessage {
                        Text(associationMessage).font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("文件关联")
                } footer: {
                    Text("设置后，双击 .md 和 .markdown 文件将使用 LocalMarkdown 打开。单独指定了打开方式的文件可在访达「显示简介」中调整。")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section {
                    LabeledContent("字号") {
                        Stepper(value: $fontSize, in: 13...24, step: 1) {
                            Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 48)
                        }
                        .fixedSize()
                    }
                    Picker("正文宽度", selection: $editorWidth) {
                        Text("紧凑 · 600 pt").tag(600.0)
                        Text("适中 · 720 pt").tag(720.0)
                        Text("标准 · 800 pt").tag(800.0)
                        Text("宽松 · 900 pt").tag(900.0)
                    }
                    Button("恢复默认排版") {
                        fontSize = 16
                        editorWidth = 800
                    }
                } header: {
                    Text("正文排版")
                } footer: {
                    Text("立即应用到所有文档。标题与代码字号会按比例调整，文件内容保持原样。")
                }
                Section {
                    Toggle("即时渲染", isOn: Binding(get: { !defaultSourceMode }, set: { defaultSourceMode = !$0 }))
                    Toggle("默认显示文档大纲", isOn: $defaultShowOutline)
                } header: {
                    Text("编辑行为")
                } footer: {
                    Text("即时渲染开启时显示排版后的正文，关闭时显示全部 Markdown 源码。立即应用到所有文档，文件内容保持不变。大纲选项用于之后打开的文档。")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("编辑", systemImage: "textformat") }

            ShortcutSettingsView()
                .tabItem { Label("快捷键与工具栏", systemImage: "keyboard") }
        }
        .frame(width: 660, height: 560)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear { refreshDefaultApplication() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDefaultApplication() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDefaultApplication()
        }
    }

    private func refreshDefaultApplication() {
        defaultApplication = NSWorkspace.shared.urlForApplication(toOpen: .markdownDocument)
    }

    @MainActor
    private func setDefaultApplication() async {
        isSettingDefault = true
        associationMessage = nil
        defer { isSettingDefault = false }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .markdownDocument)
            refreshDefaultApplication()
            if !isDefaultApplication {
                associationMessage = "系统尚未切换默认应用，请重试，或在访达「显示简介 → 打开方式 → 全部更改」中设置。"
            }
        } catch {
            refreshDefaultApplication()
            associationMessage = "未能完成设置：\(error.localizedDescription)"
        }
    }
}
