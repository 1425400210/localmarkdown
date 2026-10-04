import AppKit
import SwiftUI

struct AboutView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @Environment(\.openWindow) private var openWindow

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版本"
        let build = info["CFBundleVersion"] as? String ?? "—"
        return "版本 \(version)（\(build)）"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 80, height: 80)
            Text("LocalMarkdown").font(.largeTitle.bold())
            Text(version).foregroundStyle(.secondary).textSelection(.enabled)
            Text("专注书写，本地保存。")
                .font(.title3)
            Text("面向 Mac 的 Markdown 编辑器。\n即时排版、源码编辑与原生文件管理。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("使用帮助") { openWindow(id: "help") }
                Button("第三方许可") {
                    let url = MarkdownEditor.resourceURL.deletingLastPathComponent()
                        .appendingPathComponent("THIRD-PARTY-NOTICES.txt")
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(32)
        .frame(width: 420)
        .preferredColorScheme(appearance.colorScheme)
    }
}
