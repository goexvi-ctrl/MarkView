import Testing
import Foundation
@testable import MarkViewCore

// MarkdownRenderer tests use the cmark-gfm pipeline; they live in the Xcode
// host-app test bundle (MarkViewTests.xctest) rather than the SPM target
// because MarkdownRenderer depends on CmarkGFM which is an Xcode-only package.
// This file covers the SPM-accessible logic only.

@Suite("MarkdownRenderer (SPM-accessible helpers)")
struct RendererTests {

    @Test("HeadingSlugger smoke")
    func slugSmoke() {
        var s = HeadingSlugger()
        #expect(s.slug(for: "Hello World") == "hello-world")
    }
}
