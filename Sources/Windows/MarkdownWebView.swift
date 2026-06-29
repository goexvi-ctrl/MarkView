import AppKit
import WebKit
import Combine

/// Global debug flags for developer diagnostics. All default to false (off).
enum DebugFlags {
    /// When true, MarkdownWebView writes MarkView-debug-*.html files next to the source document.
    @MainActor static var dumpHTML = false
}

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

    // Find-in-page (Cmd-F). The bar is a native AppKit view overlaid on the web
    // view; the actual searching happens in app.js. nil while the bar is hidden.
    // (internal access so the find logic in FindBar.swift can reach it.)
    var findBar: FindBarView?

    // When non-nil we are viewing a git historical snapshot instead of the live
    // on-disk document text. The live document (and its fileURL/base) is kept for
    // title, relative asset resolution, and "return to current".
    private var historicalOverride: (version: GitVersion, text: String)?

    /// Called by the coordinator when the JS bridge sends a history navigation request
    /// (from arrow keys or < > while reviewing versions).
    var handleHistoryStep: ((Int, Bool) -> Void)?

    /// Back-pointer to the owning DWC, set for windows that support git history navigation
    /// (including the dedicated historical snapshot windows opened via Shift-< etc.).
    weak var owningDocumentWindowController: DocumentWindowController?

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

        // Allow Safari Web Inspector attachment (required on macOS 13.3+ / recent Safari
        // for standalone apps using WKWebView). Only enable in debug builds.
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        // Enable WKWebView's native magnification gesture.
        // This provides "pinch-to-zoom" as a pure visual / magnifying-glass scale
        // of the current layout (no reflow of fonts, no change to our --zoom CSS var,
        // no impact on shrink-to-fit logic).
        //
        // This is deliberately separate from the menu-driven Cmd+/- zoom (which uses
        // the CSS --zoom variable to change effective font sizes and cause reflow).
        // See user clarification and BUG-2 in Tasks.md.
        webView.allowsMagnification = true

        // We do NOT add a custom NSMagnificationGestureRecognizer that drives
        // our CSS setZoom(). Doing so caused the exact symptoms reported:
        // - Pinch incorrectly affected font-size/reflow instead of pure visual scale.
        // - Glitchy snapping (especially around text selection).
        // - Effect only after selecting text (likely because selection + our JS
        //   style manipulation or shrink-fit recompute was fighting the gesture).
        //
        // Native magnification is the correct semantic for "pinch like a magnifying
        // glass". It is independent of our reflow zoom and should not depend on
        // text selection state.

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

    // Once we have done the initial full loadHTMLString, subsequent reloads
    // (Cmd-R, FileWatcher, etc.) use JS to replace only the article content.
    // This keeps the shell (scripts, styles, inspector state) stable and avoids
    // the duplicated head/body garbage that full re-loads can produce in WKWebView.
    private var hasInitialContentLoaded = false

    /// Writes the generated HTML (full document or just the inner body fragment)
    /// next to the source document for easy comparison with what the Web Inspector shows.
    /// Gated by DebugFlags.dumpHTML (off by default).
    private func debugDumpHTML(fullHTML: String? = nil, bodyFragment: String? = nil, sourceURL: URL) {
        let dir = sourceURL.deletingLastPathComponent()
        let ts = Int(Date().timeIntervalSince1970)
        let base = dir.appendingPathComponent("MarkView-debug-\(ts)").path

        if let full = fullHTML {
            let path = base + "-full.html"
            try? full.write(toFile: path, atomically: true, encoding: .utf8)
            NSLog("[MarkView] DEBUG: wrote FULL HTML passed to loadHTMLString → %@", path)
        }
        if let frag = bodyFragment {
            let path = base + "-body.html"
            try? frag.write(toFile: path, atomically: true, encoding: .utf8)
            NSLog("[MarkView] DEBUG: wrote BODY FRAGMENT from renderer → %@", path)
        }
    }

    func loadDocument() {
        dismissBanner()
        renderAndLoad(restoreScrollY: nil)
    }

    func reload(document: MarkdownDocument, restoreScrollY: Double) {
        self.document = document
        dismissBanner()
        renderAndLoad(restoreScrollY: restoreScrollY)
    }

    // MARK: - Git historical snapshots (H1)

    /// True while we are displaying a git historical revision instead of the live
    /// on-disk content of `document`. The live document (and its fileURL) remains
    /// for title, base directory (relative assets), and "return to current".
    var isViewingHistoricalVersion: Bool {
        historicalOverride != nil
    }

    /// Internal for history list reconciliation (DWC). Not for general use.
    var currentHistoricalSnapshot: (version: GitVersion, text: String)? {
        historicalOverride
    }

    /// Switch the view to render the provided historical text (from a git blob)
    /// while keeping the live `document` for identity, title, and baseURL.
    /// Shows the content as a full fresh load. The caller (usually DWC) is
    /// responsible for showing a persistent banner with the "Return" action.
    func enterHistoricalView(_ version: GitVersion, text: String) {
        historicalOverride = (version, text)
        // Historical content is a completely different snapshot; start fresh.
        hasInitialContentLoaded = false
        loadDocument()
    }

    /// Leave historical view and re-render from the live on-disk document text.
    /// The caller re-arms any file watcher and updates UI state (banner, title).
    func exitHistoricalView() {
        guard historicalOverride != nil else { return }
        historicalOverride = nil
        hasInitialContentLoaded = false
        loadDocument()
    }

    // MARK: - Comparison view (H2 basic)

    /// Loads a fully synthetic side-by-side comparison HTML page.
    /// Used for git version diff surfaces; the HTML is self-contained (headers + two
    /// pre-rendered bodies) and does not go through the normal single-document template.
    func loadComparisonHTML(_ html: String, baseURL: URL) {
        hasInitialContentLoaded = false
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Called when leaving a comparison view; the caller will typically trigger a
    /// normal document (or historical) reload immediately after.
    func exitComparisonView() {
        // Nothing special to unwind yet (no override state); the caller reloads content.
    }

    // Render HTML (potentially off-thread for large files), then load into webView.
    private func renderAndLoad(restoreScrollY: Double?) {
        let doc      = document
        let zoom     = currentZoom
        let settings = SettingsStore.shared
        let newNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        nonce = newNonce

        let isUpdate = hasInitialContentLoaded

        // Effective source for this render (may be a git historical snapshot).
        let sourceText = historicalOverride?.text ?? doc.text

        if doc.text.count > Self.asyncRenderThreshold {
            // Off-main render for large files (cmark-gfm work).
            Task.detached(priority: .userInitiated) {
                let body = MarkdownRenderer.render(text: sourceText, fileType: doc.fileType)
                await MainActor.run { [weak self] in
                    guard let self, self.nonce == newNonce else { return }
                    if DebugFlags.dumpHTML {
                        self.debugDumpHTML(
                            fullHTML: isUpdate ? nil : HTMLTemplate.build(body: body, settings: settings, zoomFactor: zoom, nonce: newNonce),
                            bodyFragment: body,
                            sourceURL: doc.fileURL
                        )
                    }

                    if isUpdate {
                        // Stable update path: only replace the article inner content.
                        let escaped = body.jsEscaped()
                        let js = "replaceDocumentContent(\"\(escaped)\")"
                        self.webView.evaluateJavaScript(js) { _, _ in
                            if let y = restoreScrollY { self.coordinator.pendingScrollRestore = y }
                            self.reapplyFindIfActive()
                        }
                    } else {
                        let html = HTMLTemplate.build(
                            body: body, settings: settings,
                            zoomFactor: zoom, nonce: newNonce
                        )
                        if let y = restoreScrollY { self.coordinator.pendingScrollRestore = y }
                        // Use the *directory* containing the .md as baseURL (not the .md file itself).
                        // Using the file URL as base can cause the WebContent process to try to
                        // "open" the .md file as a subresource (leading to the "Cannot open file"
                        // errors you are seeing in the inspector). The directory still resolves
                        // relative images/links correctly.
                        let baseURL = doc.fileURL.deletingLastPathComponent()
                        self.webView.loadHTMLString(html, baseURL: baseURL)
                        self.hasInitialContentLoaded = true
                        self.showEncodingBannerIfNeeded(for: doc)
                    }
                }
            }
        } else {
            let body = MarkdownRenderer.render(text: sourceText, fileType: doc.fileType)
            if DebugFlags.dumpHTML {
                self.debugDumpHTML(
                    fullHTML: isUpdate ? nil : HTMLTemplate.build(body: body, settings: settings, zoomFactor: zoom, nonce: newNonce),
                    bodyFragment: body,
                    sourceURL: doc.fileURL
                )
            }

            if isUpdate {
                let escaped = body.jsEscaped()
                let js = "replaceDocumentContent(\"\(escaped)\")"
                webView.evaluateJavaScript(js) { _, _ in
                    if let y = restoreScrollY { self.coordinator.pendingScrollRestore = y }
                    self.reapplyFindIfActive()
                }
            } else {
                let html = HTMLTemplate.build(
                    body: body, settings: settings,
                    zoomFactor: zoom, nonce: newNonce
                )
                if let y = restoreScrollY { self.coordinator.pendingScrollRestore = y }
                let baseURL = doc.fileURL.deletingLastPathComponent()
                webView.loadHTMLString(html, baseURL: baseURL)
                hasInitialContentLoaded = true
                showEncodingBannerIfNeeded(for: doc)
            }
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

    // MARK: - Bridge calls (Swift -> JS)

    func setZoom(_ factor: Double) {
        currentZoom = factor
        webView.evaluateJavaScript("setZoom(\(factor))", completionHandler: nil)
    }

    // Visual magnification (pinch / magnifying glass zoom).
    // Independent of the CSS reflow zoom (currentZoom / --zoom).
    var magnification: CGFloat {
        webView.magnification
    }

    func setMagnification(_ factor: CGFloat) {
        webView.magnification = factor
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

    // MARK: - Comparison (file-to-file) live scroll capture/restore
    // The comparison HTML uses two independent overflow:auto panes (#left-pane, #right-pane)
    // rather than the normal document scroll. These helpers talk directly to them.

    func captureComparisonScrolls(completion: @escaping @MainActor (Double, Double) -> Void) {
        let js = """
        (function(){
          const l = document.getElementById('left-pane');
          const r = document.getElementById('right-pane');
          return {left: l ? l.scrollTop : 0, right: r ? r.scrollTop : 0};
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            var ly: Double = 0
            var ry: Double = 0
            if let d = result as? [String: NSNumber] {
                ly = d["left"]?.doubleValue ?? 0
                ry = d["right"]?.doubleValue ?? 0
            } else if let d = result as? [String: Double] {
                ly = d["left"] ?? 0
                ry = d["right"] ?? 0
            }
            Task { @MainActor in completion(ly, ry) }
        }
    }

    func restoreComparisonScrolls(left: Double, right: Double) {
        // Setting scrollTop will fire the 'scroll' listeners the comparison template
        // installs for its custom scrollbar thumbs, so they should track.
        let js = """
        (function(){
          const lp = document.getElementById('left-pane');
          const rp = document.getElementById('right-pane');
          if (lp) lp.scrollTop = \(left);
          if (rp) rp.scrollTop = \(right);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func applySettings(_ settings: SettingsStore) {
        let json = settings.cssVariablesJSON()
        webView.evaluateJavaScript("applySettings(\(json))", completionHandler: nil)
    }

    func setAppearance(_ isDark: Bool) {
        // CSS variables + mermaid re-render happen in JS; no full document reload needed.
        let mode = isDark ? "dark" : "light"
        webView.evaluateJavaScript("setAppearance('\(mode)')", completionHandler: nil)
    }

    func scrollToAnchor(_ slug: String) {
        let escaped = slug.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("scrollToAnchor('\(escaped)')", completionHandler: nil)
    }

    // Manual reload support (e.g. Cmd-R) so the user can force a re-render
    // while keeping the window and Web Inspector open.
    func reloadCurrentDocument() {
        let url = document.fileURL
        do {
            let fresh = try MarkdownDocument(url: url)
            reload(document: fresh, restoreScrollY: lastScrollY)
        } catch {
            showBanner("Reload failed: \(error.localizedDescription)", style: .error, autoDismiss: true)
        }
    }
}

// Safe escaping for injecting an HTML fragment as a JS string literal from Swift.
private extension String {
    func jsEscaped() -> String {
        return self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
