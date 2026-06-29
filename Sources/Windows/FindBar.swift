import AppKit

// Standard macOS-style find bar (Cmd-F). This is a native AppKit view overlaid on
// the top of the document's web view. The actual searching/highlighting happens in
// app.js (markviewFind / markviewFindStep / markviewClearFind); this view only
// drives it and shows the "X of Y" match count.
//
// Behavior modeled on Safari's find bar:
//   - Live search as you type.
//   - Return = next match, Shift-Return = previous (both wrap around).
//   - Esc or the Done button closes the bar and clears highlights.

@MainActor
final class FindBarView: NSView, NSSearchFieldDelegate {

    // Wired up by the owning controller.
    var onSearch: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onDone: (() -> Void)?

    let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let doneButton = NSButton()

    static let barHeight: CGFloat = 36

    var query: String { searchField.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // Frosted background so content scrolling underneath stays legible.
        let bg = NSVisualEffectView()
        bg.material = .titlebar
        bg.blendingMode = .withinWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.placeholderString = "Find"
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        configureNavButton(prevButton, symbol: "chevron.up",
                           tip: "Find Previous (Shift-Return)", action: #selector(prevClicked))
        configureNavButton(nextButton, symbol: "chevron.down",
                           tip: "Find Next (Return)", action: #selector(nextClicked))

        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addView(searchField, in: .leading)
        stack.addView(countLabel, in: .leading)
        stack.addView(prevButton, in: .trailing)
        stack.addView(nextButton, in: .trailing)
        stack.addView(doneButton, in: .trailing)
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.barHeight),

            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),

            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    private func configureNavButton(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.bezelStyle = .rounded
        b.imagePosition = .imageOnly
        b.toolTip = tip
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Move keyboard focus into the search field and select any existing text.
    func focusField() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    /// Update the "X of Y" / "Not found" readout.
    func setCount(current: Int, total: Int) {
        if query.isEmpty {
            countLabel.stringValue = ""
        } else if total == 0 {
            countLabel.stringValue = "Not found"
        } else {
            countLabel.stringValue = "\(current) of \(total)"
        }
    }

    // MARK: - Button actions

    @objc private func prevClicked() { onPrevious?() }
    @objc private func nextClicked() { onNext?() }
    @objc private func doneClicked() { onDone?() }

    // MARK: - NSSearchFieldDelegate / NSControlTextEditingDelegate

    func controlTextDidChange(_ obj: Notification) {
        onSearch?(query)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDone?()
            return true
        default:
            return false
        }
    }
}

// MARK: - Find driving logic on the web view controller

extension MarkdownWebViewController {

    /// Cmd-F. Show the find bar; if it is already open, just refocus/select it.
    func showFindBar() {
        if let bar = findBar {
            bar.focusField()
            return
        }

        let bar = FindBarView()
        bar.onSearch = { [weak self] query in self?.performFindSearch(query) }
        bar.onNext = { [weak self] in self?.findBarStep(forward: true) }
        bar.onPrevious = { [weak self] in self?.findBarStep(forward: false) }
        bar.onDone = { [weak self] in self?.hideFindBar() }

        view.addSubview(bar)

        // The window uses .fullSizeContentView, so the web view extends up behind
        // the title bar. Pin the find bar below the title bar (and its accessories)
        // via the window's contentLayoutGuide so it isn't obscured and its buttons
        // stay clickable. Fall back to the view top if the guide isn't available.
        let topAnchor = (view.window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? view.topAnchor
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
        ])
        findBar = bar
        bar.focusField()
    }

    /// Close the find bar, clear highlights, and hand keyboard focus back to the
    /// web content (so git-history arrow keys etc. work again).
    func hideFindBar() {
        guard let bar = findBar else { return }
        findBar = nil
        bar.removeFromSuperview()
        webView.evaluateJavaScript("markviewClearFind()", completionHandler: nil)
        view.window?.makeFirstResponder(webView)
    }

    /// Cmd-G: next match (opens the bar if it is closed).
    func findBarNext() { findBarAdvance(forward: true) }

    /// Cmd-Shift-G: previous match (opens the bar if it is closed).
    func findBarPrevious() { findBarAdvance(forward: false) }

    private func findBarAdvance(forward: Bool) {
        guard let bar = findBar else {
            showFindBar()
            return
        }
        if bar.query.isEmpty {
            bar.focusField()
        } else {
            findBarStep(forward: forward)
        }
    }

    /// Re-run the active search after the document content was re-rendered (live
    /// reload / theme / settings change) so highlights and the count stay correct.
    func reapplyFindIfActive() {
        guard let bar = findBar, !bar.query.isEmpty else { return }
        performFindSearch(bar.query)
    }

    private func performFindSearch(_ query: String) {
        webView.evaluateJavaScript("markviewFind(\(Self.jsStringLiteral(query)))") { [weak self] result, _ in
            self?.updateFindCount(from: result)
        }
    }

    private func findBarStep(forward: Bool) {
        guard let bar = findBar, !bar.query.isEmpty else { return }
        webView.evaluateJavaScript("markviewFindStep(\(forward ? "true" : "false"))") { [weak self] result, _ in
            self?.updateFindCount(from: result)
        }
    }

    private func updateFindCount(from result: Any?) {
        guard let bar = findBar else { return }
        let dict = result as? [String: Any]
        let total = (dict?["count"] as? NSNumber)?.intValue ?? 0
        let current = (dict?["current"] as? NSNumber)?.intValue ?? 0
        bar.setCount(current: current, total: total)
    }

    /// Encode an arbitrary string as a safe JS string literal (quotes included).
    /// JSON string escaping is a strict subset of valid JS string escaping.
    private static func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              var str = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        str.removeFirst()  // leading '['
        str.removeLast()   // trailing ']'
        return str
    }
}
