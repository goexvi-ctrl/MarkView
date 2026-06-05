import Testing
@testable import MarkViewCore

@Suite("HeadingSlugger")
struct HeadingSluggerTests {

    @Test("Basic lowercase and space->hyphen")
    func basic() {
        var slugger = HeadingSlugger()
        #expect(slugger.slug(for: "Hello World") == "hello-world")
    }

    @Test("Strip punctuation")
    func punctuation() {
        var slugger = HeadingSlugger()
        #expect(slugger.slug(for: "Hello, World!") == "hello-world")
    }

    @Test("Keeps hyphens")
    func hyphens() {
        var slugger = HeadingSlugger()
        #expect(slugger.slug(for: "some-heading") == "some-heading")
    }

    @Test("Collision de-duplication")
    func collision() {
        var slugger = HeadingSlugger()
        let first  = slugger.slug(for: "Foo")
        let second = slugger.slug(for: "Foo")
        let third  = slugger.slug(for: "Foo")
        #expect(first  == "foo")
        #expect(second == "foo-1")
        #expect(third  == "foo-2")
    }

    @Test("Numbers kept")
    func numbers() {
        var slugger = HeadingSlugger()
        #expect(slugger.slug(for: "Step 1: Setup") == "step-1-setup")
    }
}
