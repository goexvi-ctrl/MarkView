import Foundation

// Canonical identifier for a document URL.
// Uses resolved symlinks + standardized path + lowercased path on
// case-insensitive volumes, so symlinks / ./ ../ and case variants
// all map to the same key.
struct DocumentKey: Hashable, Sendable {

    let canonicalPath: String

    init(url: URL) {
        let resolved = url
            .resolvingSymlinksInPath()
            .standardizedFileURL
        // macOS HFS+ and APFS are case-insensitive by default
        canonicalPath = resolved.path.lowercased()
    }

    // Convenience for already-resolved paths
    init(canonicalPath: String) {
        self.canonicalPath = canonicalPath.lowercased()
    }
}
