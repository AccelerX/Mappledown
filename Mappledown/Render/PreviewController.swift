import SwiftUI
import WebKit

/// Owns one WKWebView that shows Resources/Web/preview.html and renders Markdown into it.
@MainActor
final class PreviewController: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published private(set) var mathErrors = 0
    @Published private(set) var isReady = false

    /// When true the page uses print colors and layout (for PDF export).
    var printMode = false
    var headingPageBreak = false

    private var config: RenderConfig?
    private var loadedTags: String?
    private var latestText = ""
    private var lastSentText: String?
    private var pendingWork: DispatchWorkItem?
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        let proxy = MessageProxy(owner: self)
        for name in ["ready", "rendered", "log"] {
            configuration.userContentController.add(proxy, name: name)
        }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = self
        webView.allowsLinkPreview = false
    }

    // MARK: Updating

    /// Shows `text` with `config`. Typing calls this often; `delay` groups quick changes.
    func update(text: String, config newConfig: RenderConfig, delay: TimeInterval = 0) {
        latestText = text
        if loadedTags != newConfig.tags {
            // Equation numbering is read by MathJax only at startup, so reload the page.
            config = newConfig
            load(newConfig)
            return
        }
        if newConfig != config {
            config = newConfig
            if isReady {
                setLook(newConfig)
                lastSentText = nil
            }
        }
        guard isReady else { return }
        pendingWork?.cancel()
        if delay <= 0 {
            sendRender()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.sendRender() }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Renders `text` and returns once MathJax has finished typesetting it.
    func renderAndWait(text: String, config newConfig: RenderConfig) async {
        update(text: text, config: newConfig, delay: 0)
        await waitUntilReady()
        latestText = text
        lastSentText = text
        _ = try? await webView.callAsyncJavaScript(
            "await Mappledown.render(t); return true;",
            arguments: ["t": text], in: nil, contentWorld: .page)
    }

    func setPrintMode(_ on: Bool, headingBreak: Bool) {
        printMode = on
        headingPageBreak = headingBreak
        guard isReady else { return }
        webView.callAsyncJavaScript("Mappledown.setPrintMode(on, h1)", arguments: ["on": on, "h1": headingBreak],
                                    in: nil, in: .page, completionHandler: nil)
    }

    /// The rendered body and MathJax's CSS, for HTML export.
    func exportParts() async -> (body: String, mathCSS: String) {
        let result = try? await webView.callAsyncJavaScript("return Mappledown.exportParts();", arguments: [:],
                                                            in: nil, contentWorld: .page)
        let dict = result as? [String: Any] ?? [:]
        return (dict["body"] as? String ?? "", dict["mathCSS"] as? String ?? "")
    }

    // MARK: Internals

    private func load(_ config: RenderConfig) {
        isReady = false
        loadedTags = config.tags
        lastSentText = nil
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let json = (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        controller.addUserScript(WKUserScript(source: "window.MAPPLEDOWN_CONFIG = \(json);",
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        guard let page = Bundle.main.url(forResource: "preview", withExtension: "html", subdirectory: "Web") else {
            assertionFailure("preview.html is missing from the app bundle")
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    private func setLook(_ config: RenderConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        webView.callAsyncJavaScript("Mappledown.setLook(c)", arguments: ["c": dict], in: nil, in: .page, completionHandler: nil)
    }

    private func sendRender() {
        guard isReady, latestText != lastSentText else { return }
        lastSentText = latestText
        webView.callAsyncJavaScript("Mappledown.render(t)", arguments: ["t": latestText], in: nil, in: .page, completionHandler: nil)
    }

    private func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            readyWaiters.append(c)
        }
    }

    fileprivate func receive(_ name: String, body: Any) {
        switch name {
        case "ready":
            isReady = true
            if printMode { setPrintMode(true, headingBreak: headingPageBreak) }
            let waiters = readyWaiters
            readyWaiters = []
            waiters.forEach { $0.resume() }
            sendRender()
        case "rendered":
            if let dict = body as? [String: Any], let errors = dict["errors"] as? Int {
                mathErrors = errors
            }
        default:
            #if DEBUG
            print("preview:", body)
            #endif
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Links to websites open in Safari; footnote jumps stay in the page.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The page was killed in the background (low memory). Load it again.
        if let config { loadedTags = nil; update(text: latestText, config: config) }
    }
}

/// Forwards page messages without the user content controller keeping the controller alive.
@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: PreviewController?
    init(owner: PreviewController) { self.owner = owner }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message.name, body: message.body)
    }
}

/// SwiftUI wrapper. The controller is kept outside so export can reuse the same page.
@MainActor
struct PreviewWebView: UIViewRepresentable {
    @ObservedObject var controller: PreviewController
    var text: String
    var config: RenderConfig
    var delay: TimeInterval = 0

    func makeUIView(context: Context) -> WKWebView {
        controller.update(text: text, config: config, delay: 0)
        return controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        controller.update(text: text, config: config, delay: delay)
    }
}
