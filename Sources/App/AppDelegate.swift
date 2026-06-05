import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Set to true the moment any file is opened (CLI, Finder, session restore, link).
    // Prevents the startup open panel from appearing.
    private var documentOpened = false

    private let sessionKey = "LastSessionDocuments"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Files passed on the command line
        let fileArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        for arg in fileArgs {
            let url = URL(fileURLWithPath: arg).standardizedFileURL
            DocumentWindowRegistry.shared.openDocument(url: url)
            documentOpened = true
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
}
