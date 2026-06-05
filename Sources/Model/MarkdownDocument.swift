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

    var displayTitle: String { fileURL.lastPathComponent }
    var directoryURL: URL { fileURL.deletingLastPathComponent() }

    init(url: URL) throws {
        self.fileURL = url.standardizedFileURL
        self.key = DocumentKey(url: url)
        let ext = url.pathExtension.lowercased()
        self.fileType = (ext == "txt") ? .plainText : .markdown

        var enc: String.Encoding = .utf8
        do {
            text = try String(contentsOf: url, usedEncoding: &enc)
            encoding = enc
        } catch {
            // Lossy UTF-8 fallback
            let data = try Data(contentsOf: url)
            text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            encoding = .utf8
        }
    }

    // Re-read from disk (called on file-change events)
    func reload() throws {
        var enc: String.Encoding = encoding
        do {
            text = try String(contentsOf: fileURL, usedEncoding: &enc)
            encoding = enc
        } catch {
            let data = try Data(contentsOf: fileURL)
            text = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .isoLatin1)
                ?? text
        }
    }
}
