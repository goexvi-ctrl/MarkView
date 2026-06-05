import WebKit

// Custom URL scheme handler for asset:// URLs.
// Serves files from the app bundle's WebAssets directory.
// Path traversal (../) is rejected with a 403.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, status: 400)
            return
        }

        let relativePath = url.host.map { $0 + url.path } ?? url.path

        // Reject path traversal
        guard !relativePath.contains("..") else {
            fail(urlSchemeTask, status: 403)
            return
        }

        guard let assetURL = Bundle.main.url(
            forResource: nil,
            withExtension: nil,
            subdirectory: "WebAssets/\(relativePath)"
        ) ?? Bundle.main.url(
            forResource: (relativePath as NSString).lastPathComponent.isEmpty
                ? nil
                : (relativePath as NSString).deletingPathExtension,
            withExtension: (relativePath as NSString).pathExtension.isEmpty
                ? nil
                : (relativePath as NSString).pathExtension,
            subdirectory: "WebAssets"
        ) else {
            fail(urlSchemeTask, status: 404)
            return
        }

        guard let data = try? Data(contentsOf: assetURL) else {
            fail(urlSchemeTask, status: 500)
            return
        }

        let mimeType = mimeType(for: assetURL.pathExtension)
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask, status: Int) {
        let url = task.request.url ?? URL(string: "asset://error")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        task.didReceive(response)
        task.didFinish()
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "js":   return "application/javascript"
        case "css":  return "text/css"
        case "html": return "text/html"
        case "svg":  return "image/svg+xml"
        case "png":  return "image/png"
        case "woff2": return "font/woff2"
        case "woff":  return "font/woff"
        default:     return "application/octet-stream"
        }
    }
}
