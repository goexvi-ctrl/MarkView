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

// Custom URL scheme handler for mvimg:// URLs.
// Serves a local file from disk by the absolute path carried in the URL.
// Document-relative <img src="..."> paths are rewritten to mvimg:// at load
// time (see MarkdownWebView) because loadHTMLString(_:baseURL:) does not grant
// the WebContent process read access to the document's directory, so plain
// file:// images never load.
final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, !url.path.isEmpty else {
            fail(urlSchemeTask, status: 400)
            return
        }

        // url.path is the percent-decoded absolute filesystem path.
        let fileURL = URL(fileURLWithPath: url.path)

        guard let data = try? Data(contentsOf: fileURL) else {
            fail(urlSchemeTask, status: 404)
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: mimeType(for: fileURL.pathExtension),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask, status: Int) {
        let url = task.request.url ?? URL(string: "mvimg://error")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        task.didReceive(response)
        task.didFinish()
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "svg":          return "image/svg+xml"
        case "webp":         return "image/webp"
        case "bmp":          return "image/bmp"
        case "ico":          return "image/x-icon"
        case "tif", "tiff":  return "image/tiff"
        case "avif":         return "image/avif"
        case "heic":         return "image/heic"
        default:             return "application/octet-stream"
        }
    }
}
