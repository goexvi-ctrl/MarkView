import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Set to true the moment any file is opened (CLI, Finder, session restore, link).
    // Prevents the startup open panel from appearing.
    private var documentOpened = false

    private let sessionKey = "LastSessionDocuments"

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    private func saveSession() {
        let urls = DocumentWindowRegistry.shared.openDocumentURLs()
        UserDefaults.standard.set(urls.map(\.absoluteString), forKey: sessionKey)
    }

    // Returns true if at least one previously-open file was successfully reopened.
    private func restoreSession() -> Bool {
        guard let saved = UserDefaults.standard.stringArray(forKey: sessionKey),
              !saved.isEmpty else { return false }
        var opened = false
        for raw in saved {
            guard let url = URL(string: raw),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            DocumentWindowRegistry.shared.openDocument(url: url)
            opened = true
        }
        return opened
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

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(debugViewFirstHistoricalVersion(_:)) {
            guard let controller = DocumentWindowRegistry.shared.focusedController() else {
                return false
            }
            return controller.isInGitRepository
        }
        if menuItem.action == #selector(debugCompareLiveWithFirstHistorical(_:)) {
            guard let controller = DocumentWindowRegistry.shared.focusedController() else {
                return false
            }
            return controller.isInGitRepository
        }
        if menuItem.action == #selector(compareDocumentWithFile(_:)) {
            return DocumentWindowRegistry.shared.focusedController() != nil
        }
        return true
    }
}
