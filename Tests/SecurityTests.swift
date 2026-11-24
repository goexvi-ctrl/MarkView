import Testing
import Foundation
@testable import MarkViewCore

// Regression tests for the 2026-11-09 ropend security review: sanitizer
// bypasses (unterminated tags, on* after "/" or a quote, encoded URL
// schemes) and the mvimg:// file confinement.

@Suite("HTMLSanitizer security")
struct SanitizerSecurityTests {

    /// True if any tag in `html` still carries an on*= attribute.
    private func hasEventHandler(_ html: String) -> Bool {
        html.range(of: "<[a-zA-Z][^>]*[\\s/\"']on[a-z]+\\s*=",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// True if a "<" begins a tag that is never closed with ">".
    private func hasUnterminatedTag(_ html: String) -> Bool {
        html.range(of: "<[a-zA-Z/!?][^>]*$", options: .regularExpression) != nil
    }

    // cmark with CMARK_OPT_UNSAFE passes raw HTML blocks through verbatim, so
    // these are what the sanitizer receives for the handoff's payloads.
    static let unterminated = [
        "<h1>T</h1>\n<div>\n<img src=\"x\"/onerror=\"document.title='EXEC'\"",
        "<h1>T</h1>\n<div>\n<img src=\"x\"onerror=\"document.title='EXEC'\"",
        "<h1>T</h1>\n<div>\n<svg/onload=\"document.title='EXEC'\"",
        "<h1>T</h1>\n<div>\n<details open/ontoggle=\"document.title='EXEC'\"",
        "<div>\n<img src=x onerror=\"document.title='EXEC'\" ",
        "<div>\n<script src=\"x\"",
        "<div>\n<!-- unterminated comment <img src=x onerror=alert(1)>",
    ]

    @Test("Unterminated tags are made text", arguments: unterminated)
    func unterminatedTag(input: String) {
        let out = HTMLSanitizer.sanitize(input)
        #expect(!hasEventHandler(out), "\(out)")
        #expect(!hasUnterminatedTag(out), "\(out)")
    }

    static let separators = [
        "<img src=\"x\"/onerror=\"alert(1)\">",
        "<img src=\"x\"onerror=\"alert(1)\">",
        "<img src='x'onerror='alert(1)'>",
        "<img src=x/onerror=alert(1)>",
        "<details open/ontoggle=\"alert(1)\">x</details>",
        "<img\nsrc=\"x\"\nonerror=\"alert(1)\">",
        "<IMG SRC=\"x\" ONERROR=\"alert(1)\">",
    ]

    @Test("on* after any separator is removed", arguments: separators)
    func separatorVariants(input: String) {
        #expect(!hasEventHandler(HTMLSanitizer.sanitize(input)))
    }

    @Test("Complete allowed tags survive")
    func allowedSurvive() {
        let out = HTMLSanitizer.sanitize("<p>a <img src=\"pic.png\" alt=\"p\"> <kbd>K</kbd></p>")
        #expect(out.contains("<img src=\"pic.png\" alt=\"p\">"))
        #expect(out.contains("<kbd>K</kbd>"))
    }

    @Test("Complete comments are removed, text after them kept")
    func comments() {
        let out = HTMLSanitizer.sanitize("<p>a</p><!-- x <b>y</b> --><p>b</p>")
        #expect(out == "<p>a</p><p>b</p>")
    }

    @Test("Escaped text is left alone")
    func escapedText() {
        let s = "<p>a &lt; b and x/onion=1 \"onerror=2</p>"
        #expect(HTMLSanitizer.sanitize(s) == s)
    }

    static let badURLs = [
        "javascript:alert(1)",
        "JavaScript:alert(1)",
        "javascript&colon;alert(1)",
        "java&#115;cript:alert(1)",
        "java&#x73;cript&#58;alert(1)",
        "java\tscript:alert(1)",
        " \u{1}javascript:alert(1)",
        "data:text/html,x",
        "vbscript:x",
        "&#0;javascript:x",
    ]

    @Test("Dangerous URLs refused", arguments: badURLs)
    func badURL(url: String) {
        #expect(!HTMLSanitizer.isAllowedURL(url))
    }

    static let goodURLs = [
        "https://example.com/a?b=1&amp;c=2",
        "http://example.com",
        "mailto:a@b.c",
        "#section",
        "/abs/path.png",
        "./rel.png",
        "images/a b.png",
        "a&amp;b.png",
    ]

    @Test("Ordinary URLs allowed", arguments: goodURLs)
    func goodURL(url: String) {
        #expect(HTMLSanitizer.isAllowedURL(url))
    }

    @Test("Encoded javascript: link is dropped from output")
    func encodedLinkDropped() {
        let out = HTMLSanitizer.sanitize("<a href=\"javascript&colon;alert(1)\">x</a>")
        #expect(out == "<a>x</a>")
    }
}

@Suite("LocalImagePolicy")
struct LocalImagePolicyTests {

    /// Builds:  root/doc/{a.png, sub/b.jpg, notes.txt, link-out.png -> ../outside.png,
    ///          link-in.png -> sub/b.jpg, fake.png -> notes.txt, dir.png/}
    ///          root/outside.png
    private func makeTree() throws -> (root: URL, doc: URL) {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: LocalImagePolicy.realPath(fm.temporaryDirectory))
            .appendingPathComponent("mv-policy-\(UUID().uuidString)")
        let doc = root.appendingPathComponent("doc")
        try fm.createDirectory(at: doc.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: doc.appendingPathComponent("dir.png"), withIntermediateDirectories: true)
        for p in ["doc/a.png", "doc/sub/b.jpg", "doc/notes.txt", "outside.png"] {
            try Data("x".utf8).write(to: root.appendingPathComponent(p))
        }
        try fm.createSymbolicLink(atPath: doc.appendingPathComponent("link-out.png").path,
                                  withDestinationPath: "../outside.png")
        try fm.createSymbolicLink(atPath: doc.appendingPathComponent("link-in.png").path,
                                  withDestinationPath: "sub/b.jpg")
        try fm.createSymbolicLink(atPath: doc.appendingPathComponent("fake.png").path,
                                  withDestinationPath: "notes.txt")
        return (root, doc)
    }

    @Test("Confined: only images inside the document directory")
    func confined() throws {
        let (root, doc) = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        func ok(_ p: String) -> Bool {
            LocalImagePolicy.resolve(path: p, documentDirectory: doc, confine: true) != nil
        }
        #expect(ok(doc.path + "/a.png"))
        #expect(ok(doc.path + "/sub/b.jpg"))
        #expect(ok(doc.path + "/link-in.png"))
        #expect(ok(doc.path + "/sub/../a.png"))
        #expect(!ok(doc.path + "/../outside.png"))
        #expect(!ok(root.path + "/outside.png"))
        #expect(!ok(doc.path + "/link-out.png"))
        #expect(!ok(doc.path + "/notes.txt"))
        #expect(!ok(doc.path + "/fake.png"))
        #expect(!ok(doc.path + "/dir.png"))
        #expect(!ok(doc.path + "/missing.png"))
        #expect(!ok("/etc/passwd"))
        #expect(!ok("relative.png"))
        #expect(LocalImagePolicy.resolve(path: doc.path + "/a.png", documentDirectory: nil, confine: true) == nil)
    }

    @Test("Unconfined: any image file, still never non-images")
    func unconfined() throws {
        let (root, doc) = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        func ok(_ p: String) -> Bool {
            LocalImagePolicy.resolve(path: p, documentDirectory: doc, confine: false) != nil
        }
        #expect(ok(root.path + "/outside.png"))
        #expect(ok(doc.path + "/link-out.png"))
        #expect(!ok("/etc/passwd"))
        #expect(!ok(doc.path + "/fake.png"))
    }

    @Test("ropend spool documents are confined even when allowed outside")
    func spoolAlwaysConfined() throws {
        let (root, doc) = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LocalImagePolicy.mustConfine(documentDirectory: doc, allowOutside: false, spoolDirectory: root))
        #expect(LocalImagePolicy.mustConfine(documentDirectory: doc, allowOutside: true, spoolDirectory: root))
        let elsewhere = root.appendingPathComponent("spool-elsewhere")
        #expect(!LocalImagePolicy.mustConfine(documentDirectory: doc, allowOutside: true, spoolDirectory: elsewhere))
    }

    @Test("MIME types")
    func mime() {
        #expect(LocalImagePolicy.mimeType(forPath: "/a/B.PNG") == "image/png")
        #expect(LocalImagePolicy.mimeType(forPath: "/a/b.svg") == "image/svg+xml")
        #expect(LocalImagePolicy.mimeType(forPath: "/a/b.txt") == "application/octet-stream")
    }
}
