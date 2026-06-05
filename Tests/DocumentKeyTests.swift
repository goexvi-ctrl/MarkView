import Testing
import Foundation
@testable import MarkViewCore

@Suite("DocumentKey")
struct DocumentKeyTests {

    @Test("Same path, different representations -> equal keys")
    func samePathVariants() {
        let base = URL(fileURLWithPath: "/tmp/test.md")
        let dotDot = URL(fileURLWithPath: "/tmp/subdir/../test.md")
        #expect(DocumentKey(url: base) == DocumentKey(url: dotDot))
    }

    @Test("Case-insensitive on HFS+")
    func caseInsensitive() {
        let lower = URL(fileURLWithPath: "/tmp/readme.md")
        let upper = URL(fileURLWithPath: "/tmp/README.md")
        #expect(DocumentKey(url: lower) == DocumentKey(url: upper))
    }

    @Test("Different files -> different keys")
    func differentFiles() {
        let a = URL(fileURLWithPath: "/tmp/a.md")
        let b = URL(fileURLWithPath: "/tmp/b.md")
        #expect(DocumentKey(url: a) != DocumentKey(url: b))
    }
}
