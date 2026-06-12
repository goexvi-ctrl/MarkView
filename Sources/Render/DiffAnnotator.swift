import Foundation

// Pure-Swift word/line diff annotation for the side-by-side comparison view (H2.3/H4.1).
//
// Given the Markdown source of two document versions, produces rewritten sources
// with <del class="diff-removed"> / <ins class="diff-added"> wrappers around the
// words that differ, so the normal MarkdownRenderer pipeline yields rendered
// pages whose changed parts carry tint + scrollbar-marker classes.
//
// Math and code need special handling because injecting HTML tags inside
// $...$ delimiters breaks KaTeX, and tags inside code spans/fences are
// HTML-escaped by cmark and would show up as literal text:
//   - Math regions are atomized (whole formula = one diff token). A changed
//     formula is re-emitted clean inside a <span class="diff-..."> and gets a
//     \color{red}/\color{green} prefix inside the delimiters so the whole
//     formula renders in the diff ink color.
//   - Inline code spans are atomized; a changed span is wrapped in
//     <span class="diff-..."> with the backticks intact inside.
//   - Fenced code blocks are atomized; a changed block is re-emitted inside a
//     <div class="diff-..."> HTML block separated by blank lines so cmark still
//     parses the fence normally (whole-block tint, no markup inside the code).
//
// No AppKit/cmark dependencies: this file is part of the SPM MarkViewCore
// target so it can be unit-tested headlessly.
enum DiffAnnotator {

    // MARK: - Public entry points

    /// Word-level diff: returns both sources rewritten with diff wrappers,
    /// ready to be passed to MarkdownRenderer.
    static func diffedMarkdownSourcesWordByWord(leftText: String, rightText: String) -> (left: String, right: String) {
        let leftAtom = atomize(leftText)
        let rightAtom = atomize(rightText)

        let leftWords = extractWords(leftAtom.skeleton)
        let rightWords = extractWords(rightAtom.skeleton)
        let lcs = longestCommonSubsequence(leftWords, rightWords)

        let leftWrapped = applyWordWrappers(
            to: leftAtom.skeleton, sideWords: leftWords, lcs: lcs,
            open: "<del class=\"diff-removed\">", close: "</del>")
        let rightWrapped = applyWordWrappers(
            to: rightAtom.skeleton, sideWords: rightWords, lcs: lcs,
            open: "<ins class=\"diff-added\">", close: "</ins>")

        let leftRestored = restoreAtoms(in: leftWrapped, placeholders: leftAtom.placeholders, removedSide: true)
        let rightRestored = restoreAtoms(in: rightWrapped, placeholders: rightAtom.placeholders, removedSide: false)

        return (leftRestored, rightRestored)
    }

    /// Line-level diff annotation (used for the +/- stats line in the comparison header).
    static func annotatedLines(leftLines: [String], rightLines: [String]) -> (left: [(line: String, removed: Bool)], right: [(line: String, added: Bool)]) {
        let lcs = longestCommonSubsequence(leftLines, rightLines)
        var leftAnn: [(String, Bool)] = []
        var rightAnn: [(String, Bool)] = []
        var li = 0
        var ri = 0
        var ci = 0
        while ci < lcs.count {
            while li < leftLines.count && leftLines[li] != lcs[ci] {
                leftAnn.append((leftLines[li], true))
                li += 1
            }
            while ri < rightLines.count && rightLines[ri] != lcs[ci] {
                rightAnn.append((rightLines[ri], true))
                ri += 1
            }
            guard li < leftLines.count && ri < rightLines.count else { break }
            leftAnn.append((leftLines[li], false))
            rightAnn.append((rightLines[ri], false))
            li += 1
            ri += 1
            ci += 1
        }
        while li < leftLines.count {
            leftAnn.append((leftLines[li], true))
            li += 1
        }
        while ri < rightLines.count {
            rightAnn.append((rightLines[ri], true))
            ri += 1
        }
        return (leftAnn, rightAnn)
    }

    // MARK: - LCS + word helpers

    static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        guard m > 0 && n > 0 else { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        var res: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                res.insert(a[i-1], at: 0)
                i -= 1
                j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return res
    }

    static func extractWords(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "\\S+")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            let r = Range(match.range, in: text)!
            return String(text[r])
        }
    }

    /// Wrap every word on this side that is not part of the LCS in open...close.
    static func applyWordWrappers(to original: String, sideWords: [String], lcs: [String], open: String, close: String) -> String {
        var isChanged = Array(repeating: false, count: sideWords.count)
        var wi = 0
        var ci = 0
        while wi < sideWords.count {
            if ci < lcs.count && sideWords[wi] == lcs[ci] {
                wi += 1
                ci += 1
            } else {
                isChanged[wi] = true
                wi += 1
            }
        }

        let regex = try! NSRegularExpression(pattern: "\\S+")
        let range = NSRange(original.startIndex..., in: original)
        let matches = regex.matches(in: original, range: range)

        var result = ""
        var lastEnd = original.startIndex
        var wordIdx = 0

        for match in matches {
            let mRange = Range(match.range, in: original)!
            result += original[lastEnd..<mRange.lowerBound]

            let wordText = String(original[mRange])
            if wordIdx < isChanged.count && isChanged[wordIdx] {
                result += open + wordText + close
            } else {
                result += wordText
            }
            lastEnd = mRange.upperBound
            wordIdx += 1
        }
        result += original[lastEnd...]
        return result
    }

    // MARK: - Atomization (math + code regions become single diff tokens)

    struct Atom {
        enum Kind {
            case math
            case inlineCode
            case blockCode
        }
        let kind: Kind
        /// Original source of the region, including its delimiters/fences.
        let content: String
    }

    struct Atomization {
        /// Text with atomic regions replaced by unique whitespace-free placeholders.
        let skeleton: String
        let placeholders: [String: Atom]
    }

    /// Replace every math region, inline code span, and fenced code block with a
    /// single atomic placeholder token so the word-level LCS treats the whole
    /// region as one "word" and never injects markup inside it.
    ///
    /// The placeholder is derived from a hash of the region's content, NOT from
    /// its ordinal position: the two sides are atomized independently, so a
    /// position-based token would be identical for a changed formula on both
    /// sides and the LCS would treat the change as common (no highlight).
    /// Content-derived tokens match exactly when the regions are identical.
    static func atomize(_ text: String) -> Atomization {
        var skeleton = ""
        var placeholders: [String: Atom] = [:]
        var i = text.startIndex

        func appendAtom(_ content: String, kind: Atom.Kind) {
            let ph = "\u{0001}M\(fnv1aHash(content))\u{0001}"
            placeholders[ph] = Atom(kind: kind, content: content)
            skeleton += ph
        }

        while i < text.endIndex {
            let ch = text[i]

            // --- Fenced code block (``` or ~~~ at line start) ---
            if ch == "`" || ch == "~" {
                let atLineStart = i == text.startIndex || text[text.index(before: i)] == "\n"
                if atLineStart {
                    let fenceCount = text[i...].prefix(while: { $0 == ch }).count
                    if fenceCount >= 3 {
                        let fence = String(repeating: ch, count: fenceCount)
                        let searchStart = text.index(i, offsetBy: fenceCount)
                        if let closing = text[searchStart...].range(of: "\n" + fence) {
                            // Up to and including the closing fence characters; the
                            // newline after the closer stays in the skeleton so the
                            // placeholder remains its own word.
                            let end = closing.upperBound
                            appendAtom(String(text[i..<end]), kind: .blockCode)
                            i = end
                            continue
                        } else {
                            // Unclosed fence: atomize the rest so no markup lands inside.
                            appendAtom(String(text[i...]), kind: .blockCode)
                            i = text.endIndex
                            continue
                        }
                    }
                }
            }

            // --- Inline code span `...` ---
            if ch == "`" {
                var j = i
                while j < text.endIndex && text[j] == "`" { j = text.index(after: j) }
                let ticks = String(text[i..<j])
                if let close = text.range(of: ticks, range: j..<text.endIndex) {
                    appendAtom(String(text[i..<close.upperBound]), kind: .inlineCode)
                    i = close.upperBound
                    continue
                }
            }

            // --- Display math $$...$$ ---
            if ch == "$", text[i...].hasPrefix("$$") {
                let after = text.index(i, offsetBy: 2)
                if let closeRange = text.range(of: "$$", range: after..<text.endIndex) {
                    let end = text.index(closeRange.lowerBound, offsetBy: 2)
                    appendAtom(String(text[i..<end]), kind: .math)
                    i = end
                    continue
                }
            }

            // --- Display \[ ... \] ---
            if text[i...].hasPrefix("\\[") {
                let after = text.index(i, offsetBy: 2)
                if let closeRange = text.range(of: "\\]", range: after..<text.endIndex) {
                    let end = text.index(closeRange.lowerBound, offsetBy: 2)
                    appendAtom(String(text[i..<end]), kind: .math)
                    i = end
                    continue
                }
            }

            // --- Inline \( ... \) ---
            if text[i...].hasPrefix("\\(") {
                let after = text.index(i, offsetBy: 2)
                if let closeRange = text.range(of: "\\)", range: after..<text.endIndex) {
                    let end = text.index(closeRange.lowerBound, offsetBy: 2)
                    appendAtom(String(text[i..<end]), kind: .math)
                    i = end
                    continue
                }
            }

            // --- Inline $...$ (single line, no space adjacent to the delimiters) ---
            if ch == "$" {
                let after = text.index(after: i)
                if after < text.endIndex,
                   text[after] != "$",
                   text[after] != " ",
                   text[after] != "\n" {
                    var j = after
                    var found = false
                    while j < text.endIndex && text[j] != "\n" {
                        if text[j] == "$", text[text.index(before: j)] != " " {
                            appendAtom(String(text[i...j]), kind: .math)
                            i = text.index(after: j)
                            found = true
                            break
                        }
                        j = text.index(after: j)
                    }
                    if found { continue }
                }
            }

            skeleton.append(ch)
            i = text.index(after: i)
        }

        return Atomization(skeleton: skeleton, placeholders: placeholders)
    }

    /// Deterministic 64-bit FNV-1a (String.hashValue is randomized per process).
    private static func fnv1aHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Insert \color{...} right after the opening math delimiter so the whole
    /// formula renders in the diff ink color while the LaTeX stays valid.
    static func insertColorIntoMath(_ fullMath: String, color: String) -> String {
        if fullMath.hasPrefix("$$") && fullMath.hasSuffix("$$") && fullMath.count > 4 {
            let inner = String(fullMath.dropFirst(2).dropLast(2))
            return "$$\\color{" + color + "}" + inner + "$$"
        }
        if fullMath.hasPrefix("$") && fullMath.hasSuffix("$") && fullMath.count > 2 && !fullMath.hasPrefix("$$") {
            let inner = String(fullMath.dropFirst().dropLast())
            return "$\\color{" + color + "}" + inner + "$"
        }
        if fullMath.hasPrefix("\\[") && fullMath.hasSuffix("\\]") && fullMath.count > 4 {
            let inner = String(fullMath.dropFirst(2).dropLast(2))
            return "\\[\\color{" + color + "}" + inner + "\\]"
        }
        if fullMath.hasPrefix("\\(") && fullMath.hasSuffix("\\)") && fullMath.count > 4 {
            let inner = String(fullMath.dropFirst(2).dropLast(2))
            return "\\(\\color{" + color + "}" + inner + "\\)"
        }
        return fullMath
    }

    /// Replace placeholders in the wrapped skeleton with their original source.
    ///
    /// A placeholder that was wrapped (i.e. the region differs between sides)
    /// is re-emitted according to its kind (see the type comment). Plain string
    /// replacement is used throughout: an earlier implementation passed the
    /// original source as an NSRegularExpression replacement template, which
    /// silently stripped LaTeX backslashes ("\\color" became "color").
    private static func restoreAtoms(in wrapped: String, placeholders: [String: Atom], removedSide: Bool) -> String {
        let cls = removedSide ? "diff-removed" : "diff-added"
        let color = removedSide ? "red" : "green"
        let openTag = removedSide ? "<del class=\"diff-removed\">" : "<ins class=\"diff-added\">"
        let closeTag = removedSide ? "</del>" : "</ins>"

        var result = wrapped
        for (ph, atom) in placeholders {
            let wrappedToken = openTag + ph + closeTag
            if result.contains(wrappedToken) {
                let replacement: String
                switch atom.kind {
                case .math:
                    replacement = "<span class=\"\(cls)\">" + insertColorIntoMath(atom.content, color: color) + "</span>"
                case .inlineCode:
                    replacement = "<span class=\"\(cls)\">" + atom.content + "</span>"
                case .blockCode:
                    // Blank lines end the <div> HTML block before the fence starts,
                    // so cmark still renders the fence as a normal code block while
                    // the div supplies the whole-block tint.
                    let block = atom.content.trimmingCharacters(in: .newlines)
                    replacement = "\n<div class=\"\(cls)\">\n\n" + block + "\n\n</div>\n"
                }
                result = result.replacingOccurrences(of: wrappedToken, with: replacement)
            }
            // Unchanged (or punctuation-fused) placeholders: restore the clean original.
            result = result.replacingOccurrences(of: ph, with: atom.content)
        }
        return result
    }
}
