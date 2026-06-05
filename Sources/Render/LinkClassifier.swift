import Foundation

// Classifies a navigation URL into a LinkAction.
// Pure function with no side effects; fully unit-testable.
enum LinkAction {
    case anchor(String)             // #fragment -> scroll in current doc
    case openMarkdown(URL)          // local .md/.markdown -> open/raise window
    case openWithDefaultApp(URL)    // local non-markdown file -> NSWorkspace
    case openExternal(URL)          // http/https/mailto/etc -> browser/mail
    case notFound(String)           // path could not be resolved to an existing file
}

enum LinkClassifier {

    static func classify(url: URL, documentURL: URL) -> LinkAction {
        let raw = url.absoluteString

        // Fragment-only string (#heading) — shouldn't normally reach here
        // when the bridge handler checks href.hasPrefix("#") first, but kept as safety net.
        if raw.hasPrefix("#") {
            let fragment = String(raw.dropFirst())
            return fragment.isEmpty ? .notFound("Empty anchor") : .anchor(fragment)
        }

        let scheme = url.scheme?.lowercased() ?? ""

        // URL whose only interesting component is the fragment (scheme == about/empty, path empty)
        if let frag = url.fragment, scheme.isEmpty || scheme == "about",
           url.path.isEmpty || url.path == "/" {
            return frag.isEmpty ? .notFound("Empty anchor") : .anchor(frag)
        }

        // Same-document fragment: url path resolves to the current document (or its directory)
        // e.g. file:///path/README.md#section after resolving #section against the file URL.
        if let frag = url.fragment, !frag.isEmpty, url.isFileURL {
            let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            let docPath     = documentURL.resolvingSymlinksInPath().standardizedFileURL.path
            let dirPath     = documentURL.deletingLastPathComponent()
                                         .resolvingSymlinksInPath().standardizedFileURL.path
            if resolvedPath == docPath || resolvedPath == dirPath {
                return .anchor(frag)
            }
        }

        // External schemes -> open in browser / mail
        if ["http", "https", "mailto", "tel"].contains(scheme) {
            return .openExternal(url)
        }

        // Resolve local file URL
        let resolved: URL
        if url.isFileURL {
            // Strip any fragment before resolving the path
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            let pathOnly = components?.url ?? url
            resolved = pathOnly.resolvingSymlinksInPath().standardizedFileURL
        } else {
            let docDir = documentURL.deletingLastPathComponent()
            guard let rel = URL(string: raw, relativeTo: docDir) else {
                return .notFound("Cannot resolve: \(raw)")
            }
            resolved = rel.resolvingSymlinksInPath().standardizedFileURL
        }

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return .notFound("File not found: \(resolved.lastPathComponent)")
        }

        let ext = resolved.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return .openMarkdown(resolved)
        }
        return .openWithDefaultApp(resolved)
    }
}
