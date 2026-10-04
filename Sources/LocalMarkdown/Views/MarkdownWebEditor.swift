import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct EditorHeading: Identifiable, Equatable {
    let title: String
    let level: Int
    let location: Int
    var id: Int { location }
}

@MainActor
@Observable
final class EditorController {
    weak var webView: WKWebView?
    var headings: [EditorHeading] = []
    var errorMessage: String?

    func command(_ name: String, argument: Any = "") {
        webView?.callAsyncJavaScript("window.localMarkdown?.command(name, argument)",
                                    arguments: ["name": name, "argument": argument], in: nil, in: .page) { _ in }
    }
    func find() { command("find") }
    func wrap(_ marker: String) { command("wrap", argument: marker) }
    func jump(to location: Int) { command("jump", argument: location) }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let sourceMode: Bool
    let controller: EditorController
    var fileURL: URL?
    var fontSize: Double = 16
    var editorWidth: Double = 800
    var formattingJSON: String = ""

    static var resourceURL: URL {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor")
        ?? Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Editor")!
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "editor")
        configuration.setURLSchemeHandler(context.coordinator.assets, forURLScheme: "local-md")
        let webView = EditorWebView(frame: .zero, configuration: configuration)
        webView.appearanceChanged = { [weak coordinator = context.coordinator] in coordinator?.update() }
        webView.navigationDelegate = context.coordinator
        webView.setAccessibilityLabel("Markdown 编辑器")
        context.coordinator.webView = webView
        controller.webView = webView
        context.coordinator.assets.documentURL = fileURL
        webView.loadFileURL(Self.resourceURL, allowingReadAccessTo: Self.resourceURL.deletingLastPathComponent())
        return webView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 720,
               height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 600)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.assets.documentURL = fileURL
        context.coordinator.update()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownEditor
        weak var webView: WKWebView?
        let assets = MarkdownAssets()
        var ready = false
        var lastText: String?
        private var lastSettings: String?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func update() {
            guard ready, let webView else { return }
            let dark = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let settings = "\(parent.formattingJSON)-\(parent.sourceMode)-\(parent.fontSize)-\(parent.editorWidth)-\(dark)-\(parent.fileURL?.absoluteString ?? "")"
            guard lastText != parent.text || settings != lastSettings else { return }
            var payload: [String: Any] = ["sourceMode": parent.sourceMode, "fontSize": parent.fontSize,
                                          "editorWidth": parent.editorWidth, "dark": dark,
                                          "documentURL": parent.fileURL?.absoluteString ?? "",
                                          "shortcuts": FormattingPreferences(json: parent.formattingJSON).webKeys,
                                          "controlHeadings": FormattingPreferences(json: parent.formattingJSON).controlHeadings]
            if lastText != parent.text { payload["text"] = parent.text }
            lastText = parent.text
            lastSettings = settings
            webView.callAsyncJavaScript("window.localMarkdown.update(payload)", arguments: ["payload": payload], in: nil, in: .page) { [weak self] result in
                if case .failure(let error) = result { self?.parent.controller.errorMessage = error.localizedDescription }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                lastText = nil
                lastSettings = nil
                parent.controller.errorMessage = nil
                update()
            case "change":
                guard let text = body["text"] as? String else { return }
                lastText = text
                parent.text = text
            case "outline":
                let headings = body["headings"] as? [[String: Any]] ?? []
                parent.controller.headings = headings.compactMap { item in
                    guard let title = item["title"] as? String, let level = item["level"] as? Int,
                          let from = item["from"] as? Int else { return nil }
                    return EditorHeading(title: title, level: level, location: from)
                }
            case "copy":
                if let text = body["text"] as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            case "link":
                if let href = body["href"] as? String { openLink(href) }
            case "error": parent.controller.errorMessage = body["message"] as? String
            default: break
            }
        }

        private func openLink(_ href: String) {
            if let url = URL(string: href), let scheme = url.scheme?.lowercased() {
                if ["https", "http", "mailto"].contains(scheme) { NSWorkspace.shared.open(url) }
                else if scheme == "file" { NSWorkspace.shared.open(url) }
            } else if let base = parent.fileURL?.deletingLastPathComponent(),
                      let url = URL(string: href, relativeTo: base.appendingPathComponent("", isDirectory: true))?.absoluteURL {
                NSWorkspace.shared.open(url)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            // Only the bundled editor may navigate this WebView. Document links open externally.
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url { openLink(url.absoluteString) }
                decisionHandler(.cancel)
            } else { decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel) }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            webView.reload()
        }
    }
}

@MainActor
final class MarkdownAssets: NSObject, WKURLSchemeHandler {
    var documentURL: URL?

    static func resolve(_ path: String, documentURL: URL?) -> URL? {
        let decoded = path.removingPercentEncoding ?? path
        if let url = URL(string: decoded), url.isFileURL { return url.standardizedFileURL }
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded).standardizedFileURL }
        guard let documentURL else { return nil }
        return documentURL.deletingLastPathComponent().appendingPathComponent(decoded).standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let request = urlSchemeTask.request.url,
              let path = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value,
              let url = Self.resolve(path, documentURL: documentURL),
              let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let data = try? Data(contentsOf: url) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(URLResponse(url: request, mimeType: type.preferredMIMEType ?? "application/octet-stream",
                                            expectedContentLength: data.count, textEncodingName: nil))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
final class EditorWebView: WKWebView {
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}
