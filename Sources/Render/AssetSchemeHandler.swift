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
// Serves a local image file by the absolute path carried in the URL.
// Document-relative <img src="..."> paths are rewritten to mvimg:// at load
// time (see LocalImageRewriter) because loadHTMLString(_:baseURL:) does not
// grant the WebContent process read access to the document's directory, so
// plain file:// images never load.
//
// What may be served is decided by LocalImagePolicy: by default only regular
// image files inside the current document's directory subtree. The owner sets
// documentDirectory before each load.
@MainActor
final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Directory of the document being shown; nil refuses everything.
    var documentDirectory: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, !url.path.isEmpty else {
            fail(urlSchemeTask, status: 400)
            return
        }

        let allowOutside = UserDefaults.standard.bool(forKey: LocalImagePolicy.allowOutsideDefaultsKey)
        let confine = documentDirectory.map {
            LocalImagePolicy.mustConfine(documentDirectory: $0, allowOutside: allowOutside)
        } ?? true

        // url.path is the percent-decoded absolute filesystem path.
        guard let fileURL = LocalImagePolicy.resolve(
            path: url.path, documentDirectory: documentDirectory, confine: confine
        ) else {
            fail(urlSchemeTask, status: 403)
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            fail(urlSchemeTask, status: 404)
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: LocalImagePolicy.mimeType(forPath: fileURL.path),
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
}
