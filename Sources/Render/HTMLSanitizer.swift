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

            output += html[lastEnd..<fullRange.lowerBound]
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

        output += html[lastEnd...]
        return output
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

    private static func stripOnEvents(_ html: String) -> String {
        let pattern = "\\s+on[a-z]+\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]*)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return html
        }
        return re.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: ""
        )
    }

    private static func isAllowedURL(_ url: String) -> Bool {
        let lower = url.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("#") || lower.hasPrefix("/") || lower.hasPrefix("./") { return true }
        for scheme in ["http:", "https:", "mailto:", "tel:"] {
            if lower.hasPrefix(scheme) { return true }
        }
        return !lower.contains(":")
    }
}
