import Foundation

// Rewrites document-relative (and absolute-path / file://) <img src> values
// to the mvimg:// custom scheme so they are served off disk by
// LocalImageSchemeHandler. loadHTMLString(_:baseURL:) does not grant the
// WebContent process read access to the document's directory, so plain
// file:// images never load; routing them through the scheme handler does.
// Pure Foundation so both the macOS and iPad targets can share it.
enum LocalImageRewriter {

    /// Rewrites local `<img src>` values in a rendered body. Network
    /// (http/https), data:, and asset:// sources are left untouched.
    /// `baseDir` is the directory containing the document.
    static func rewriteLocalImageSources(in body: String, baseDir: URL) -> String {
        // The body is post-sanitize, so img src values are always double-quoted.
        let pattern = "(<img\\b[^>]*?\\ssrc=\")([^\"]*)(\")"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return body
        }

        let ns = body as NSString
        var output = ""
        var lastEnd = 0
        for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            lastEnd = m.range.location + m.range.length

            let prefix = ns.substring(with: m.range(at: 1))
            let src    = ns.substring(with: m.range(at: 2))
            let suffix = ns.substring(with: m.range(at: 3))

            let newSrc = localImageSrc(src, baseDir: baseDir) ?? src
            output += prefix + newSrc + suffix
        }
        output += ns.substring(from: lastEnd)
        return output
    }

    /// Maps a single `src` to an `mvimg://` URL when it refers to a local file,
    /// or returns nil to leave it unchanged.
    private static func localImageSrc(_ src: String, baseDir: URL) -> String? {
        if src.hasPrefix("#") || src.isEmpty { return nil }

        // Detect an explicit URL scheme (e.g. http:, https:, data:, asset:, mvimg:).
        if let r = src.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) {
            let scheme = src[src.startIndex..<src.index(before: r.upperBound)].lowercased()
            guard scheme == "file" else { return nil }  // leave non-file schemes alone
            guard let path = URL(string: src)?.path, !path.isEmpty else { return nil }
            return mvimgURL(forPath: path)
        }

        // No scheme: a relative or absolute local filesystem path.
        let decoded = src.removingPercentEncoding ?? src
        let fileURL = decoded.hasPrefix("/")
            ? URL(fileURLWithPath: decoded)
            : URL(fileURLWithPath: decoded, relativeTo: baseDir)
        return mvimgURL(forPath: fileURL.standardizedFileURL.path)
    }

    private static func mvimgURL(forPath path: String) -> String? {
        var comps = URLComponents()
        comps.scheme = "mvimg"
        comps.host = "localhost"
        comps.path = path  // absolute, begins with "/"; URLComponents percent-encodes
        return comps.url?.absoluteString
    }
}
