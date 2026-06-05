import Testing
import Foundation
@testable import MarkViewCore

// Golden renderer tests are filled in M2.5 once cmark-gfm is wired.
// For now, test the HTML escaping helper via HeadingSlugger as a smoke check.
@Suite("MarkdownRenderer (placeholder)")
struct RendererTests {

    @Test("Heading slug basic smoke")
    func slugSmoke() {
        var s = HeadingSlugger()
        #expect(s.slug(for: "Hello World") == "hello-world")
    }
}
