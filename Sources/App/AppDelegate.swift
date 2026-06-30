import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted whenever the set of open windows or their diff state changes, so the
    /// session is re-saved incrementally (not just at quit).
    static let markViewSessionDidChange = Notification.Name("MarkViewSessionDidChange")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Set to true the moment any file is opened (CLI, Finder, session restore, link).
    // Prevents the startup open panel from appearing.
    private var documentOpened = false

    private let sessionKey = "LastSessionDocuments"      // legacy: [String] of URLs
    private let sessionKeyV2 = "LastSessionDocumentsV2"  // [[String:String]] with "url" and optional "compareWith"

    // While restoring, suppress incremental saves so a crash mid-restore can't
    // truncate the saved session to the windows reopened so far.
    private var isRestoringSession = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-save the session whenever windows open/close or toggle diff mode, so the
        // on-disk state survives a crash (not just a clean quit).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionStateDidChange),
            name: .markViewSessionDidChange,
            object: nil
        )

        // 1. Files passed on the command line (e.g. `./MarkView some.md` or `open -a MarkView --args some.md`).
        //    Only treat non-option args as files if they actually exist. This prevents stray tokens
        //    (build scripts, shell noise, "YES"/"NO", Xcode scheme args, etc.) from producing scary
        //    "Cannot open YES" alerts.
        let fileArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        for arg in fileArgs {
            let url = URL(fileURLWithPath: arg).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                DocumentWindowRegistry.shared.openDocument(url: url)
                documentOpened = true
            } else {
                // Common when launched from ksh, scripts, Xcode, or certain terminal integrations.
                NSLog("MarkView: ignoring non-existent command-line argument: %@", arg)
            }
        }

        if !documentOpened {
            // 2. Restore the previous session (files that were open when last quit).
            //    One-tick deferral lets application(_:open:) fire first for Finder launches.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.documentOpened else { return }
                if self.restoreSession() {
                    self.documentOpened = true
                } else {
                    self.showOpenPanel()
                }
            }
        }
    }

    // Called between applicationWillFinishLaunching and applicationDidFinishLaunching
    // when launched via Finder "Open With" or drag-onto-dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        documentOpened = true
        for url in urls {
            DocumentWindowRegistry.shared.openDocument(url: url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
    }

    // Re-opening from the Dock with no visible windows
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showOpenPanel()
        }
        return true
    }

    // MARK: - Session persistence

    @objc private func sessionStateDidChange() {
        guard !isRestoringSession else { return }
        saveSession()
    }

    private func saveSession() {
        // Persist each window's primary URL plus, for file-to-file diffs, the URL it
        // is compared against so the diff view can be rebuilt on next launch.
        let encoded: [[String: String]] = DocumentWindowRegistry.shared.sessionDocuments().map { entry in
            var dict = ["url": entry.url.absoluteString]
            if let partner = entry.compareWith {
                dict["compareWith"] = partner.absoluteString
            }
            return dict
        }
        UserDefaults.standard.set(encoded, forKey: sessionKeyV2)
        UserDefaults.standard.removeObject(forKey: sessionKey)  // retire the legacy format
    }

    // Returns true if at least one previously-open file was successfully reopened.
    private func restoreSession() -> Bool {
        let entries = savedSessionEntries()
        guard !entries.isEmpty else { return false }

        // Suppress incremental saves while we reopen windows so a partial restore
        // can't overwrite the saved session. Re-enabled before returning; the diff
        // rebuild (compareWith) runs async and will persist the full state then.
        isRestoringSession = true
        defer { isRestoringSession = false }

        var opened = false
        for entry in entries {
            guard FileManager.default.fileExists(atPath: entry.url.path) else { continue }
            DocumentWindowRegistry.shared.openDocument(url: entry.url)
            opened = true

            // Rebuild a file-to-file diff if the window had one (and the other file
            // still exists). Missing the partner just leaves the single document open.
            if let partner = entry.compareWith,
               FileManager.default.fileExists(atPath: partner.path),
               let controller = DocumentWindowRegistry.shared.controller(for: entry.url) {
                controller.compareWith(fileURL: partner)
            }
        }
        return opened
    }

    /// Reads the saved session, preferring the richer V2 format and falling back to
    /// the legacy plain-URL list written by older builds.
    private func savedSessionEntries() -> [(url: URL, compareWith: URL?)] {
        var result: [(url: URL, compareWith: URL?)] = []
        if let v2 = UserDefaults.standard.array(forKey: sessionKeyV2) as? [[String: String]] {
            for dict in v2 {
                guard let raw = dict["url"], let url = URL(string: raw) else { continue }
                let partner: URL? = dict["compareWith"].flatMap { URL(string: $0) }
                result.append((url: url, compareWith: partner))
            }
            return result
        }
        if let legacy = UserDefaults.standard.stringArray(forKey: sessionKey) {
            for raw in legacy where URL(string: raw) != nil {
                result.append((url: URL(string: raw)!, compareWith: nil))
            }
        }
        return result
    }

    // MARK: - Panels / actions

    func showAboutPanel() {
        let buildDate = Bundle.main.infoDictionary?["BuildDate"] as? String ?? "unknown"
        let credits = NSAttributedString(
            string: "Built: \(buildDate)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func openCheatSheet() {
        guard let url = Bundle.main.url(forResource: "MarkdownCheatSheet",
                                        withExtension: "md") else { return }
        DocumentWindowRegistry.shared.openDocument(url: url)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.allowedContentTypes = [
            UTType(importedAs: "net.daringfireball.markdown"),
            .plainText,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            documentOpened = true
            DocumentWindowRegistry.shared.openDocument(url: url)
        }
    }

    @objc func reloadDocument(_ sender: Any?) {
        if let controller = DocumentWindowRegistry.shared.focusedController() {
            controller.reloadCurrentDocument()
        }
    }

    // MARK: - Find in page (Cmd-F / Cmd-G / Cmd-Shift-G)

    @objc func performFind(_ sender: Any?) {
        DocumentWindowRegistry.shared.focusedController()?.showFindBar()
    }

    @objc func performFindNext(_ sender: Any?) {
        DocumentWindowRegistry.shared.focusedController()?.findNext()
    }

    @objc func performFindPrevious(_ sender: Any?) {
        DocumentWindowRegistry.shared.focusedController()?.findPrevious()
    }

    // Temporary debug hook for H1 git recall (remove or hide behind #if DEBUG later).
    @objc func debugViewFirstHistoricalVersion(_ sender: Any?) {
        guard let controller = DocumentWindowRegistry.shared.focusedController() else { return }
        // Fire-and-forget; the controller method does the async fetch + UI.
        // We ask for history and pick the first real (non-WT) entry if present.
        Task { @MainActor in
            // The GitClient is internal to the controller for now; expose a tiny
            // convenience or just call a method we can add. For the absolute
            // minimum we can cheat by reaching through a future public API.
            // Instead, for immediate testability we add a direct debug path on DWC.
            // (See DocumentWindowController.debugViewFirstHistorical for the impl.)
            controller.debugViewFirstHistoricalVersion()
        }
    }

    // Debug hook for H2 basic comparison surface (live vs first historical commit).
    @objc func debugCompareLiveWithFirstHistorical(_ sender: Any?) {
        guard let controller = DocumentWindowRegistry.shared.focusedController() else { return }
        Task { @MainActor in
            controller.debugCompareLiveWithFirstHistorical()
        }
    }

    /// Real (non-git) command: from the focused document window, let the user pick a
    /// second local file and open a side-by-side rendered diff against it.
    @objc func compareDocumentWithFile(_ sender: Any?) {
        guard let controller = DocumentWindowRegistry.shared.focusedController() else { return }
        controller.compareWithOtherFile()
    }

}
