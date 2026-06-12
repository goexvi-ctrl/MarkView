import Testing
import Foundation
@testable import MarkViewCore

// Unit tests for the comparison-view diff annotation engine.
// Runs in the SPM test target (no AppKit/cmark dependency).

@Suite("DiffAnnotator")
struct DiffAnnotatorTests {

    // MARK: - LCS / word basics

    @Test("LCS of identical sequences is the sequence")
    func lcsIdentical() {
        let a = ["one", "two", "three"]
        #expect(DiffAnnotator.longestCommonSubsequence(a, a) == a)
    }

    @Test("LCS of disjoint sequences is empty")
    func lcsDisjoint() {
        #expect(DiffAnnotator.longestCommonSubsequence(["a", "b"], ["c", "d"]).isEmpty)
    }

    @Test("Changed words get del/ins wrappers, common words do not")
    func wordWrappers() {
        let (left, right) = DiffAnnotator.diffedMarkdownSourcesWordByWord(
            leftText: "the quick brown fox",
            rightText: "the slow brown fox"
        )
        #expect(left == "the <del class=\"diff-removed\">quick</del> brown fox")
        #expect(right == "the <ins class=\"diff-added\">slow</ins> brown fox")
    }

    @Test("Identical sources come back unchanged")
    func identicalSources() {
        let text = "# Title\n\nSome *body* text with $E = mc^2$ math.\n"
        let (left, right) = DiffAnnotator.diffedMarkdownSourcesWordByWord(leftText: text, rightText: text)
        #expect(left == text)
        #expect(right == text)
    }

    // MARK: - Line annotation (stats)

    @Test("Line annotation counts removed and added lines")
    func lineAnnotation() {
        let (l, r) = DiffAnnotator.annotatedLines(
            leftLines: ["same", "old line", "same2"],
            rightLines: ["same", "new line", "extra", "same2"]
        )
        #expect(l.filter(\.removed).map(\.line) == ["old line"])
        #expect(r.filter(\.added).map(\.line) == ["new line", "extra"])
    }

    // MARK: - Math handling

    @Test("Changed inline math is wrapped whole with color prefix, backslashes intact")
    func changedMathKeepsBackslashes() {
        // Regression test: an earlier implementation passed the math source through
        // an NSRegularExpression replacement template, which stripped the LaTeX
        // backslashes (e.g. \sqrt became sqrt) for every changed formula.
        let (left, right) = DiffAnnotator.diffedMarkdownSourcesWordByWord(
            leftText: "Roots: $x = \\sqrt{b^2 - 4ac}$ done",
            rightText: "Roots: $x = \\sqrt{b^2 - 4AC}$ done"
        )
        #expect(left.contains("<span class=\"diff-removed\">$\\color{red}x = \\sqrt{b^2 - 4ac}$</span>"))
        #expect(right.contains("<span class=\"diff-added\">$\\color{green}x = \\sqrt{b^2 - 4AC}$</span>"))
        // No markup may be injected inside the math delimiters.
        #expect(!left.contains("$x = <del"))
        #expect(!right.contains("$x = <ins"))
    }

    @Test("Unchanged math is restored clean even when nearby text changes")
    func unchangedMathRestoredClean() {
        let (left, right) = DiffAnnotator.diffedMarkdownSourcesWordByWord(
            leftText: "Before $E = mc^2$ alpha",
            rightText: "Before $E = mc^2$ beta"
        )
        #expect(left.contains("$E = mc^2$"))
        #expect(right.contains("$E = mc^2$"))
        #expect(!left.contains("\\color"))
        #expect(!right.contains("\\color"))
        #expect(left.contains("<del class=\"diff-removed\">alpha</del>"))
        #expect(right.contains("<ins class=\"diff-added\">beta</ins>"))
    }

    @Test("Display math $$...$$ gets color inside the delimiters")
    func displayMathColor() {
        let colored = DiffAnnotator.insertColorIntoMath("$$a \\\\ b$$", color: "red")
        #expect(colored == "$$\\color{red}a \\\\ b$$")
    }

    // MARK: - Code handling

    @Test("Changed fenced code block is tinted via div, no tags inside the fence")
    func changedFencedBlock() {
        let leftSrc = "Intro\n\n```swift\nlet x = 1\n```\n\nOutro"
        let rightSrc = "Intro\n\n```swift\nlet x = 2\n```\n\nOutro"
        let (left, right) = DiffAnnotator.diffedMarkdownSourcesWordByWord(
            leftText: leftSrc, rightText: rightSrc
        )
        // The block is re-emitted whole inside a blank-line-separated div so cmark
        // still parses the fence; no del/ins markup may appear inside the fence.
        #expect(left.contains("<div class=\"diff-removed\">\n\n```swift\nlet x = 1\n```\n\n</div>"))
        #expect(right.contains("<div class=\"diff-added\">\n\n```swift\nlet x = 2\n```\n\n</div>"))
        #expect(!left.contains("```swift\nlet x = <del"))
        #expect(!right.contains("```swift\nlet x = <ins"))
    }

    @Test("Unchanged fenced code block is untouched while prose changes")
    func unchangedFencedBlock() {
        let block = "```python\nprint(\"hi\")\n```"
        let (left, right) = DiffAnnotator.diffedMarkdownSourcesWordByWord(
            leftText: "old text\n\n\(block)\n",
            rightText: "new text\n\n\(block)\n"
        )
        #expect(left.contains(block))
        #expect(right.contains(block))
        #expect(!left.contains("<div class=\"diff-removed\">"))
        #expect(!right.contains("<div class=\"diff-added\">"))
    }

    @Test("Changed inline code span is wrapped outside the backticks")
    func changedInlineCode() {
        let (left, right) = DiffAnnotator.diffedMarkdownSourcesWordByWord(
            leftText: "Use `foo()` here",
            rightText: "Use `bar()` here"
        )
        #expect(left.contains("<span class=\"diff-removed\">`foo()`</span>"))
        #expect(right.contains("<span class=\"diff-added\">`bar()`</span>"))
        #expect(!left.contains("`<del"))
        #expect(!right.contains("`<ins"))
    }

    // MARK: - Atomization details

    @Test("Atomize replaces math and code with single-token placeholders")
    func atomizeTokens() {
        let atom = DiffAnnotator.atomize("a $x+y$ b `code` c\n\n```\nblock\n```\n")
        #expect(atom.placeholders.count == 3)
        let kinds = Set(atom.placeholders.values.map { "\($0.kind)" })
        #expect(kinds == ["math", "inlineCode", "blockCode"])
        // Placeholders contain no whitespace, so each is a single diff word.
        for ph in atom.placeholders.keys {
            #expect(ph.rangeOfCharacter(from: .whitespacesAndNewlines) == nil)
        }
        // Skeleton retains the surrounding prose.
        #expect(atom.skeleton.contains("a "))
        #expect(atom.skeleton.contains(" b "))
        #expect(atom.skeleton.contains(" c"))
    }

    @Test("Unclosed fence is atomized to the end of input")
    func unclosedFence() {
        let atom = DiffAnnotator.atomize("text\n```\nnever closed")
        #expect(atom.placeholders.count == 1)
        #expect(atom.placeholders.values.first?.content == "```\nnever closed")
    }
}
