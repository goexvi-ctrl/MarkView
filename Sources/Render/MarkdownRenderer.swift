import Foundation
import CmarkGFM
import AppKit

// Converts a MarkdownDocument to an HTML body string using cmark-gfm.
// Plain text files bypass the Markdown pipeline entirely (D-5.7).
enum MarkdownRenderer {

    static func render(document: MarkdownDocument, allowUnsafeHTML: Bool = false) -> String {
        switch document.fileType {
        case .plainText:
            return renderPlainText(document.text)
        case .markdown:
            return renderMarkdown(document.text, allowUnsafeHTML: allowUnsafeHTML)
        }
    }

    // MARK: - Markdown (cmark-gfm, D-5.1)

    static func renderMarkdown(_ text: String, allowUnsafeHTML: Bool = false) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        // 1. Protect $$...$$ from cmark's Markdown processing.
        //    (Mermaid fenced blocks pass through as normal code blocks for
        //    client-side rendering with the real mermaid.js library.)
        let protected = protectMathBackslashes(text)

        // Always enable CMARK_OPT_UNSAFE so raw HTML (including the math <div>
        // blocks inserted above) is passed through rather than replaced with a
        // comment.  Safety is provided by HTMLSanitizer when allowUnsafeHTML = false.
        let options: Int32 = CMARK_OPT_FOOTNOTES | CMARK_OPT_UNSAFE

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        let extNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
        for name in extNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        let bytes = Array(protected.utf8)
        cmark_parser_feed(parser, bytes, bytes.count)
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }

        var extList: UnsafeMutablePointer<cmark_llist>? = nil
        let mem = cmark_get_default_mem_allocator()
        for name in extNames {
            if let ext = cmark_find_syntax_extension(name) {
                extList = cmark_llist_append(mem, extList, UnsafeMutableRawPointer(ext))
            }
        }
        defer { if extList != nil { cmark_llist_free(mem, extList) } }

        guard let raw = cmark_render_html(doc, options, extList) else { return "" }
        var html = String(cString: raw)
        free(raw)

        // 3. Sanitise.
        if !allowUnsafeHTML { html = HTMLSanitizer.sanitize(html) }

        // Robustness: if cmark produced nothing (e.g. unexpected parse issue with
        // certain fenced blocks or edge cases), fall back to showing the raw text.
        // This prevents completely blank windows.
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            html = "<pre class=\"plain-text\">\(htmlEscape(text))</pre>"
        }

        return html
    }

    // MARK: - Plain text (D-5.7)

    static func renderPlainText(_ text: String) -> String {
        "<pre class=\"plain-text\">\(htmlEscape(text))</pre>"
    }

    // MARK: - Math pre-processing

    // Protects math content from cmark-gfm's Markdown processing.
    //
    // Two problems cmark-gfm causes inside math blocks:
    //   1. `\\` (LaTeX row-break) is treated as a backslash escape → emits `\`
    //   2. A line containing only `=` or `-` is a Setext heading underline,
    //      consuming the preceding lines as heading content (the matrix bug).
    //
    // Solution for $$...$$:
    //   Wrap in a CommonMark type-6 HTML block (<div>). cmark-gfm passes HTML
    //   blocks through verbatim — no Markdown processing, no `\\` mangling, no
    //   Setext heading detection. HTML-encode & < > so the HTML is well-formed;
    //   the browser decodes them back before KaTeX reads the text node.
    //
    // Solution for $...$:
    //   Double backslashes (cmark halves them back). Inline math rarely uses
    //   `\\` but this handles it correctly when it appears.
    //
    // Fenced code blocks and inline code spans are skipped entirely.
    private static func protectMathBackslashes(_ source: String) -> String {
        var out = ""
        var i = source.startIndex

        while i < source.endIndex {
            let ch = source[i]

            // --- Fenced code block (``` or ~~~, at start of line) ---
            if ch == "`" || ch == "~" {
                let atLineStart = i == source.startIndex || source[source.index(before: i)] == "\n"
                if atLineStart {
                    let fenceCount = source[i...].prefix(while: { $0 == ch }).count
                    if fenceCount >= 3 {
                        let fence = String(repeating: ch, count: fenceCount)
                        let afterFence = source.index(i, offsetBy: fenceCount)
                        if let eol = source[afterFence...].firstIndex(of: "\n") {
                            out += source[i...eol]
                            i = source.index(after: eol)
                        } else {
                            out += source[i...]; return out
                        }
                        while i < source.endIndex {
                            if let lineEnd = source[i...].firstIndex(of: "\n") {
                                let lineText = source[i..<lineEnd]
                                out += lineText + "\n"
                                i = source.index(after: lineEnd)
                                if lineText.trimmingCharacters(in: .whitespaces).hasPrefix(fence) { break }
                            } else {
                                out += source[i...]; return out
                            }
                        }
                        continue
                    }
                }
            }

            // --- Inline code span (backticks) ---
            if ch == "`" {
                var j = i
                while j < source.endIndex && source[j] == "`" { j = source.index(after: j) }
                let ticks = String(source[i..<j])
                if let closeRange = source.range(of: ticks, range: j..<source.endIndex) {
                    out += source[i..<closeRange.upperBound]
                    i = closeRange.upperBound
                    continue
                }
            }

            // --- Display math $$...$$ ---
            // Wrap in <div class="math-display"> HTML block so cmark-gfm skips
            // all Markdown processing of the content.
            if ch == "$", source[i...].hasPrefix("$$") {
                let afterOpen = source.index(i, offsetBy: 2)
                if let closeRange = source.range(of: "$$", range: afterOpen..<source.endIndex) {
                    let math = source[afterOpen..<closeRange.lowerBound]
                    // HTML-encode only & < > — backslashes are preserved as-is
                    let encoded = math
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                    // Two trailing newlines separate the HTML block from what follows
                    out += "\n<div class=\"math-display\">$$\(encoded)$$</div>\n\n"
                    i = closeRange.upperBound
                    continue
                }
            }

            // --- Inline math $...$ (single line; no leading/trailing space) ---
            if ch == "$" {
                let afterDollar = source.index(after: i)
                if afterDollar < source.endIndex,
                   source[afterDollar] != "$",
                   source[afterDollar] != " ",
                   source[afterDollar] != "\n" {
                    var j = afterDollar
                    var found = false
                    while j < source.endIndex, source[j] != "\n" {
                        if source[j] == "$", source[source.index(before: j)] != " " {
                            let math = source[afterDollar..<j]
                            out += "$" + math.replacingOccurrences(of: "\\", with: "\\\\") + "$"
                            i = source.index(after: j)
                            found = true
                            break
                        }
                        j = source.index(after: j)
                    }
                    if found { continue }
                }
            }

            out.append(ch)
            i = source.index(after: i)
        }
        return out
    }

    // MARK: - Helpers

    static func htmlEscape(_ str: String) -> String {
        str
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
