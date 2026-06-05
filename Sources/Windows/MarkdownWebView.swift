import AppKit
import WebKit

// NSViewController that owns the WKWebView for a single document window.
@MainActor
final class MarkdownWebViewController: NSViewController {

    private(set) var webView: WKWebView!
    private var coordinator: WebViewCoordinator!
    // Exposed so WebViewCoordinator and DocumentWindowController can read it
    var document: MarkdownDocument
    private(set) var currentZoom: Double
    // Nonce regenerated on each load; coordinator validates incoming bridge messages
    private(set) var nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    // Cache for live-reload scroll restore (written by bridge, read by DWC)
    var lastScrollY: Double = 0

    init(document: MarkdownDocument, zoomFactor: Double) {
        self.document = document
        self.currentZoom = zoomFactor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        coordinator = WebViewCoordinator(viewController: self)
        let config = makeWebViewConfig()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        self.view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadDocument()
    }


    private func makeWebViewConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        // M3: file-access prefs (non-sandboxed build)
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // M3: asset:// custom scheme handler for bundled JS/CSS
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: "asset")

        // Bridge
        config.userContentController.add(coordinator, name: "bridge")

        return config
    }

    // MARK: - Loading

    func loadDocument() {
        nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: document.fileURL)
    }

    func reload(document: MarkdownDocument, restoreScrollY: Double) {
        self.document = document
        nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        coordinator.pendingScrollRestore = restoreScrollY
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: document.fileURL)
    }

    private func buildHTML() -> String {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let body = MarkdownRenderer.render(document: document, isDark: isDark)
        return HTMLTemplate.build(
            body: body,
            settings: SettingsStore.shared,
            zoomFactor: currentZoom,
            nonce: nonce
        )
    }

    // MARK: - Bridge calls (Swift -> JS)

    func setZoom(_ factor: Double) {
        currentZoom = factor
        webView.evaluateJavaScript("setZoom(\(factor))", completionHandler: nil)
    }

    func captureScrollPosition(completion: @escaping @MainActor (Double) -> Void) {
        webView.evaluateJavaScript("window.scrollY") { result, _ in
            let y = (result as? Double) ?? 0
            Task { @MainActor in completion(y) }
        }
    }

    func restoreScroll(_ y: Double) {
        webView.evaluateJavaScript("restoreScroll(\(y))", completionHandler: nil)
    }

    func applySettings(_ settings: SettingsStore) {
        let json = settings.cssVariablesJSON()
        webView.evaluateJavaScript("applySettings(\(json))", completionHandler: nil)
    }

    func setAppearance(_ isDark: Bool) {
        // Update the CSS theme via JS (handles non-mermaid content instantly)
        let mode = isDark ? "dark" : "light"
        webView.evaluateJavaScript("setAppearance('\(mode)')", completionHandler: nil)
        // Re-render the document so native mermaid diagrams use the new theme
        reload(document: document, restoreScrollY: lastScrollY)
    }

    func scrollToAnchor(_ slug: String) {
        let escaped = slug.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("scrollToAnchor('\(escaped)')", completionHandler: nil)
    }
}
