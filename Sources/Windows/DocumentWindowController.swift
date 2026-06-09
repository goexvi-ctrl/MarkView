import AppKit
import Combine

@MainActor
final class DocumentWindowController: NSWindowController {

    let markdownDocument: MarkdownDocument
    private var fileWatcher: FileWatcher?
    private var webViewController: MarkdownWebViewController?
    private var settingsCancellable: AnyCancellable?

    // Per-document zoom factor loaded from ZoomMemory on init
    private(set) var zoomFactor: Double = 1.0

    // Git history support (H1). Created on first use.
    private lazy var gitClient = GitClient()

    /// When true, file change events are ignored (we are looking at a historical
    /// git snapshot and do not want live reload to fight it).
    private var isViewingHistory = false

    // History navigation state (for < > / arrow key browsing while reviewing versions).
    // historyVersions[0] is always the WorkingTree sentinel (current on-disk).
    // Higher indices are older revisions (as returned by GitClient.history).
    private var historyVersions: [GitVersion] = []
    private var currentHistoryIndex: Int = 0  // 0 == live / working tree
    private var historyLoadTask: Task<Void, Never>?

    /// Whether the document's file is inside a git repository (populated asynchronously on init).
    private(set) var isInGitRepository = false

    /// True for windows that were created specifically to show a historical git revision
    /// (via Shift-< etc. or "open in new window"). These windows have special "Return to current"
    /// behavior: if a live window already exists they close themselves and raise the live one.
    private var isPureHistoricalSnapshot = false

    /// When viewing a historical revision, this holds the full commit message for the info panel.
    private var currentHistoricalFullMessage: String?
    private var currentHistoricalVersion: GitVersion?

    /// Active comparison (H2). When set we have loaded a synthetic side-by-side page.
    private var comparisonVersions: (left: GitVersion, right: GitVersion)?

    /// Indices into historyVersions for the current left and right panes while in comparison mode.
    private var comparisonLeftIndex: Int = 0
    private var comparisonRightIndex: Int = 0

    /// The (optional) info popup panel for this window. We keep at most one per DWC
    /// so that repeated presses of the titlebar ⓘ reuse it instead of spawning multiples.
    private var currentInfoPanel: NSPanel?

    /// Three distinct revision selectors (as suggested to avoid any wiring/mutation issues).
    /// - revisionPopUpButton: used only in normal / single-historical view
    /// - leftRevisionPopUpButton / rightRevisionPopUpButton: used only in comparison mode
    private var revisionPopUpButton: NSPopUpButton?
    private var leftRevisionPopUpButton: NSPopUpButton?
    private var rightRevisionPopUpButton: NSPopUpButton?

    /// Titlebar accessories for the revision selectors. We add/remove whole accessories
    /// when switching modes rather than mutating one container in place.
    private var singleRevisionAccessory: NSTitlebarAccessoryViewController?
    private var leftRevisionAccessory: NSTitlebarAccessoryViewController?
    private var rightRevisionAccessory: NSTitlebarAccessoryViewController?

    /// The info button in the title bar. We repurpose it as an "exit comparison" button
    /// while in side-by-side mode so there is an obvious way to return to single view.
    private var infoButton: NSButton?

    init(document: MarkdownDocument) {
        self.markdownDocument = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = document.displayTitle
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 300)
        super.init(window: window)

        zoomFactor = ZoomMemory.shared.zoom(for: document.key) ?? 1.0

        let webVC = MarkdownWebViewController(document: document, zoomFactor: zoomFactor)
        self.webViewController = webVC

        // Set owning and handler BEFORE setting contentViewController, in case loadView
        // is triggered synchronously during the assignment. This ensures the back-pointer
        // and closure are present on the webVC for Shift-opened historical windows.
        webVC.owningDocumentWindowController = self
        webVC.handleHistoryStep = { [weak self] delta, newWindow in
            self?.handleHistoryStep(delta: delta, newWindow: newWindow)
        }

        print("GITNAV: DVC init: owning and handleHistoryStep wired on webVC (self=\(self))")

        window.contentViewController = webVC

        // Kick off a quick check so we can disable the history menu item when appropriate.
        // Also warm the history list in the background so < / > navigation is instant.
        Task {
            do {
                _ = try await self.gitClient.repoContext(for: self.markdownDocument.fileURL)
                await MainActor.run {
                    self.isInGitRepository = true
                    self.loadHistoryInBackground()
                }
            } catch {
                await MainActor.run { self.isInGitRepository = false }
            }
        }

        // Restore saved window frame; fall back to centered 900x700
        let autosaveKey = "WinFrame-\(document.key.hashValue)"
        if let savedFrameString = UserDefaults.standard.string(forKey: autosaveKey),
           !savedFrameString.isEmpty {
            let savedFrame = NSRectFromString(savedFrameString)
            if savedFrame.width >= 300 && savedFrame.height >= 200 {
                window.setFrameOrigin(savedFrame.origin)
                window.setContentSize(savedFrame.size)
            } else {
                window.setContentSize(NSSize(width: 900, height: 700))
                window.center()
            }
        } else {
            let winSize = NSSize(width: 900, height: 700)
            window.setContentSize(winSize)
            // NSScreen.main follows the cursor; screens.first is always the primary display.
            let screen = NSScreen.screens.first ?? NSScreen.main
            if let sf = screen?.visibleFrame {
                let titleH: CGFloat = window.frame.height - window.contentRect(forFrameRect: window.frame).height
                let totalH = winSize.height + titleH
                let origin = NSPoint(
                    x: sf.origin.x + (sf.width - winSize.width) / 2,
                    y: sf.origin.y + (sf.height - totalH) / 2
                )
                window.setFrameOrigin(origin)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak window] _ in
            // The notification queue is .main, but the closure is treated as Sendable
            // under strict concurrency; hop explicitly to the main actor.
            Task { @MainActor in
                guard let w = window else { return }
                UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: autosaveKey)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak window] _ in
            Task { @MainActor in
                guard let w = window else { return }
                UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: autosaveKey)
            }
        }

        setupFileWatcher()
        setupSettingsObserver()

        // Add a small "i" info button in the title bar (leading side) for commit/live info.
        setupTitlebarInfoButton()

        // Revision selector button (pop-up menu) in title bar for direct access to any commit.
        setupTitlebarRevisionSelector()
    }

    private func setupTitlebarInfoButton() {
        // Use explicit frame for the accessory root view. NSTitlebarAccessoryClipView
        // applies autoresizing masks that conflict with Auto Layout constraints on the
        // root view (leading to the "conflicting constraints" warnings). Frame-based
        // sizing for small titlebar accessories is the reliable pattern.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        // Do not set translatesAutoresizingMaskIntoConstraints = false here; the
        // system manages the accessory view's size via the clip view.

        let button = NSButton(
            image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Version information")!,
            target: self,
            action: #selector(showVersionInfoPanel)
        )
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.toolTip = "Version information"
        button.frame = NSRect(x: 6, y: 2, width: 18, height: 18)

        container.addSubview(button)
        infoButton = button

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .leading

        window?.addTitlebarAccessoryViewController(accessory)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        // deinit is nonisolated even for @MainActor classes. We use assumeIsolated
        // because deallocation of NSWindowController always happens on the main thread.
        MainActor.assumeIsolated {
            dismissInfoPanel()
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: Double) {
        zoomFactor = factor
        ZoomMemory.shared.setZoom(factor, for: markdownDocument.key)
        webViewController?.setZoom(factor)
    }

    // Visual magnification (separate from the reflow font-size zoom).
    // This controls WKWebView's native magnification for "magnifying glass" zoom.
    var visualZoomFactor: CGFloat {
        webViewController?.magnification ?? 1.0
    }

    func setVisualZoom(_ factor: CGFloat) {
        webViewController?.setMagnification(factor)
    }

    // Support for Cmd-R / manual reload while keeping the window (and attached
    // Web Inspector) open.
    func reloadCurrentDocument() {
        webViewController?.reloadCurrentDocument()
    }

    // MARK: - Git historical recall (H1.3)

    /// Asynchronously fetch the content for `version` (a git blob) and switch the
    /// view to a read-only historical snapshot. Shows a persistent banner with a
    /// "Return to current version" action. While active, live file changes are
    /// ignored.
    func viewHistoricalVersion(_ version: GitVersion) {
        guard let webVC = webViewController else { return }

        // Working tree sentinel: switch back to live.
        if version.isWorkingTree {
            exitHistoricalView()
            return
        }

        // Capture scroll so we can try to restore a reasonable position when returning.
        webVC.captureScrollPosition { [weak self] scrollY in
            guard let self else { return }

            Task { [weak self] in
                guard let self else { return }
                do {
                    let text = try await self.gitClient.content(at: version.sha, for: self.markdownDocument.fileURL)

                    self.applyHistoricalContent(version: version, text: text)

                    // Start (or refresh) the ordered history list so that arrow / < > keys work.
                    self.loadHistoryInBackground(preferredCurrentVersion: version)

                } catch {
                    webVC.showBanner(
                        "Could not load historical version: \(error.localizedDescription)",
                        style: .error,
                        autoDismiss: true
                    )
                }
            }
        }
    }

    /// Configure this controller to show a specific historical revision (used both
    /// for in-place recall and for newly opened historical snapshot windows).
    private func applyHistoricalContent(version: GitVersion, text: String) {
        if comparisonVersions != nil {
            // Stale single-view path while we are in comparison mode.
            // Force the titlebar back to dual selectors and bail.
            updateRevisionControls()
            return
        }
        guard let webVC = webViewController else { return }

        dismissInfoPanel()  // the popup was for the previous revision; it is no longer accurate

        print("GITNAV: APPLY HISTORICAL called for \(version.shortSha)")

        webVC.enterHistoricalView(version, text: text)
        isViewingHistory = true
        currentHistoricalVersion = version

        // Update our index if we already have a list.
        if let idx = historyVersions.firstIndex(where: { $0.sha == version.sha }) {
            currentHistoryIndex = idx
        } else if !version.isWorkingTree {
            // Not in list yet (or list not loaded); we'll fix it when list arrives.
            currentHistoryIndex = 1 // best guess: first historical
        }

        window?.title = "\(markdownDocument.displayTitle) @ \(version.shortSha)"

        // Fetch full commit message for the info popup (non-blocking).
        if !version.isWorkingTree {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let full = try await self.gitClient.commitMessage(for: version.sha, file: self.markdownDocument.fileURL)
                    await MainActor.run { self.currentHistoricalFullMessage = full }
                } catch {
                    await MainActor.run { self.currentHistoricalFullMessage = version.subject }
                }
            }
        } else {
            currentHistoricalFullMessage = nil
        }

        let msg = "Viewing \(version.shortSha) — \(version.subject)"
        webVC.showBanner(msg, style: .info, autoDismiss: false, action: ("Return to current", { [weak self] in
            self?.handleReturnToCurrent()
        }))

        self.updateRevisionControls()
    }

    func exitHistoricalView() {
        if comparisonVersions != nil {
            // Stale single-view path while we are in comparison mode.
            updateRevisionControls()
            return
        }
        guard isViewingHistory else { return }
        dismissInfoPanel()  // old popup is no longer accurate for the live view

        isViewingHistory = false
        currentHistoryIndex = 0
        currentHistoricalVersion = nil
        currentHistoricalFullMessage = nil

        // Restore normal title.
        window?.title = markdownDocument.displayTitle

        webViewController?.exitHistoricalView()

        self.updateRevisionControls()

        // Note: webVC.exitHistoricalView() already does a loadDocument() for the live text
        // (with hasInitialContentLoaded forced false so it does a full loadHTMLString).
        // The duplicate loadDocument() was removed to avoid an immediate isUpdate=true
        // replaceDocumentContent right after the full load on return-to-live.
    }

    // Debug-only convenience (H1). Fetches the first real historical commit for
    // the current document (if any) and calls into the normal viewHistorical path.
    // Invoked from the AppDelegate debug menu action.
    func debugViewFirstHistoricalVersion() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let hist = try await self.gitClient.history(for: self.markdownDocument.fileURL, limit: 5)
                // First entry after the WorkingTree sentinel, if present.
                if let firstReal = hist.first(where: { !$0.isWorkingTree }) {
                    self.viewHistoricalVersion(firstReal)
                } else {
                    self.webViewController?.showBanner(
                        "No previous git versions found for this file (or not in a repo).",
                        style: .warning,
                        autoDismiss: true
                    )
                }
            } catch {
                self.webViewController?.showBanner(
                    "Git history lookup failed: \(error.localizedDescription)",
                    style: .error,
                    autoDismiss: true
                )
            }
        }
    }

    // Debug-only (H2). Opens a basic side-by-side comparison between the live
    // document and the first historical commit (newer on the right). Exercises
    // GitClient.diffHunks + MarkdownRenderer for both sides + synthetic HTML load.
    func debugCompareLiveWithFirstHistorical() {
        guard isInGitRepository else {
            webViewController?.showBanner("Not in a git repository.", style: .warning, autoDismiss: true)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let hist = try await self.gitClient.history(for: self.markdownDocument.fileURL, limit: 5)
                guard let firstReal = hist.first(where: { !$0.isWorkingTree }) else {
                    self.webViewController?.showBanner(
                        "No previous git versions to compare.",
                        style: .warning, autoDismiss: true
                    )
                    return
                }
                await self.performComparison(left: firstReal, right: .workingTree)
            } catch {
                self.webViewController?.showBanner(
                    "Compare failed: \(error.localizedDescription)",
                    style: .error, autoDismiss: true
                )
            }
        }
    }

    private func performComparison(left: GitVersion, right: GitVersion) async {
        // Ensure we have the history list so the dual titlebar selectors can be populated.
        if historyVersions.isEmpty {
            do {
                historyVersions = try await gitClient.history(for: markdownDocument.fileURL, limit: 100)
            } catch {
                await MainActor.run { [weak self] in
                    self?.webViewController?.showBanner(
                        "Could not load history for comparison: \(error.localizedDescription)",
                        style: .error, autoDismiss: true
                    )
                }
                return
            }
        }

        // Resolve indices for the two sides (used by the pop-ups).
        if let lidx = historyVersions.firstIndex(where: { $0.sha == left.sha || ($0.isWorkingTree && left.isWorkingTree) }) {
            comparisonLeftIndex = lidx
        } else {
            comparisonLeftIndex = left.isWorkingTree ? 0 : 1
        }
        if let ridx = historyVersions.firstIndex(where: { $0.sha == right.sha || ($0.isWorkingTree && right.isWorkingTree) }) {
            comparisonRightIndex = ridx
        } else {
            comparisonRightIndex = right.isWorkingTree ? 0 : 1
        }

        // Activate comparison mode on the main actor *before* we await any content fetches.
        // This forces the dual L+R titlebar selectors to be installed and
        // `comparisonVersions` to be set immediately. This prevents the race where
        // a stale single revision popup could still be clicked (and take the single-view
        // path) while the comparison HTML was still being prepared.
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.comparisonVersions = (left, right)
            self.window?.title = "\(self.markdownDocument.displayTitle) — compare \(left.shortSha) vs \(right.shortSha)"
            self.updateRevisionControls()
        }

        // Now do the content work (the internal MainActor.run will call update again).
        await loadComparisonContent(left: left, right: right, showBanner: true)
    }

    // MARK: - Line-based diff for H2.3 (implemented ourselves, no git diff)

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
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



    private func annotatedLines(leftLines: [String], rightLines: [String]) -> (left: [(line: String, removed: Bool)], right: [(line: String, added: Bool)]) {
        let lcs = longestCommonSubsequence(leftLines, rightLines)
        var leftAnn: [(String, Bool)] = []
        var rightAnn: [(String, Bool)] = []
        var li = 0
        var ri = 0
        var ci = 0
        while li < leftLines.count || ri < rightLines.count {
            if ci < lcs.count {
                // advance left to the current common
                while li < leftLines.count && leftLines[li] != lcs[ci] {
                    leftAnn.append((leftLines[li], true))
                    li += 1
                }
                // advance right to the current common
                while ri < rightLines.count && rightLines[ri] != lcs[ci] {
                    rightAnn.append((rightLines[ri], true))
                    ri += 1
                }
                // now output the common (if present)
                if li < leftLines.count && ri < rightLines.count {
                    leftAnn.append((leftLines[li], false))
                    rightAnn.append((rightLines[ri], false))
                    li += 1
                    ri += 1
                    ci += 1
                } else {
                    // one side exhausted the match
                    break
                }
            } else {
                // no more commons, emit remainders
                while li < leftLines.count {
                    leftAnn.append((leftLines[li], true))
                    li += 1
                }
                while ri < rightLines.count {
                    rightAnn.append((rightLines[ri], true))
                    ri += 1
                }
                break
            }
        }
        // any final remainders
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



    // Word-by-word diff (H2.3 next step)
    private func extractWords(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "\\S+")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            let r = Range(match.range, in: text)!
            return String(text[r])
        }
    }

    private func applyWordWrappers(to original: String, sideWords: [String], lcs: [String], open: String, close: String) -> String {
        // Mark which words on this side are not part of the LCS (i.e. removed or added)
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

        // Find word matches in original order and wrap the changed ones
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

    private func diffedMarkdownSourcesWordByWord(leftText: String, rightText: String) -> (left: String, right: String) {
        let leftWords = extractWords(leftText)
        let rightWords = extractWords(rightText)
        let lcs = longestCommonSubsequence(leftWords, rightWords)

        let leftMod = applyWordWrappers(to: leftText, sideWords: leftWords, lcs: lcs, open: "<del class=\"diff-removed\">", close: "</del>")
        let rightMod = applyWordWrappers(to: rightText, sideWords: rightWords, lcs: lcs, open: "<ins class=\"diff-added\">", close: "</ins>")

        return (leftMod, rightMod)
    }

    private func loadComparisonContent(left: GitVersion, right: GitVersion, showBanner: Bool) async {
        do {
            let leftText: String = left.isWorkingTree
                ? self.markdownDocument.text
                : try await self.gitClient.content(at: left.sha, for: self.markdownDocument.fileURL)
            let rightText: String = right.isWorkingTree
                ? self.markdownDocument.text
                : try await self.gitClient.content(at: right.sha, for: self.markdownDocument.fileURL)

            // Smart source-line diff: we modify the *source* (preserving block markers like #, -, > etc.
            // outside the wrapper) then render the whole modified document once per side.
            // This keeps full Markdown structure (nested lists, TOCs, headings, etc.) while still
            // highlighting differing source lines in red/green.
            let leftLines = leftText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let rightLines = rightText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let (lAnn, rAnn) = annotatedLines(leftLines: leftLines, rightLines: rightLines)

            let (leftDiffed, rightDiffed) = diffedMarkdownSourcesWordByWord(leftText: leftText, rightText: rightText)

            let leftBody = MarkdownRenderer.render(text: leftDiffed, fileType: self.markdownDocument.fileType, allowUnsafeHTML: true)
            let rightBody = MarkdownRenderer.render(text: rightDiffed, fileType: self.markdownDocument.fileType, allowUnsafeHTML: true)

            // Stats from our line diff (no git diff).
            let removedCount = lAnn.filter { $0.1 }.count
            let addedCount = rAnn.filter { $0.1 }.count
            let stats = (removedCount == 0 && addedCount == 0) ? "identical" : "\(removedCount) removed, \(addedCount) added (source lines)"

            let html = HTMLTemplate.buildComparison(
                leftBody: leftBody,
                rightBody: rightBody,
                leftLabel: "\(left.shortSha) — \(left.subject)",
                rightLabel: right.isWorkingTree ? "Working tree (current on disk)" : "\(right.shortSha) — \(right.subject)",
                stats: stats,
                settings: SettingsStore.shared,
                zoomFactor: self.zoomFactor
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.comparisonVersions = (left, right)
                self.window?.title = "\(self.markdownDocument.displayTitle) — compare \(left.shortSha) vs \(right.shortSha)"
                self.webViewController?.loadComparisonHTML(html, baseURL: self.markdownDocument.fileURL.deletingLastPathComponent())

                if showBanner {
                    self.webViewController?.showBanner(
                        "Comparison view (read-only)",
                        style: .info,
                        autoDismiss: false,
                        action: ("Return to document", { [weak self] in self?.exitComparisonView() })
                    )
                }

                // Ensure dual selectors are installed and show the current choices.
                self.updateRevisionControls()
            }
        } catch {
            await MainActor.run { [weak self] in
                self?.webViewController?.showBanner(
                    "Compare failed: \(error.localizedDescription)",
                    style: .error, autoDismiss: true
                )
            }
        }
    }

    @objc private func exitComparisonView() {
        comparisonVersions = nil
        window?.title = markdownDocument.displayTitle
        webViewController?.exitComparisonView()
        // Restore the single revision selector in the title bar.
        updateRevisionControls()
        // For the debug "live vs first" case we return to live document.
        webViewController?.loadDocument()
    }

    // MARK: - Comparison side selection (two titlebar pop-ups)

    @objc private func leftRevisionPopUpAction(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem,
              let index = item.representedObject as? Int else { return }
        changeComparisonSide(isLeft: true, toIndex: index)
    }

    @objc private func rightRevisionPopUpAction(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem,
              let index = item.representedObject as? Int else { return }
        changeComparisonSide(isLeft: false, toIndex: index)
    }

    private func changeComparisonSide(isLeft: Bool, toIndex index: Int) {
        guard comparisonVersions != nil,
              index >= 0 && index < historyVersions.count else { return }

        let newVersion = historyVersions[index]
        let otherIdx = isLeft ? comparisonRightIndex : comparisonLeftIndex
        let otherVersion = historyVersions[otherIdx]

        let newLeft = isLeft ? newVersion : otherVersion
        let newRight = isLeft ? otherVersion : newVersion

        if isLeft {
            comparisonLeftIndex = index
        } else {
            comparisonRightIndex = index
        }

        // Refresh the side-by-side content (and the pop-up selections via updateRevisionControls).
        Task { [weak self] in
            await self?.loadComparisonContent(left: newLeft, right: newRight, showBanner: false)
        }
    }

    // MARK: - History list management and keyboard-driven stepping (< > arrows)

    /// Asynchronously load (or refresh) the ordered history for this document's file.
    /// When `preferredCurrentVersion` is supplied we try to position `currentHistoryIndex`
    /// on it after the list arrives.
    private func loadHistoryInBackground(preferredCurrentVersion: GitVersion? = nil) {
        historyLoadTask?.cancel()
        historyLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await self.gitClient.history(for: self.markdownDocument.fileURL, limit: 100)
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.historyVersions = list
                    self.currentHistoryIndex = 0

                    if let preferred = preferredCurrentVersion,
                       let idx = list.firstIndex(where: { $0.sha == preferred.sha }) {
                        self.currentHistoryIndex = idx
                    } else if self.isViewingHistory,
                              let currentOverride = self.webViewController?.currentHistoricalSnapshot?.version,
                              let idx = list.firstIndex(where: { $0.sha == currentOverride.sha }) {
                        self.currentHistoryIndex = idx
                    }

                    // If we are in comparison mode, try to keep the same versions selected
                    // even if the history list was refreshed (new commits may have been prepended).
                    if self.comparisonVersions != nil {
                        if let leftV = self.comparisonVersions?.left,
                           let idx = list.firstIndex(where: { $0.sha == leftV.sha || ($0.isWorkingTree && leftV.isWorkingTree) }) {
                            self.comparisonLeftIndex = idx
                        }
                        if let rightV = self.comparisonVersions?.right,
                           let idx = list.firstIndex(where: { $0.sha == rightV.sha || ($0.isWorkingTree && rightV.isWorkingTree) }) {
                            self.comparisonRightIndex = idx
                        }
                    }

                    self.updateRevisionControls()
                }
            } catch {
                // Non-fatal for stepping; the user can still use explicit version pickers later.
                // We leave any previously loaded list in place.
            }
        }
    }

    /// Handle a history step request coming from the JS bridge (arrow keys, < > etc.).
    /// `delta` is -1 for older (earlier in time), +1 for newer (later, toward live).
    /// If `newWindow` is true we open the target revision in a fresh window instead of
    /// changing the current one.
    func handleHistoryStep(delta: Int, newWindow: Bool) {
        guard delta != 0 else { return }

        print("GITNAV: handleHistoryStep delta=\(delta) newW=\(newWindow) isViewing=\(isViewingHistory) cur=\(currentHistoryIndex) listCnt=\(historyVersions.count)")

        Task { [weak self] in
            await self?.performHistoryStep(delta: delta, newWindow: newWindow)
        }
    }

    @MainActor
    private func performHistoryStep(delta: Int, newWindow: Bool) async {
        if comparisonVersions != nil {
            // In comparison mode the titlebar has two selectors; ignore arrow/< > steps.
            updateRevisionControls()
            return
        }

        // If we are on the live view, force index 0 so that plain "<" (older) from live
        // always means "go to the most recent checked-in revision".
        if !isViewingHistory {
            currentHistoryIndex = 0
        }

        // Ensure we have the ordered list (newest first after the working-tree sentinel).
        if historyVersions.isEmpty {
            do {
                historyVersions = try await gitClient.history(for: markdownDocument.fileURL, limit: 100)
                updateRevisionControls()
            } catch {
                webViewController?.showBanner(
                    "Could not load history for stepping: \(error.localizedDescription)",
                    style: .warning,
                    autoDismiss: true
                )
                return
            }
        }

        guard !historyVersions.isEmpty else { return }

        print("GITNAV: perform entered: viewing=\(isViewingHistory) curIdx=\(currentHistoryIndex) listCnt=\(historyVersions.count) delta=\(delta) newW=\(newWindow)")

        // Special fast path for the very common case the user cares about:
        // From live (index 0), plain older step (<) → immediately go to the first real
        // historical revision (index 1) in the current window. This makes repeated "<"
        // from live after returning via ">" work reliably.
        if currentHistoryIndex == 0 && delta < 0 && !newWindow && historyVersions.count > 1 {
            print("GITNAV: SPECIAL FAST PATH TRIGGERED for delta<0 from live, targeting [1]")
            let firstHist = historyVersions[1]
            if !firstHist.isWorkingTree {
                do {
                    let text = try await gitClient.content(at: firstHist.sha, for: markdownDocument.fileURL)
                    applyHistoricalContent(version: firstHist, text: text)
                    currentHistoryIndex = 1
                    return
                } catch {
                    webViewController?.showBanner(
                        "Could not load revision: \(error.localizedDescription)",
                        style: .error,
                        autoDismiss: true
                    )
                    return
                }
            }
        }

        let newIndex = max(0, min(historyVersions.count - 1,
                                  currentHistoryIndex + (delta > 0 ? -1 : +1)))

        if newIndex == currentHistoryIndex {
            print("GITNAV: GENERAL early return newIndex==current (\(newIndex))")
            // Already at the live end or the oldest revision we know about.
            return
        }

        let targetVersion = historyVersions[newIndex]

        if newWindow {
            DocumentWindowRegistry.shared.openHistoricalVersion(for: markdownDocument.fileURL, version: targetVersion)
            return
        }

        // In-place step in the current window.
        if targetVersion.isWorkingTree {
            print("GITNAV: HIT WT sentinel in step, calling exit")
            exitHistoricalView()
        } else {
            do {
                let text = try await gitClient.content(at: targetVersion.sha, for: markdownDocument.fileURL)
                applyHistoricalContent(version: targetVersion, text: text)
                currentHistoryIndex = newIndex
            } catch {
                webViewController?.showBanner(
                    "Could not load revision: \(error.localizedDescription)",
                    style: .error,
                    autoDismiss: true
                )
            }
        }
    }

    /// Called by the registry when creating a brand-new window that should start life
    /// already showing a historical revision (Shift-< / Shift-> path).
    func configureAsInitialHistorical(version: GitVersion, text: String) {
        isPureHistoricalSnapshot = true
        applyHistoricalContent(version: version, text: text)
        // Load the surrounding history so the user can immediately use arrows / < > from here.
        loadHistoryInBackground(preferredCurrentVersion: version)
    }

    /// Helper for the registry to surface an error on a just-created historical window
    /// (e.g. the git fetch for the blob failed after the window was shown).
    func showTransientHistoricalError(_ message: String) {
        webViewController?.showBanner(message, style: .error, autoDismiss: true)
    }

    private func dismissInfoPanel() {
        if let panel = currentInfoPanel {
            // Removing observer is optional (ARC + willClose will clear the ref),
            // but explicit is fine.
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            panel.close()
            currentInfoPanel = nil
        }
    }

    @objc private func showVersionInfoPanel() {
        let isHistorical = isViewingHistory
        let version = currentHistoricalVersion
        let message: String
        let title: String

        if isHistorical, let v = version {
            title = "Commit \(v.shortSha)"
            message = currentHistoricalFullMessage ?? v.subject
        } else {
            title = "Live"
            message = "Live (working tree)\n\nYou are viewing the current on-disk version of the file."
        }

        // Reuse existing panel for this window if it's still around.
        if let existing = currentInfoPanel {
            existing.title = title
            if let scroll = existing.contentView?.subviews.first as? NSScrollView,
               let textView = scroll.documentView as? NSTextView {
                textView.string = message
            }
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        // Content view with the message.
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))

        let textView = NSTextView(frame: NSRect(x: 16, y: 16, width: 388, height: 120))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.string = message

        // Make the text view wrap nicely.
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: 388, height: 500)

        // Scroll view in case the commit message is long.
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 12, width: 396, height: 126))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        content.addSubview(scroll)

        panel.contentView = content
        panel.setContentSize(NSSize(width: 420, height: 150))

        // Position the panel near the top-left of the main window.
        if let mainWin = window {
            var origin = mainWin.frame.origin
            origin.x += 30
            origin.y = mainWin.frame.maxY - 210
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        // When user closes the popup (red traffic light), clear our ref so next
        // press of ⓘ will create a fresh one.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // The block is @Sendable; we must hop to the main actor to mutate
            // the main-actor-isolated property.
            Task { @MainActor [weak self] in
                self?.currentInfoPanel = nil
            }
        }

        panel.makeKeyAndOrderFront(nil)
        currentInfoPanel = panel
    }

    /// Called by the "Return to current" banner action.
    /// For windows that were opened purely as historical snapshots (Shift-< from live, etc.):
    ///   - If a live window for this document already exists, close this window and bring the live one forward.
    ///   - Otherwise, turn this window into the live viewer (standard behavior).
    /// For in-place historical views inside a live window, just exit historical mode normally.
    private func handleReturnToCurrent() {
        if isPureHistoricalSnapshot {
            let key = markdownDocument.key
            if DocumentWindowRegistry.shared.activateOrAdoptAsLive(self) {
                // A live window already existed (or we just adopted this one).
                // If one already existed, close this historical viewer.
                // The registry's activateOrAdoptAsLive already raised the live one.
                if DocumentWindowRegistry.shared.hasLiveWindow(for: key) {
                    // We were not the one adopted; a different live window existed.
                    // Close ourselves.
                    close()
                }
                // If we were adopted, we are now the live window — do nothing extra.
                return
            }
            // No prior live window — we have been adopted (or the call turned us live).
            // Fall through to normal exit so the content switches to live.
            exitHistoricalView()
            return
        }

        // Normal in-place historical view inside what was originally a live window.
        exitHistoricalView()
    }

    // MARK: - Direct revision selection (titlebar pop-up menu)

    private func setupTitlebarRevisionSelector() {
        // Create the three distinct pop-up buttons once, each permanently wired to its
        // own action. This avoids any risk of the wrong action being attached when we
        // show/hide them via separate accessories.
        ensureRevisionPopUpButtons()

        // Initially we are in single-view mode, so install only the single selector.
        updateRevisionControls()
    }

    private func ensureRevisionPopUpButtons() {
        if revisionPopUpButton == nil {
            let pop = makeRevisionPopUpButton(width: 160)
            pop.target = self
            pop.action = #selector(revisionPopUpAction(_:))
            revisionPopUpButton = pop
        }
        if leftRevisionPopUpButton == nil {
            let pop = makeRevisionPopUpButton(width: 130)
            pop.target = self
            pop.action = #selector(leftRevisionPopUpAction(_:))
            pop.toolTip = "Left side version"
            leftRevisionPopUpButton = pop
        }
        if rightRevisionPopUpButton == nil {
            let pop = makeRevisionPopUpButton(width: 130)
            pop.target = self
            pop.action = #selector(rightRevisionPopUpAction(_:))
            pop.toolTip = "Right side version"
            rightRevisionPopUpButton = pop
        }
    }

    private func makeRevisionPopUpButton(width: CGFloat) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 22), pullsDown: false)
        popUp.controlSize = .small
        popUp.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        popUp.bezelStyle = .rounded
        return popUp
    }

    /// Reconfigures which revision selector(s) are visible in the title bar.
    /// We maintain three distinct, permanently-wired selectors (as requested):
    ///   - revisionPopUpButton (single action) — only visible in normal/single-historical mode
    ///   - leftRevisionPopUpButton (left action) + rightRevisionPopUpButton (right action)
    ///     — only visible in side-by-side comparison mode.
    /// We add/remove whole accessories rather than mutating a shared container.
    /// This guarantees the visible control always has the correct action attached.
    private func updateRevisionControls() {
        ensureRevisionPopUpButtons()

        let inComparison = comparisonVersions != nil

        // Remove whatever revision accessories are currently installed.
        // We manage them as separate mode-specific accessories rather than trying
        // to mutate subviews inside one persistent accessory. This guarantees that
        // whichever selector is visible has the correct action permanently attached.
        removeAllRevisionAccessories()

        if inComparison {
            // Comparison mode: only L and R selectors (no single-view one).
            // Left accessory
            let leftContainer = NSView(frame: NSRect(x: 0, y: 0, width: 145, height: 22))
            let llabel = NSTextField(labelWithString: "L")
            llabel.isEditable = false
            llabel.isBordered = false
            llabel.drawsBackground = false
            llabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            llabel.textColor = .tertiaryLabelColor
            llabel.frame = NSRect(x: 2, y: 4, width: 10, height: 14)
            leftContainer.addSubview(llabel)

            if let leftBtn = leftRevisionPopUpButton {
                leftBtn.frame = NSRect(x: 14, y: 0, width: 125, height: 22)
                leftContainer.addSubview(leftBtn)
            }

            let leftAcc = NSTitlebarAccessoryViewController()
            leftAcc.view = leftContainer
            leftAcc.layoutAttribute = .leading
            window?.addTitlebarAccessoryViewController(leftAcc)
            leftRevisionAccessory = leftAcc

            // Right accessory
            let rightContainer = NSView(frame: NSRect(x: 0, y: 0, width: 145, height: 22))
            let rlabel = NSTextField(labelWithString: "R")
            rlabel.isEditable = false
            rlabel.isBordered = false
            rlabel.drawsBackground = false
            rlabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            rlabel.textColor = .tertiaryLabelColor
            rlabel.frame = NSRect(x: 2, y: 4, width: 10, height: 14)
            rightContainer.addSubview(rlabel)

            if let rightBtn = rightRevisionPopUpButton {
                rightBtn.frame = NSRect(x: 14, y: 0, width: 125, height: 22)
                rightContainer.addSubview(rightBtn)
            }

            let rightAcc = NSTitlebarAccessoryViewController()
            rightAcc.view = rightContainer
            rightAcc.layoutAttribute = .leading
            window?.addTitlebarAccessoryViewController(rightAcc)
            rightRevisionAccessory = rightAcc

            updateComparisonRevisionPopUps()
            updateInfoButtonForCurrentMode()

        } else {
            // Single view mode: only the regular revision selector.
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 170, height: 22))

            if let singleBtn = revisionPopUpButton {
                singleBtn.frame = NSRect(x: 0, y: 0, width: 160, height: 22)
                container.addSubview(singleBtn)
            }

            let acc = NSTitlebarAccessoryViewController()
            acc.view = container
            acc.layoutAttribute = .leading
            window?.addTitlebarAccessoryViewController(acc)
            singleRevisionAccessory = acc

            updateRevisionPopUpButton()
            updateInfoButtonForCurrentMode()
        }
    }

    private func removeAllRevisionAccessories() {
        for acc in [singleRevisionAccessory, leftRevisionAccessory, rightRevisionAccessory].compactMap({ $0 }) {
            if let idx = window?.titlebarAccessoryViewControllers.firstIndex(where: { $0 === acc }) {
                window?.removeTitlebarAccessoryViewController(at: idx)
            }
        }
        singleRevisionAccessory = nil
        leftRevisionAccessory = nil
        rightRevisionAccessory = nil
    }

    private func updateInfoButtonForCurrentMode() {
        guard let btn = infoButton else { return }
        if comparisonVersions != nil {
            btn.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Exit comparison")!
            btn.toolTip = "Return to single document view"
            btn.action = #selector(exitComparisonView)
        } else {
            btn.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Version information")!
            btn.toolTip = "Version information"
            btn.action = #selector(showVersionInfoPanel)
        }
    }

    // MARK: - Revision pop-up helpers (shared by single and dual modes)

    private func populateRevisionMenu(into popUp: NSPopUpButton) {
        let menu = popUp.menu ?? NSMenu()
        menu.removeAllItems()

        if historyVersions.isEmpty {
            let item = NSMenuItem(title: "Loading history…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            popUp.menu = menu
            return
        }

        // Live / working tree (always index 0)
        let liveItem = NSMenuItem(title: historyVersions[0].subject, action: nil, keyEquivalent: "")
        liveItem.representedObject = 0
        menu.addItem(liveItem)

        // Historical commits (newest first after the sentinel)
        for (idx, ver) in historyVersions.enumerated().dropFirst() {
            let sha = ver.shortSha
            let subj = String(ver.subject.prefix(70))
            let title = "\(sha)  \(subj)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = idx
            menu.addItem(item)
        }

        popUp.menu = menu
    }

    private func selectItem(in popUp: NSPopUpButton, index: Int) {
        guard let menu = popUp.menu else { return }
        for item in menu.items {
            if let idx = item.representedObject as? Int, idx == index {
                popUp.select(item)
                return
            }
        }
        if !menu.items.isEmpty {
            popUp.selectItem(at: 0)
        }
    }

    private func updateComparisonRevisionPopUps() {
        guard let leftPop = leftRevisionPopUpButton,
              let rightPop = rightRevisionPopUpButton else { return }
        populateRevisionMenu(into: leftPop)
        populateRevisionMenu(into: rightPop)
        selectItem(in: leftPop, index: comparisonLeftIndex)
        selectItem(in: rightPop, index: comparisonRightIndex)
    }

    private func updateRevisionPopUpButton() {
        guard let popUp = revisionPopUpButton else { return }
        populateRevisionMenu(into: popUp)
        selectItem(in: popUp, index: currentHistoryIndex)
    }

    private func updateRevisionPopUpSelection() {
        guard let popUp = revisionPopUpButton else { return }
        selectItem(in: popUp, index: currentHistoryIndex)
    }

    @objc private func revisionPopUpAction(_ sender: NSPopUpButton) {
        if comparisonVersions != nil {
            // Stale single popup while in comparison — force dual selectors back.
            updateRevisionControls()
            return
        }
        guard let item = sender.selectedItem,
              let index = item.representedObject as? Int else { return }
        jumpToHistoryIndex(index)
    }

    private func jumpToHistoryIndex(_ index: Int) {
        if comparisonVersions != nil {
            updateRevisionControls()
            return
        }
        guard index >= 0 && index < historyVersions.count else { return }
        let target = historyVersions[index]

        if target.isWorkingTree {
            exitHistoricalView()
            return
        }

        // Fetch the blob for this specific revision (we don't cache all of them).
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.gitClient.content(at: target.sha, for: self.markdownDocument.fileURL)
                await MainActor.run {
                    self.applyHistoricalContent(version: target, text: text)
                    self.currentHistoryIndex = index
                    self.updateRevisionControls()
                }
            } catch {
                self.webViewController?.showBanner(
                    "Could not load revision: \(error.localizedDescription)",
                    style: .error,
                    autoDismiss: true
                )
            }
        }
    }

    // MARK: - Settings live-propagation (M9.3)

    private func setupSettingsObserver() {
        settingsCancellable = SettingsStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the new value is committed;
                // dispatch async so we read the updated values.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.webViewController?.applySettings(SettingsStore.shared)
                }
            }
    }

    // MARK: - File watching / live reload

    private func setupFileWatcher() {
        fileWatcher = FileWatcher(url: markdownDocument.fileURL) { [weak self] in
            self?.handleFileChange()
        }
    }

    private func handleFileChange() {
        guard let webVC = webViewController else { return }

        if isViewingHistory {
            // Ignore live file changes while the user is inspecting a historical
            // git revision. The "Return to current" action will pick up reality.
            return
        }

        // File gone? Show a persistent banner and keep the last rendered content.
        guard FileManager.default.fileExists(atPath: markdownDocument.fileURL.path) else {
            webVC.showBanner("File removed: \(markdownDocument.displayTitle)",
                             style: .warning, autoDismiss: false)
            return
        }
        // File returned after being gone — dismiss any stale banner.
        webVC.dismissBanner()

        webVC.captureScrollPosition { [weak self, weak webVC] (scrollY: Double) in
            guard let self, let webVC else { return }
            do {
                try self.markdownDocument.reload()
                webVC.reload(document: self.markdownDocument, restoreScrollY: scrollY)
            } catch {
                webVC.showBanner(
                    "Could not read \(self.markdownDocument.displayTitle): \(error.localizedDescription)",
                    style: .error, autoDismiss: false)
            }
        }
    }
}
