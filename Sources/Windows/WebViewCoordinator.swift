import AppKit
import WebKit

// WKNavigationDelegate + WKUIDelegate + WKScriptMessageHandler for one document window.
@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    weak var viewController: MarkdownWebViewController?
    // Set by reload(); consumed in webView(_:didFinish:)
    var pendingScrollRestore: Double = 0

    init(viewController: MarkdownWebViewController) {
        self.viewController = viewController
    }

    // MARK: - WKNavigationDelegate

    // Async form avoids the "nearly matches" warning in Swift 6
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        // Allow the initial HTML load
        if navigationAction.navigationType == .other ||
           navigationAction.navigationType == .reload {
            return .allow
        }

        // All user-initiated navigations: classify and act
        guard let vc = viewController else { return .cancel }
        let action = LinkClassifier.classify(url: url, documentURL: vc.document.fileURL)
        handleLinkAction(action, from: vc)
        return .cancel
    }

    private func handleLinkAction(_ action: LinkAction, from vc: MarkdownWebViewController) {
        switch action {
        case .anchor(let slug):
            vc.scrollToAnchor(slug)
        case .openMarkdown(let url):
            DocumentWindowRegistry.shared.openDocument(url: url)
        case .openExternal(let url):
            NSWorkspace.shared.open(url)
        case .openWithDefaultApp(let url):
            NSWorkspace.shared.open(url)
        case .notFound(let message):
            showTransientBanner(message, in: vc.view.window)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if pendingScrollRestore != 0 {
            let y = pendingScrollRestore
            pendingScrollRestore = 0
            viewController?.restoreScroll(y)
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
            msgNonce == viewController?.nonce,
            let type = body["type"] as? String
        else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]
        handleBridgeMessage(type: type, payload: payload)
    }

    private func handleBridgeMessage(type: String, payload: [String: Any]) {
        guard let vc = viewController else { return }
        switch type {
        case "openLink":
            if let href = payload["href"] as? String {
                // Fragment-only links (#anchor) must be caught before URL resolution
                // because resolving against a base URL loses the "anchor-only" signal.
                if href.hasPrefix("#") {
                    vc.scrollToAnchor(String(href.dropFirst()))
                } else if let url = URL(string: href, relativeTo: vc.document.fileURL)?.standardized {
                    let action = LinkClassifier.classify(url: url, documentURL: vc.document.fileURL)
                    handleLinkAction(action, from: vc)
                }
            }
        case "copyCode":
            if let text = payload["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "requestZoom":
            switch payload["direction"] as? String {
            case "in":    zoomIn()
            case "out":   zoomOut()
            case "reset": zoomReset()
            default: break
            }
        case "domReady":
            break
        case "scrollPosition":
            if let y = payload["y"] as? Double {
                vc.lastScrollY = y
            }
        default:
            break
        }
    }

    // MARK: - Helpers

    private func showTransientBanner(_ message: String, in window: NSWindow?) {
        viewController?.showBanner(message, style: .warning, autoDismiss: true)
    }
}
