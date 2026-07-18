import Foundation

// markview:// URL scheme support.
//
// Another app opens MarkView programmatically (launching it if necessary) via
// UIApplication.open with one of:
//
//   markview://view?text=<percent-encoded UTF-8 markdown>[&name=Title.md]
//   markview://view?b64=<base64 UTF-8 markdown, std or URL-safe>[&name=Title.md]
//   markview://view?file=<percent-encoded absolute path or file:// URL>
//
// The optional name provides the tab title; a .txt name renders as plain
// text. file= only works for locations this app can read (its own container,
// app-group containers, or other shared paths) - iOS sandboxing applies.
// Inline text is bounded by practical URL length (tens of KB); larger content
// should be handed over as a file instead.
//
// Parsed URLs are delivered to DocumentTabsView.onOpenURL, which shows the
// content as a tab (inline payloads reuse a tab with the same name).
struct SchemePayload {
    let text: String
    let name: String
    let fileType: MarkdownDocument.FileType
    let fileURL: URL?        // set for file= opens (base dir for relative images)
    let usedLossyEncoding: Bool
    // file= handoffs only: the sender marks the file as temporary and MarkView
    // deletes it when the user closes the tab (deleteonclose=1).
    let deleteOnClose: Bool
}

struct SchemeError: Error {
    let message: String
}

enum MarkViewURLParser {

    static func parse(_ url: URL) -> Result<SchemePayload, SchemeError> {
        guard url.scheme?.lowercased() == "markview" else {
            return .failure(SchemeError(message: "Not a markview:// URL."))
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(SchemeError(message: "Malformed markview:// URL."))
        }
        let action = components.host?.lowercased() ?? ""
        guard action.isEmpty || action == "view" else {
            return .failure(SchemeError(message: "Unknown markview:// action \"\(action)\" (expected \"view\")."))
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name.lowercased()] = item.value
        }

        if let path = params["file"], !path.isEmpty {
            let deleteOnClose = ["1", "true", "yes"]
                .contains((params["deleteonclose"] ?? "").lowercased())
            return parseFile(path, deleteOnClose: deleteOnClose)
        }
        if let b64 = params["b64"], !b64.isEmpty {
            guard let data = decodeBase64(b64), let text = String(data: data, encoding: .utf8) else {
                return .failure(SchemeError(message: "The b64 parameter is not valid base64-encoded UTF-8."))
            }
            return .success(inlinePayload(text: text, name: params["name"]))
        }
        if let text = params["text"], !text.isEmpty {
            return .success(inlinePayload(text: text, name: params["name"]))
        }
        return .failure(SchemeError(message: "markview://view needs a text=, b64=, or file= parameter."))
    }

    private static func inlinePayload(text: String, name: String?) -> SchemePayload {
        let displayName = (name?.isEmpty == false) ? name! : "Untitled.md"
        let type: MarkdownDocument.FileType =
            (displayName as NSString).pathExtension.lowercased() == "txt" ? .plainText : .markdown
        return SchemePayload(
            text: text, name: displayName, fileType: type,
            fileURL: nil, usedLossyEncoding: false, deleteOnClose: false
        )
    }

    private static func parseFile(_ raw: String, deleteOnClose: Bool) -> Result<SchemePayload, SchemeError> {
        let fileURL: URL
        if raw.hasPrefix("file://"), let u = URL(string: raw) {
            fileURL = URL(fileURLWithPath: u.path)
        } else if raw.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: raw)
        } else {
            return .failure(SchemeError(message: "file= must be an absolute path or file:// URL."))
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .failure(SchemeError(message: "Cannot read \(fileURL.lastPathComponent): "
                + "the path is outside this app's sandbox or does not exist."))
        }

        let text: String
        let lossy: Bool
        if let clean = String(data: data, encoding: .utf8) {
            text = clean
            lossy = false
        } else {
            text = String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            lossy = true
        }
        let type: MarkdownDocument.FileType =
            fileURL.pathExtension.lowercased() == "txt" ? .plainText : .markdown
        return .success(SchemePayload(
            text: text, name: fileURL.lastPathComponent, fileType: type,
            fileURL: fileURL, usedLossyEncoding: lossy, deleteOnClose: deleteOnClose
        ))
    }

    // Accepts standard and URL-safe base64, with or without padding.
    private static func decodeBase64(_ raw: String) -> Data? {
        var s = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: " ", with: "+")  // '+' arriving as space in a query
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
