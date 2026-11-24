import Foundation

// Decides which local files the mvimg:// scheme handler may serve.
//
// A rendered document is untrusted input (it may have arrived over the
// network through ropend), so the handler must not become a general file
// reader. By default only regular image files inside the document's own
// directory (or a subdirectory of it) are served; symlinks are resolved
// before the check, so a link cannot point outside. The user may relax the
// directory confinement for ordinary local documents with the
// "allowImagesOutsideDocumentFolder" default; documents in ropend's spool
// are always confined.
//
// Pure Foundation so the macOS and iPad targets and the SPM tests share it.
enum LocalImagePolicy {

    /// Image extensions the handler will serve, with their MIME types.
    /// Keep in step with ropend's "assets ext" list for type md.
    static let mimeTypes: [String: String] = [
        "png":  "image/png",
        "jpg":  "image/jpeg",
        "jpeg": "image/jpeg",
        "gif":  "image/gif",
        "svg":  "image/svg+xml",
        "webp": "image/webp",
        "bmp":  "image/bmp",
        "ico":  "image/x-icon",
        "tif":  "image/tiff",
        "tiff": "image/tiff",
        "avif": "image/avif",
        "heic": "image/heic",
    ]

    /// UserDefaults key: when true, local documents (not ropend's) may show
    /// images from anywhere on disk. Not exposed in the Settings UI; set with
    ///   defaults write <bundle-id> allowImagesOutsideDocumentFolder -bool YES
    static let allowOutsideDefaultsKey = "allowImagesOutsideDocumentFolder"

    /// ropend's default spool directory. Documents under it are always
    /// confined to their own directory.
    static var ropendSpoolDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/ropend", isDirectory: true)
    }

    /// Whether images for a document in `documentDirectory` must come from
    /// that directory's subtree.
    static func mustConfine(documentDirectory: URL, allowOutside: Bool,
                            spoolDirectory: URL = ropendSpoolDirectory) -> Bool {
        if !allowOutside { return true }
        return isInside(realPath(documentDirectory), root: realPath(spoolDirectory))
    }

    /// Resolves a request for absolute filesystem path `path` to the file to
    /// serve, or nil if it must be refused. `documentDirectory` nil with
    /// `confine` true refuses everything.
    static func resolve(path: String, documentDirectory: URL?, confine: Bool) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        guard mimeTypes[ext] != nil else { return nil }

        // Resolve symlinks and ".." before any containment check.
        let target = realPath(URL(fileURLWithPath: path))
        // The extension must also hold for the file actually read, so a
        // link named x.png cannot serve a non-image file.
        guard mimeTypes[(target as NSString).pathExtension.lowercased()] != nil else { return nil }

        if confine {
            guard let dir = documentDirectory else { return nil }
            guard isInside(target, root: realPath(dir)) else { return nil }
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target, isDirectory: &isDir), !isDir.boolValue,
              let attrs = try? FileManager.default.attributesOfItem(atPath: target),
              attrs[.type] as? FileAttributeType == .typeRegular
        else { return nil }
        return URL(fileURLWithPath: target)
    }

    static func mimeType(forPath path: String) -> String {
        mimeTypes[(path as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
    }

    // MARK: - Helpers

    /// Absolute path with symlinks and "."/".." resolved (realpath(3)).
    /// For a path that does not exist, the standardized path is returned.
    static func realPath(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        guard let r = realpath(p, nil) else { return p }
        defer { free(r) }
        return String(cString: r)
    }

    /// True if `path` is strictly below `root` (both already real paths).
    static func isInside(_ path: String, root: String) -> Bool {
        let r = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(r)
    }
}
