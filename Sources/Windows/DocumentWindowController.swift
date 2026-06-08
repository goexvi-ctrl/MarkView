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

    /// The (optional) info popup panel for this window. We keep at most one per DWC
    /// so that repeated presses of the titlebar ⓘ reuse it instead of spawning multiples.
    private var currentInfoPanel: NSPanel?

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

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .leading

        window?.addTitlebarAccessoryViewController(accessory)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        // Ensure any orphaned info popup is closed when this controller is released.
        // deinit runs in a non-isolated context even for @MainActor classes, so
        // we must explicitly assume main-actor isolation (safe for UI controllers
        // that are always deallocated on the main thread).
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
    }

    func exitHistoricalView() {
        guard isViewingHistory else { return }
        dismissInfoPanel()  // old popup is no longer accurate for the live view

        isViewingHistory = false
        currentHistoryIndex = 0
        currentHistoricalVersion = nil
        currentHistoricalFullMessage = nil

        // Restore normal title.
        window?.title = markdownDocument.displayTitle

        webViewController?.exitHistoricalView()

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
        // If we are on the live view, force index 0 so that plain "<" (older) from live
        // always means "go to the most recent checked-in revision".
        if !isViewingHistory {
            currentHistoryIndex = 0
        }

        // Ensure we have the ordered list (newest first after the working-tree sentinel).
        if historyVersions.isEmpty {
            do {
                historyVersions = try await gitClient.history(for: markdownDocument.fileURL, limit: 100)
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
