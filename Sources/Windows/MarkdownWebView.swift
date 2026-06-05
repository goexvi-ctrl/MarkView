import AppKit
import WebKit
import Combine

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
    private var appearanceCancellable: AnyCancellable?

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
        observeAppearance()
    }

    private func observeAppearance() {
        appearanceCancellable = NSApp.publisher(for: \.effectiveAppearance)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self?.setAppearance(isDark)
            }
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

    // Large-file threshold: render off the main thread above this character count.
    private static let asyncRenderThreshold = 100_000

    func loadDocument() {
        dismissBanner()
        renderAndLoad(restoreScrollY: nil)
    }

    func reload(document: MarkdownDocument, restoreScrollY: Double) {
        self.document = document
        dismissBanner()
        renderAndLoad(restoreScrollY: restoreScrollY)
    }

    // Render HTML (potentially off-thread for large files), then load into webView.
    private func renderAndLoad(restoreScrollY: Double?) {
        let doc      = document
        let zoom     = currentZoom
        let settings = SettingsStore.shared
        let newNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        nonce = newNonce

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if doc.text.count > Self.asyncRenderThreshold {
            // Off-main render: only the cmark-gfm/mermaid work is heavy.
            // HTMLTemplate.build (settings access) runs back on main actor.
            Task.detached(priority: .userInitiated) {
                let body = MarkdownRenderer.render(document: doc, isDark: isDark)
                await MainActor.run { [weak self] in
                    guard let self, self.nonce == newNonce else { return }
                    let html = HTMLTemplate.build(
                        body: body, settings: settings,
                        zoomFactor: zoom, nonce: newNonce
                    )
                    if let y = restoreScrollY { self.coordinator.pendingScrollRestore = y }
                    self.webView.loadHTMLString(html, baseURL: doc.fileURL)
                    self.showEncodingBannerIfNeeded(for: doc)
                }
            }
        } else {
            let body = MarkdownRenderer.render(document: doc, isDark: isDark)
            let html = HTMLTemplate.build(
                body: body, settings: settings,
                zoomFactor: zoom, nonce: newNonce
            )
            if let y = restoreScrollY { coordinator.pendingScrollRestore = y }
            webView.loadHTMLString(html, baseURL: doc.fileURL)
            showEncodingBannerIfNeeded(for: doc)
        }
    }

    private func showEncodingBannerIfNeeded(for doc: MarkdownDocument) {
        if doc.usedLossyEncoding {
            showBanner(
                "\(doc.displayTitle) contains invalid UTF-8 and was decoded with a lossy fallback.",
                style: .warning, autoDismiss: true
            )
        }
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
