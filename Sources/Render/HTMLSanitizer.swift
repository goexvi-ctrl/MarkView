import Foundation

// GitHub-style HTML sanitizer (D-11).
// Strips unsafe tags/attributes while keeping safe presentational elements
// including <ins>/<u> for underline. Mirrors GitHub's current allowed set.
enum HTMLSanitizer {

    // MARK: - Allowed elements

    private static let allowedTags: Set<String> = [
        "p", "br", "hr", "div", "span", "article", "section",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "dl", "dt", "dd",
        "em", "i", "strong", "b", "del", "s", "strike",
        "ins", "u",
        "kbd", "sub", "sup", "mark",
        "code", "pre", "tt",
        "a", "img",
        "table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption",
        "blockquote", "details", "summary",
        "abbr",
    ]

    private static let allowedAttributes: [String: Set<String>] = [
        "a":       ["href", "title", "rel"],
        "img":     ["src", "alt", "title", "width", "height"],
        "th":      ["align"],
        "td":      ["align"],
        "ol":      ["start", "reversed"],
        "li":      ["value"],
        "abbr":    ["title"],
        "details": ["open"],
        // class allowed on block/inline containers (e.g. math-display, mermaid)
        "div":     ["class", "id"],
        "span":    ["class", "id"],
        // class needed for the comparison view's diff-removed/diff-added markers
        "del":     ["class"],
        "ins":     ["class"],
    ]

    // MARK: - Sanitize

    static func sanitize(_ html: String) -> String {
        var text = html

        // Strip dangerous block tags and their content
        for tag in ["script", "style", "iframe", "object", "embed",
                    "frame", "frameset", "applet", "link", "meta", "base"] {
            text = removeTagWithContent(text, tag: tag)
        }

        text = removeComments(text)

        // Process remaining tags
        text = filterTags(text)

        // Strip on* event attributes (belt-and-suspenders)
        text = stripOnEvents(text)

        return text
    }

    // MARK: - Private helpers

    private static func removeTagWithContent(_ html: String, tag: String) -> String {
        let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
        guard let re = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return html }
        return re.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: ""
        )
    }

    private static func filterTags(_ html: String) -> String {
        let tagPattern = "<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)>"
        guard let re = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) else {
            return html
        }

        var output = ""
        var lastEnd = html.startIndex
        let range = NSRange(html.startIndex..., in: html)

        for match in re.matches(in: html, range: range) {
            guard
                let fullRange  = Range(match.range,       in: html),
                let closeRange = Range(match.range(at: 1), in: html),
                let nameRange  = Range(match.range(at: 2), in: html),
                let attrsRange = Range(match.range(at: 3), in: html),
                let selfRange  = Range(match.range(at: 4), in: html)
            else { continue }

            output += escapeStrayTagOpeners(html[lastEnd..<fullRange.lowerBound])
            lastEnd = fullRange.upperBound

            let isClose = !html[closeRange].isEmpty
            let tagName = html[nameRange].lowercased()
            let attrs   = String(html[attrsRange])
            let isSelf  = !html[selfRange].isEmpty

            // Task list checkboxes: pass through with only type/disabled/checked
            if tagName == "input" {
                let lcAttrs = attrs.lowercased()
                if lcAttrs.contains("type=\"checkbox\"") || lcAttrs.contains("type='checkbox'") {
                    let disabled = lcAttrs.contains("disabled") ? " disabled" : ""
                    let checked  = lcAttrs.contains("checked")  ? " checked"  : ""
                    output += "<input type=\"checkbox\"\(disabled)\(checked)>"
                }
                continue
            }

            guard allowedTags.contains(tagName) else { continue }

            if isClose {
                output += "</\(tagName)>"
            } else {
                let clean = sanitizeAttributes(tagName: tagName, rawAttrs: attrs)
                output += isSelf ? "<\(tagName)\(clean) />" : "<\(tagName)\(clean)>"
            }
        }

        output += escapeStrayTagOpeners(html[lastEnd...])
        return output
    }

    /// Text between the tags filterTags recognised. cmark escapes "<" in
    /// ordinary text as "&lt;", so a literal "<" here is raw HTML the tag
    /// pattern could not match: most dangerously a tag with no closing ">"
    /// at the end of the input, e.g.
    ///     <div>
    ///     <svg/onload="..."
    /// which the browser would still parse as a tag, attributes and all.
    /// Escaping every such "<" turns it into visible text.
    private static func escapeStrayTagOpeners(_ text: Substring) -> String {
        guard text.contains("<") else { return String(text) }
        return text.replacingOccurrences(of: "<", with: "&lt;")
    }

    /// Removes complete HTML comments before tag filtering; a comment may
    /// contain tag-like text that would otherwise split it into pieces. An
    /// unterminated "<!--" is left for escapeStrayTagOpeners to make text.
    private static func removeComments(_ html: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: "<!--.*?-->", options: [.dotMatchesLineSeparators]
        ) else { return html }
        return re.stringByReplacingMatches(
            in: html, range: NSRange(html.startIndex..., in: html), withTemplate: ""
        )
    }

    private static func sanitizeAttributes(tagName: String, rawAttrs: String) -> String {
        let allowed = allowedAttributes[tagName] ?? []
        guard !allowed.isEmpty else { return "" }

        let attrPattern = "([a-zA-Z][a-zA-Z0-9_-]*)\\s*(?:=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=><`]+)))?"
        guard let re = try? NSRegularExpression(pattern: attrPattern, options: []) else { return "" }

        var out = ""
        for m in re.matches(in: rawAttrs, range: NSRange(rawAttrs.startIndex..., in: rawAttrs)) {
            guard let keyRange = Range(m.range(at: 1), in: rawAttrs) else { continue }
            let key = rawAttrs[keyRange].lowercased()
            if key.hasPrefix("on") { continue }
            guard allowed.contains(key) else { continue }

            let val: String?
            if let r = Range(m.range(at: 2), in: rawAttrs), !rawAttrs[r].isEmpty { val = String(rawAttrs[r]) }
            else if let r = Range(m.range(at: 3), in: rawAttrs), !rawAttrs[r].isEmpty { val = String(rawAttrs[r]) }
            else if let r = Range(m.range(at: 4), in: rawAttrs), !rawAttrs[r].isEmpty { val = String(rawAttrs[r]) }
            else { val = nil }

            if let v = val {
                if (key == "href" || key == "src") && !isAllowedURL(v) { continue }
                let escaped = v.replacingOccurrences(of: "\"", with: "&quot;")
                out += " \(key)=\"\(escaped)\""
            } else {
                out += " \(key)"
            }
        }
        return out
    }

    /// Removes on*= attributes from every tag. filterTags already rebuilds
    /// each tag from allowed attributes, so this is a second line of defence.
    /// The handler may follow whitespace, "/" or a closing quote
    /// (<img src="x"/onerror=...>, <img src="x"onerror=...>); browsers accept
    /// all three as attribute separators. Text outside tags is not touched.
    private static func stripOnEvents(_ html: String) -> String {
        guard let tagRE = try? NSRegularExpression(pattern: "<[a-zA-Z][^>]*>", options: []),
              let onRE = try? NSRegularExpression(
                pattern: "(?<=[\\s/\"'])on[a-z]+\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]*)",
                options: .caseInsensitive)
        else { return html }
        let ns = html as NSString
        var out = ""
        var last = 0
        for m in tagRE.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let tag = ns.substring(with: m.range)
            out += onRE.stringByReplacingMatches(
                in: tag, range: NSRange(location: 0, length: (tag as NSString).length), withTemplate: "")
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// The value is checked as the browser will see it: the attribute value
    /// is emitted with its character references intact, and the browser
    /// decodes them, so "javascript&colon;..." or "java&#115;cript:..." would
    /// otherwise pass the scheme check. Named references other than the five
    /// cmark itself emits are refused outright; numeric ones are decoded.
    /// Tab/CR/LF are dropped and leading control characters and spaces
    /// trimmed, as the URL parser does.
    static func isAllowedURL(_ url: String) -> Bool {
        guard let decoded = decodeForURLCheck(url) else { return false }
        let lower = decoded.lowercased()
        if lower.hasPrefix("#") || lower.hasPrefix("/") || lower.hasPrefix("./") { return true }
        for scheme in ["http:", "https:", "mailto:", "tel:"] {
            if lower.hasPrefix(scheme) { return true }
        }
        return !lower.contains(":")
    }

    private static let safeNamedRefs: [String: String] = [
        "amp": "&", "quot": "\"", "lt": "<", "gt": ">", "apos": "'",
    ]

    private static func decodeForURLCheck(_ raw: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "&(?:#[xX]([0-9a-fA-F]+)|#([0-9]+)|([A-Za-z][A-Za-z0-9]*));?", options: []
        ) else { return nil }
        let ns = raw as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            last = m.range.location + m.range.length
            var scalar: UInt32?
            if m.range(at: 1).location != NSNotFound {
                scalar = UInt32(ns.substring(with: m.range(at: 1)), radix: 16)
            } else if m.range(at: 2).location != NSNotFound {
                scalar = UInt32(ns.substring(with: m.range(at: 2)), radix: 10)
            } else {
                let name = ns.substring(with: m.range(at: 3))
                guard let rep = safeNamedRefs[name] else { return nil }
                out += rep
                continue
            }
            guard let v = scalar, let u = Unicode.Scalar(v) else { return nil }
            out.unicodeScalars.append(u)
        }
        out += ns.substring(from: last)
        out.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }
        while let f = out.unicodeScalars.first, f.value <= 0x20 {
            out.unicodeScalars.removeFirst()
        }
        return out
    }
}
