import Foundation

// Represents a single open file (Markdown or plain text).
// Mutable only through reload(); all other access is read-only.
final class MarkdownDocument: @unchecked Sendable {

    enum FileType {
        case markdown   // .md, .markdown
        case plainText  // .txt
    }

    let fileURL: URL
    let key: DocumentKey
    let fileType: FileType
    private(set) var text: String
    private(set) var encoding: String.Encoding
    // True when the file could not be decoded cleanly and a lossy fallback was used.
    private(set) var usedLossyEncoding: Bool = false

    var displayTitle: String { fileURL.lastPathComponent }
    var directoryURL: URL { fileURL.deletingLastPathComponent() }

    init(url: URL) throws {
        self.fileURL = url.standardizedFileURL
        self.key = DocumentKey(url: url)
        let ext = url.pathExtension.lowercased()
        self.fileType = (ext == "txt") ? .plainText : .markdown

        var enc: String.Encoding = .utf8
        var lossy = false
        do {
            text = try String(contentsOf: url, usedEncoding: &enc)
            encoding = enc
        } catch {
            let data = try Data(contentsOf: url)
            text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            encoding = .utf8
            lossy = true
        }
        usedLossyEncoding = lossy
    }

    // Re-read from disk (called on file-change events)
    func reload() throws {
        var enc: String.Encoding = encoding
        var lossy = false
        do {
            text = try String(contentsOf: fileURL, usedEncoding: &enc)
            encoding = enc
        } catch {
            let data = try Data(contentsOf: fileURL)
            text = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .isoLatin1)
                ?? text
            lossy = true
        }
        usedLossyEncoding = lossy
    }
}
