import SwiftUI
import WebKit

// Command surface for the toolbar: holds the web view, per-document zoom
// (persisted via the shared ZoomMemory), and JS-side setting updates.
@MainActor
final class WebViewProxy: ObservableObject {

    private(set) weak var webView: WKWebView?
    private var documentKey: DocumentKey?
    private(set) var currentZoom: Double = 1.0

    func attach(webView: WKWebView, fileURL: URL?) {
        self.webView = webView
        if let fileURL {
            let key = DocumentKey(url: fileURL)
            documentKey = key
            currentZoom = ZoomMemory.shared.zoom(for: key) ?? 1.0
        }
    }

    func zoomIn()    { setZoom(min(3.0, currentZoom + 0.1)) }
    func zoomOut()   { setZoom(max(0.5, currentZoom - 0.1)) }
    func zoomReset() { setZoom(1.0) }

    private func setZoom(_ factor: Double) {
        currentZoom = factor
        webView?.evaluateJavaScript("setZoom(\(factor))", completionHandler: nil)
        if let documentKey {
            ZoomMemory.shared.setZoom(factor, for: documentKey)
        }
    }

    func applySettings() {
        let json = SettingsStore.shared.cssVariablesJSON()
        webView?.evaluateJavaScript("applySettings(\(json))", completionHandler: nil)
    }

    func presentFind() {
        webView?.findInteraction?.presentFindNavigator(showingReplace: false)
    }
}

// WKWebView host. Mirrors the macOS MarkdownWebViewController pipeline:
// render via MarkdownRenderer -> LocalImageRewriter -> HTMLTemplate, load
// with the document's directory as baseURL, asset:// + mvimg:// scheme
// handlers, and the nonce-validated JS bridge.
struct PadWebView: UIViewRepresentable {

    let text: String
    let fileType: MarkdownDocument.FileType
    let fileURL: URL?
    let allowUnsafeHTML: Bool
    let proxy: WebViewProxy
    // When set (tab context), the position is restored on creation and kept
    // updated from JS scroll events, so switching tabs preserves the place.
    let scrollY: Binding<Double>?
    let onEvent: (PadWebEvent) -> Void

    func makeCoordinator() -> PadWebCoordinator {
        PadWebCoordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: "asset")
        // Confined to the document's directory by LocalImagePolicy.
        config.setURLSchemeHandler(coordinator.imageHandler, forURLScheme: "mvimg")
        config.userContentController.add(coordinator, name: "bridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.isFindInteractionEnabled = true
        #if DEBUG
        webView.isInspectable = true
        #endif

        proxy.attach(webView: webView, fileURL: fileURL)
        coordinator.webView = webView
        coordinator.currentDark = context.environment.colorScheme == .dark
        coordinator.onScroll = { [scrollY] y in scrollY?.wrappedValue = y }
        coordinator.load(
            text: text, fileType: fileType, fileURL: fileURL,
            allowUnsafeHTML: allowUnsafeHTML, zoom: proxy.currentZoom,
            restoreScroll: scrollY?.wrappedValue ?? 0
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onScroll = { [scrollY] y in scrollY?.wrappedValue = y }
        if coordinator.loadedText != text || coordinator.loadedAllowUnsafeHTML != allowUnsafeHTML {
            coordinator.load(
                text: text, fileType: fileType, fileURL: fileURL,
                allowUnsafeHTML: allowUnsafeHTML, zoom: proxy.currentZoom,
                restoreScroll: coordinator.lastScrollY
            )
        }
        let dark = context.environment.colorScheme == .dark
        if coordinator.currentDark != dark {
            coordinator.currentDark = dark
            coordinator.applyAppearance()
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: PadWebCoordinator) {
        // The user content controller retains its handlers; break the cycle.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
    }
}

@MainActor
final class PadWebCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    weak var webView: WKWebView?
    // Serves mvimg:// images; documentDirectory is set on every load.
    let imageHandler = LocalImageSchemeHandler()
    private let onEvent: (PadWebEvent) -> Void

    // Nonce regenerated on each load; incoming bridge messages must echo it.
    private(set) var nonce = ""
    private(set) var loadedText: String?
    private(set) var loadedAllowUnsafeHTML = false
    private var documentURL: URL?
    var currentDark = false
    var lastScrollY: Double = 0
    var onScroll: ((Double) -> Void)?
    private var pendingScrollRestore: Double = 0

    // Large-file threshold: render off the main thread above this character count.
    private static let asyncRenderThreshold = 100_000

    init(onEvent: @escaping (PadWebEvent) -> Void) {
        self.onEvent = onEvent
    }

    // MARK: - Loading

    func load(
        text: String,
        fileType: MarkdownDocument.FileType,
        fileURL: URL?,
        allowUnsafeHTML: Bool,
        zoom: Double,
        restoreScroll: Double = 0
    ) {
        guard let webView else { return }
        loadedText = text
        loadedAllowUnsafeHTML = allowUnsafeHTML
        documentURL = fileURL
        pendingScrollRestore = restoreScroll

        let newNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        nonce = newNonce
        let baseDir = fileURL?.deletingLastPathComponent()
        imageHandler.documentDirectory = baseDir

        if text.count > Self.asyncRenderThreshold {
            Task.detached(priority: .userInitiated) {
                let rendered = MarkdownRenderer.render(
                    text: text, fileType: fileType, allowUnsafeHTML: allowUnsafeHTML
                )
                let body = baseDir.map {
                    LocalImageRewriter.rewriteLocalImageSources(in: rendered, baseDir: $0)
                } ?? rendered
                await MainActor.run { [weak self] in
                    guard let self, self.nonce == newNonce else { return }
                    let html = HTMLTemplate.build(
                        body: body, settings: SettingsStore.shared,
                        zoomFactor: zoom, nonce: newNonce
                    )
                    self.webView?.loadHTMLString(html, baseURL: baseDir)
                }
            }
        } else {
            let rendered = MarkdownRenderer.render(
                text: text, fileType: fileType, allowUnsafeHTML: allowUnsafeHTML
            )
            let body = baseDir.map {
                LocalImageRewriter.rewriteLocalImageSources(in: rendered, baseDir: $0)
            } ?? rendered
            let html = HTMLTemplate.build(
                body: body, settings: SettingsStore.shared,
                zoomFactor: zoom, nonce: newNonce
            )
            webView.loadHTMLString(html, baseURL: baseDir)
        }
    }

    func applyAppearance() {
        let mode = currentDark ? "dark" : "light"
        webView?.evaluateJavaScript("setAppearance('\(mode)')", completionHandler: nil)
    }

    private func scrollToAnchor(_ slug: String) {
        let escaped = slug.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("scrollToAnchor('\(escaped)')", completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        if navigationAction.navigationType == .other ||
           navigationAction.navigationType == .reload {
            return .allow
        }
        let docURL = documentURL ?? URL(fileURLWithPath: "/untitled.md")
        handle(action: LinkClassifier.classify(url: url, documentURL: docURL))
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if pendingScrollRestore != 0 {
            let y = pendingScrollRestore
            pendingScrollRestore = 0
            webView.evaluateJavaScript("restoreScroll(\(y))", completionHandler: nil)
        }
        // Sync mermaid + data-color-scheme with the current appearance; the
        // CSS itself already follows prefers-color-scheme.
        if currentDark { applyAppearance() }
    }

    // MARK: - Link actions

    private func handle(action: LinkAction) {
        switch action {
        case .anchor(let slug):
            scrollToAnchor(slug)
        case .openMarkdown(let url):
            onEvent(.openMarkdown(url))
        case .openExternal(let url):
            UIApplication.shared.open(url)
        case .openWithDefaultApp(let url):
            onEvent(.banner("Only Markdown and text files can be opened here (\(url.lastPathComponent))."))
        case .notFound(let message):
            onEvent(.banner(message))
        }
    }

    // MARK: - WKScriptMessageHandler (JS -> Swift bridge)

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            let body = message.body as? [String: Any],
            let msgNonce = body["nonce"] as? String,
            msgNonce == nonce,
            let type = body["type"] as? String
        else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]
        switch type {
        case "openLink":
            if let href = payload["href"] as? String {
                // Fragment-only links must be caught before URL resolution
                // because resolving against a base loses the anchor-only signal.
                if href.hasPrefix("#") {
                    scrollToAnchor(String(href.dropFirst()))
                } else {
                    let docURL = documentURL ?? URL(fileURLWithPath: "/untitled.md")
                    if let url = URL(string: href, relativeTo: docURL)?.standardized {
                        handle(action: LinkClassifier.classify(url: url, documentURL: docURL))
                    }
                }
            }
        case "copyCode":
            if let text = payload["text"] as? String {
                UIPasteboard.general.string = text
            }
        case "scrollPosition":
            if let y = payload["y"] as? Double {
                lastScrollY = y
                onScroll?(y)
            }
        default:
            break  // domReady, historyStep (git-only) are ignored on iPad
        }
    }
}
