import AppKit
import SwiftUI
import Testing
import WebKit
@testable import LocalMarkdown

@MainActor
@Suite(.serialized)
struct MarkdownEditorTests {
    @MainActor
    final class DocumentBox {
        var text: String
        init(_ text: String) { self.text = text }
    }

    @MainActor
    final class Harness {
        let box: DocumentBox
        let controller = EditorController()
        let coordinator: MarkdownEditor.Coordinator
        let webView: WKWebView

        init(_ source: String, fileURL: URL? = nil) {
            _ = NSApplication.shared
            box = DocumentBox(source)
            let box = box
            let parent = MarkdownEditor(text: Binding(get: { box.text }, set: { box.text = $0 }),
                                        sourceMode: false, controller: controller, fileURL: fileURL)
            coordinator = MarkdownEditor.Coordinator(parent)
            coordinator.assets.documentURL = fileURL
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.userContentController.add(coordinator, name: "editor")
            config.setURLSchemeHandler(coordinator.assets, forURLScheme: "local-md")
            webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 900), configuration: config)
            coordinator.webView = webView
            controller.webView = webView
            webView.navigationDelegate = coordinator
            webView.loadFileURL(MarkdownEditor.resourceURL, allowingReadAccessTo: MarkdownEditor.resourceURL.deletingLastPathComponent())
        }

        func evaluate(_ code: String) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                webView.evaluateJavaScript(code) { value, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: String(describing: value ?? "")) }
                }
            }
        }

        func waitUntil(_ expression: String) async throws {
            for _ in 0..<300 {
                if (try? await evaluate(expression)) == "true" { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            let diagnostics = (try? await evaluate("JSON.stringify({state:window.localMarkdown?.inspect(), diagram:document.querySelector('.diagram')?.outerHTML, error:document.querySelector('.render-error')?.textContent})")) ?? "no diagnostics"
            throw NSError(domain: "EditorTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out: \(expression); \(controller.errorMessage ?? "no JS error"); \(diagnostics)"])
        }

        func close() {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
            webView.stopLoading()
        }
    }

    @Test func offlineRenderingEditingUndoAndModeChanges() async throws {
        let source = "# 中文😀\n\n**L2 (`reg_lambda`)**\n\n| A | B |\n| --- | ---: |\n| one | two |\n\n$x^2$\n\n- [ ] task\n\nEnd\n"
        let app = Harness(source)
        defer { app.close() }
        try await app.waitUntil("String(!!window.localMarkdown?.inspect().tables)")
        #expect(app.box.text == source)
        #expect(try await app.evaluate("String(localMarkdown.inspect().math)") == "1")
        #expect(try await app.evaluate("String(!!document.querySelector('strong code'))") == "true")
        #expect(app.controller.headings.map(\.title) == ["中文😀"])
        _ = try await app.evaluate("document.querySelector('input[data-task-line]').click(); 'clicked'")
        try await app.waitUntil("String(localMarkdown.inspect().text.includes('- [x] task'))")
        #expect(app.box.text == source.replacingOccurrences(of: "- [ ] task", with: "- [x] task"))
        _ = try await app.evaluate("localMarkdown.command('undo'); 'undo'")
        try await app.waitUntil("String(localMarkdown.inspect().text.includes('- [ ] task'))")
        #expect(app.box.text == source)
        _ = try await app.evaluate("localMarkdown.command('redo'); localMarkdown.update({sourceMode:true}); 'source'")
        #expect(try await app.evaluate("String(localMarkdown.inspect().rendered)") == "0")
        _ = try await app.evaluate("localMarkdown.update({sourceMode:false, fontSize:24, editorWidth:600}); 'live'")
        #expect(try await app.evaluate("String(localMarkdown.inspect().tables)") == "1")
        #expect(try await app.evaluate("getComputedStyle(document.documentElement).getPropertyValue('--editor-size')") == "24px")
        #expect(app.controller.errorMessage == nil)
    }

    @Test func fullExtensionsAndExternalReplacement() async throws {
        let source = "# Start\n\n---\n\n$$\\frac{a}{b}$$\n\n> [!WARNING]\n> **notice**\n\ntext[^1]\n\n```mermaid\ngraph TD\nA[开始] --> B[结束]\n```\n\n[^1]: note\n"
        let app = Harness(source)
        defer { app.close() }
        try await app.waitUntil("String(!!window.localMarkdown?.inspect().diagrams)")
        #expect(try await app.evaluate("String(!!document.querySelector('.callout-warning'))") == "true")
        #expect(try await app.evaluate("String(!!document.querySelector('.footnotes'))") == "true")
        #expect(app.box.text == source)
        _ = try await app.evaluate("localMarkdown.update({text:'# Replacement\\n\\n**new**'}); 'replaced'")
        #expect(try await app.evaluate("String(!!document.querySelector('strong'))") == "true")
        _ = try await app.evaluate("localMarkdown.command('wrap','**'); 'edit'")
        try await app.waitUntil("String(localMarkdown.inspect().text.startsWith('****'))")
        #expect(app.controller.errorMessage == nil)
    }

    @Test func sanitizationAndCRLFPreservation() async throws {
        let source = "# Start\r\n\r\n<script>window.PWNED=1</script>\r\n\r\n<img src=x onerror=\"window.PWNED=1\">\r\n\r\n- [ ] 中文😀\r\n"
        let app = Harness(source)
        defer { app.close() }
        try await app.waitUntil("String(!!window.localMarkdown?.inspect().rendered)")
        #expect(try await app.evaluate("String(window.PWNED === undefined)") == "true")
        #expect(try await app.evaluate("String(document.querySelectorAll('[onerror]').length)") == "0")
        #expect(app.box.text == source)
        _ = try await app.evaluate("document.querySelector('input[data-task-line]').click(); 'clicked'")
        try await app.waitUntil("String(localMarkdown.inspect().text.includes('[x]'))")
        #expect(app.box.text == source.replacingOccurrences(of: "[ ]", with: "[x]"))
    }

    @Test func swiftUIHostProvidesVisibleEditor() async throws {
        let app = Harness("# Hosted\n\n**body**")
        defer { app.close() }
        let content = ContentView(document: Binding(get: { MarkdownDocument(text: app.box.text) },
                                                   set: { app.box.text = $0.text }))
        let host = NSHostingView(rootView: content.frame(width: 1000, height: 700))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .seconds(2))
        func findEditor(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.compactMap { findEditor($0) }.first
        }
        let web = try #require(findEditor(host))
        #expect(web.frame.width > 100)
        #expect(web.frame.height > 100)
        #expect(app.controller.headings.map(\.title) == ["Hosted"])
        let value: String = try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript("String(!!window.localMarkdown?.inspect().rendered)") { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: String(describing: value ?? "")) }
            }
        }
        #expect(value == "true")
    }

    @Test func bundledRelativeImageAndTyping() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = Harness("# Start\n\n![本地图片](assets/sample.svg)\n\nEnd\n", fileURL: root.appendingPathComponent("docs/格式验收.md"))
        defer { app.close() }
        try await app.waitUntil("String(!!document.querySelector('img')?.naturalWidth)")
        #expect(app.controller.errorMessage == nil)
        _ = try await app.evaluate("localMarkdown.command('jump',localMarkdown.inspect().text.length); document.execCommand('insertText',false,'中文输入😀'); 'typed'")
        try await app.waitUntil("String(localMarkdown.inspect().text.endsWith('中文输入😀'))")
        #expect(app.box.text.hasSuffix("中文输入😀"))
        _ = try await app.evaluate("localMarkdown.command('undo'); localMarkdown.command('find'); 'find'")
        try await app.waitUntil("String(!!document.querySelector('.cm-search'))")
        #expect(!app.box.text.contains("中文输入😀"))
    }

    @Test func typoraLayoutHasNoSourceWhitespaceOrExtraBlankLines() async throws {
        let source = "# Start\n\n### Heading\n\nFirst paragraph.\n\nSecond paragraph.\n\n- first\n\n- second\n\n```\na\nb\n```\n\nEnd\n"
        let app = Harness(source)
        defer { app.close() }
        try await app.waitUntil("String(!!document.querySelector('.rendered-block h3'))")
        _ = try await app.evaluate("localMarkdown.update({fontSize:16}); 'sized'")
        let metrics = try await app.evaluate("JSON.stringify({whiteSpace:getComputedStyle(document.querySelector('.rendered-block')).whiteSpace, font:getComputedStyle(document.querySelector('.rendered-block')).fontFamily, padding:getComputedStyle(document.querySelector('.cm-content')).padding, h3:getComputedStyle(document.querySelector('h3')).fontSize, list:document.querySelector('ul').getBoundingClientRect().height})")
        print("Layout metrics: \(metrics)")
        #expect(try await app.evaluate("getComputedStyle(document.querySelector('.rendered-block')).whiteSpace") == "normal")
        #expect(try await app.evaluate("getComputedStyle(document.querySelector('h3')).fontSize") == "24px")
        #expect(try await app.evaluate("getComputedStyle(document.querySelector('.cm-content')).paddingLeft") == "30px")
        #expect(try await app.evaluate("String(getComputedStyle(document.querySelector('.rendered-block')).fontFamily.includes('Open Sans'))") == "true")
        let before = try await app.evaluate("String(document.querySelectorAll('.rendered-block')[2].getBoundingClientRect().top - document.querySelectorAll('.rendered-block')[1].getBoundingClientRect().bottom)")
        _ = try await app.evaluate("localMarkdown.update({text:localMarkdown.inspect().text.replace('First paragraph.\\n\\nSecond', 'First paragraph.\\n\\n\\n\\nSecond')}); 'more blanks'")
        let after = try await app.evaluate("String(document.querySelectorAll('.rendered-block')[2].getBoundingClientRect().top - document.querySelectorAll('.rendered-block')[1].getBoundingClientRect().bottom)")
        #expect(before == after)
        _ = try await app.evaluate("localMarkdown.update({sourceMode:true}); 'source'")
        #expect(try await app.evaluate("String(document.querySelectorAll('.cm-collapsed-blank').length)") == "0")
        #expect(app.controller.errorMessage == nil)
    }

    @Test func appearanceChangesPreserveTextAndUndo() async throws {
        let source = "# Appearance\n\n中文 **body**\n"
        let app = Harness(source)
        defer { app.close() }
        try await app.waitUntil("String(!!window.localMarkdown?.inspect().rendered)")
        _ = try await app.evaluate("localMarkdown.command('wrap','**'); localMarkdown.update({dark:true}); 'dark'")
        #expect(try await app.evaluate("getComputedStyle(document.body).backgroundColor") == "rgb(30, 32, 36)")
        #expect(try await app.evaluate("getComputedStyle(document.documentElement).colorScheme") == "dark")
        _ = try await app.evaluate("localMarkdown.update({dark:false}); localMarkdown.command('undo'); 'light'")
        try await app.waitUntil("String(!localMarkdown.inspect().text.startsWith('****'))")
        #expect(app.box.text == source)
        #expect(try await app.evaluate("getComputedStyle(document.body).backgroundColor") == "rgb(255, 255, 255)")
    }

    @Test func longDocumentEditingAndExternalReload() async throws {
        let source = (0..<1000).map { "## 第 \($0) 节\n\n中文😀 **内容**，用于长文档编辑检查。\n\n" }.joined()
        let app = Harness(source)
        defer { app.close() }
        let window = NSWindow(contentRect: app.webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = app.webView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await app.waitUntil("String(window.localMarkdown?.inspect().headings?.length === 1000)")
        #expect(app.box.text == source)
        _ = try await app.evaluate("localMarkdown.command('jump',localMarkdown.inspect().text.length); document.execCommand('insertText',false,'末尾编辑'); 'edited'")
        try await app.waitUntil("String(localMarkdown.inspect().text.endsWith('末尾编辑'))")
        #expect(app.box.text == source + "末尾编辑")
        _ = try await app.evaluate("localMarkdown.command('undo'); 'undo'")
        try await app.waitUntil("String(!localMarkdown.inspect().text.endsWith('末尾编辑'))")
        #expect(app.box.text == source)
        // A disk reload delivered by the native document binding must reset history.
        app.box.text = "# 外部更新\r\n\r\n保留磁盘内容😀\r\n"
        app.coordinator.update()
        try await app.waitUntil("String(localMarkdown.inspect().text.startsWith('# 外部更新'))")
        _ = try await app.evaluate("localMarkdown.command('undo'); 'undo'")
        #expect(try await app.evaluate("localMarkdown.inspect().text") == app.box.text)
        #expect(app.controller.errorMessage == nil)
    }

    @Test func webReloadRestoresUnsavedNativeText() async throws {
        let app = Harness("# Recovery\n\nOriginal\n")
        defer { app.close() }
        try await app.waitUntil("String(!!window.localMarkdown?.inspect().rendered)")
        _ = try await app.evaluate("localMarkdown.command('jump',localMarkdown.inspect().text.length); document.execCommand('insertText',false,'未保存内容😀'); 'edited'")
        try await app.waitUntil("String(localMarkdown.inspect().text.endsWith('未保存内容😀'))")
        let unsaved = app.box.text
        app.coordinator.webViewWebContentProcessDidTerminate(app.webView)
        for _ in 0..<300 {
            if app.coordinator.ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(app.coordinator.ready)
        try await app.waitUntil("String(window.localMarkdown?.inspect().text.endsWith('未保存内容😀'))")
        #expect(app.box.text == unsaved)
        #expect(try await app.evaluate("localMarkdown.inspect().text") == unsaved)
    }

    @Test func configurableFormattingAndControlHeadingKeys() async throws {
        let app = Harness("新标题")
        defer { app.close() }
        try await app.waitUntil("String(!!window.localMarkdown?.inspect().text)")
        _ = try await app.evaluate("document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown',{key:'2',code:'Digit2',ctrlKey:true,bubbles:true})); 'heading'")
        try await app.waitUntil("String(localMarkdown.inspect().text === '## 新标题')")
        _ = try await app.evaluate("localMarkdown.command('undo'); localMarkdown.update({shortcuts:{heading3:'Mod-Alt-j'},controlHeadings:false}); document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown',{key:'j',code:'KeyJ',keyCode:74,altKey:true,metaKey:true,bubbles:true})); 'custom'")
        try await app.waitUntil("String(localMarkdown.inspect().text === '### 新标题')")
        _ = try await app.evaluate("localMarkdown.command('format','heading0'); 'body'")
        try await app.waitUntil("String(localMarkdown.inspect().text === '新标题')")
        _ = try await app.evaluate("document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown',{key:'2',code:'Digit2',ctrlKey:true,bubbles:true})); 'disabled'")
        #expect(try await app.evaluate("localMarkdown.inspect().text") == "新标题")
        #expect(app.controller.errorMessage == nil)
    }

    @Test func shortcutPreferencesPersistAndRejectConflicts() throws {
        var preferences = FormattingPreferences()
        let heading = try #require(FormattingAction.all.first { $0.id == "heading1" })
        #expect(preferences.conflict("Mod-b", for: heading) != nil)
        #expect(preferences.conflict("Mod-s", for: heading) != nil)
        #expect(preferences.conflict("Control-2", for: heading) != nil)
        #expect(preferences.conflict("Mod-Option-j", for: heading) == nil)
        preferences.overrides[heading.id] = "Mod-Option-j"
        preferences.toolbar.insert("table")
        let loaded = FormattingPreferences(json: preferences.json)
        #expect(loaded.webKeys[heading.id] == "Mod-Alt-j")
        #expect(loaded.toolbar.contains("table"))
        #expect(loaded.shortcut(for: heading) != nil)
    }

    @Test func relativeImagesResolveFromDocument() {
        let file = URL(fileURLWithPath: "/tmp/笔记/文档.md")
        #expect(MarkdownAssets.resolve("images/示例.png", documentURL: file)?.path == "/tmp/笔记/images/示例.png")
        #expect(MarkdownAssets.resolve("../图.png", documentURL: file)?.path == "/tmp/图.png")
        #expect(MarkdownAssets.resolve("/tmp/a.png", documentURL: nil)?.path == "/tmp/a.png")
        #expect(MarkdownAssets.resolve("image.png", documentURL: nil) == nil)
    }
}
