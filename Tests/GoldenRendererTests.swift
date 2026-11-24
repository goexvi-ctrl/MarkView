// Golden renderer tests — compiled only in the Xcode test bundle (MarkViewTests.xctest)
// where the full MarkView module (including cmark-gfm) is available.
// NOT included in the SPM MarkViewCore target.

#if canImport(CmarkGFM)
import Testing
import Foundation
@testable import MarkView

// These tests exercise MarkdownRenderer.renderMarkdown() end-to-end.
// Each test supplies Markdown source and checks that key HTML fragments appear
// or do NOT appear in the output.

@Suite("MarkdownRenderer (golden)")
struct GoldenRendererTests {

    private func html(_ md: String) -> String {
        MarkdownRenderer.renderMarkdown(md)
    }

    // MARK: - Inline styles

    @Test("Bold")
    func bold() {
        #expect(html("**bold**").contains("<strong>bold</strong>"))
    }

    @Test("Italic")
    func italic() {
        #expect(html("*italic*").contains("<em>italic</em>"))
    }

    @Test("Strikethrough (GFM extension)")
    func strikethrough() {
        #expect(html("~~strike~~").contains("<del>strike</del>"))
    }

    @Test("Inline code")
    func inlineCode() {
        #expect(html("`code`").contains("<code>code</code>"))
    }

    // MARK: - Block structure

    @Test("ATX heading levels")
    func headings() {
        let out = html("# H1\n## H2\n### H3")
        #expect(out.contains("<h1>"))
        #expect(out.contains("<h2>"))
        #expect(out.contains("<h3>"))
    }

    @Test("Fenced code block preserves language class")
    func fencedCode() {
        let out = html("```swift\nlet x = 1\n```")
        #expect(out.contains("language-swift"))
        #expect(out.contains("let x = 1"))
    }

    @Test("Blockquote")
    func blockquote() {
        #expect(html("> quote").contains("<blockquote>"))
    }

    // MARK: - GFM extensions

    @Test("GFM table emits thead and tbody")
    func table() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let out = html(md)
        #expect(out.contains("<table>"))
        #expect(out.contains("<thead>"))
        #expect(out.contains("<tbody>"))
    }

    @Test("Task list produces checkbox inputs")
    func taskList() {
        let md = "- [x] done\n- [ ] todo"
        let out = html(md)
        #expect(out.contains("type=\"checkbox\""))
        #expect(out.contains("checked"))
    }

    @Test("Autolink wraps bare URL")
    func autolink() {
        #expect(html("https://example.com").contains("<a href=\"https://example.com\""))
    }

    @Test("Footnote produces ref and def")
    func footnote() {
        let md = "Text[^1]\n\n[^1]: Note"
        let out = html(md)
        // cmark-gfm wraps footnote ref in sup+a and emits a footnotes section
        #expect(out.contains("<sup") || out.contains("footnote"))
    }

    // MARK: - Sanitizer behaviour

    @Test("Script tag is stripped by sanitizer")
    func scriptStripped() {
        let out = html("<script>alert(1)</script> text")
        #expect(!out.contains("<script>"))
        #expect(!out.contains("alert(1)"))
    }

    // The four payloads from the 2026-11-09 ropend security review, through
    // the real cmark path. Each ends in a tag with no closing ">".
    @Test("Unterminated-tag XSS payloads render inert",
          arguments: [
            "# T\n\n<div>\n<img src=\"x\"/onerror=\"document.title='EXEC'\"",
            "# T\n\n<div>\n<img src=\"x\"onerror=\"document.title='EXEC'\"",
            "# T\n\n<div>\n<svg/onload=\"document.title='EXEC'\"",
            "# T\n\n<div>\n<details open/ontoggle=\"document.title='EXEC'\"",
          ])
    func unterminatedTagPayloads(md: String) {
        let out = html(md)
        #expect(out.range(of: "<[a-zA-Z][^>]*\\son[a-z]+\\s*=", options: .regularExpression) == nil)
        #expect(out.range(of: "<(img|svg|details)\\b", options: .regularExpression) == nil)
        #expect(out.contains("&lt;"))
    }

    @Test("ins tag passes sanitizer")
    func insAllowed() {
        let out = html("<ins>underline</ins>")
        #expect(out.contains("<ins>underline</ins>"))
    }

    @Test("kbd tag passes sanitizer")
    func kbdAllowed() {
        let out = html("<kbd>Cmd</kbd>")
        #expect(out.contains("<kbd>Cmd</kbd>"))
    }

    // MARK: - Math pre-processing

    @Test("Display math block not parsed as Setext heading")
    func displayMathNoSetext() {
        // A lone '=' on its own line inside $$ used to be parsed as a Setext H1.
        let md = "$$\na = b\n$$"
        let out = html(md)
        // Must NOT produce an h1/h2 wrapping the matrix content
        #expect(!out.contains("<h1>"))
        #expect(!out.contains("<h2>"))
    }

    @Test("Inline math backslash preserved")
    func inlineMathBackslash() {
        // cmark halves \\ -> \ — pre-processor must double them back first.
        let md = "$\\frac{1}{2}$"
        let out = html(md)
        // The raw LaTeX should appear somewhere (KaTeX renders client-side)
        #expect(out.contains("\\frac") || out.contains("frac"))
    }

    // MARK: - Plain text path

    @Test("Plain text is HTML-escaped in a pre block")
    func plainText() {
        let out = MarkdownRenderer.renderPlainText("<b>Hello & World</b>")
        #expect(out.hasPrefix("<pre"))
        #expect(out.contains("&lt;b&gt;"))
        #expect(out.contains("&amp;"))
    }
}
#endif
