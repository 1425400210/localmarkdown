import AppKit
import SwiftUI

@main
struct LocalMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1060, height: 760)
        .commands { EditorCommands() }

        Window("关于 LocalMarkdown", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("LocalMarkdown 使用帮助", id: "help") {
            AppHelpView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct EditorCommands: Commands {
    @AppStorage("formattingPreferences") private var formattingStored = ""
    @FocusedValue(\.editorActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 LocalMarkdown") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .help) {
            Button("LocalMarkdown 使用帮助") { openWindow(id: "help") }
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { actions?.undo() }.keyboardShortcut("z")
            Button("重做") { actions?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("查找…") { actions?.find() }.keyboardShortcut("f")
        }
        CommandMenu("格式") {
            ForEach(FormattingAction.all) { action in
                Button(action.title) { actions?.format(action.id) }
                    .keyboardShortcut(FormattingPreferences(json: formattingStored).shortcut(for: action))
                    .disabled(actions == nil)
            }
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button("显示或隐藏大纲") { actions?.toggleOutline() }.keyboardShortcut("1", modifiers: [.command, .option])
        }
    }
}
