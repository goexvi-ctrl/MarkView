import Testing
import Foundation
@testable import MarkViewCore

@Suite("LinkClassifier")
struct LinkClassifierTests {

    private let docURL = URL(fileURLWithPath: "/tmp/docs/readme.md")

    @Test("Fragment-only link -> anchor")
    func fragmentOnly() {
        let url = URL(string: "#setup")!
        if case .anchor(let slug) = LinkClassifier.classify(url: url, documentURL: docURL) {
            #expect(slug == "setup")
        } else {
            Issue.record("Expected .anchor")
        }
    }

    @Test("http URL -> openExternal")
    func httpExternal() {
        let url = URL(string: "https://example.com")!
        if case .openExternal = LinkClassifier.classify(url: url, documentURL: docURL) {
            // pass
        } else {
            Issue.record("Expected .openExternal")
        }
    }

    @Test("mailto -> openExternal")
    func mailto() {
        let url = URL(string: "mailto:user@example.com")!
        if case .openExternal = LinkClassifier.classify(url: url, documentURL: docURL) {
            // pass
        } else {
            Issue.record("Expected .openExternal")
        }
    }

    @Test("Missing local file -> notFound")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/file.md")
        if case .notFound = LinkClassifier.classify(url: url, documentURL: docURL) {
            // pass
        } else {
            Issue.record("Expected .notFound")
        }
    }

    @Test("Same-document fragment URL -> anchor (regression: #viewer-integration)")
    func sameDocumentFragment() {
        // href="#viewer-integration" resolved against file:///tmp/docs/readme.md
        // produces file:///tmp/docs/readme.md#viewer-integration
        let fragmentURL = URL(string: "#viewer-integration", relativeTo: docURL)!
        if case .anchor(let slug) = LinkClassifier.classify(url: fragmentURL, documentURL: docURL) {
            #expect(slug == "viewer-integration")
        } else {
            Issue.record("Expected .anchor for same-document fragment URL")
        }
    }

    @Test("Fragment resolved against directory does not open Finder")
    func fragmentAgainstDirectory() {
        let dirURL = docURL.deletingLastPathComponent()
        let fragmentURL = URL(string: "#some-heading", relativeTo: dirURL)!
        // Should return .anchor, not .openWithDefaultApp (the directory)
        if case .openWithDefaultApp = LinkClassifier.classify(url: fragmentURL, documentURL: docURL) {
            Issue.record("Fragment-against-directory must not open Finder")
        }
    }
}
