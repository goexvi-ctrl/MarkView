import AppKit

// Singleton registry mapping DocumentKey -> DocumentWindowController.
// All access must happen on the main actor.
@MainActor
final class DocumentWindowRegistry {

    static let shared = DocumentWindowRegistry()
    private init() {}

    private var windows: [DocumentKey: DocumentWindowController] = [:]

    // Strong references to "ephemeral" / pure-historical snapshot windows (the ones
    // created via Shift-< etc. and openHistoricalVersion). We intentionally do *not*
    // put them in the main `windows` dict (so they can coexist with the live doc window).
    // Without a strong ref here they can be deallocated while their NSWindow/webView
    // is still alive, which breaks the weak `owningDocumentWindowController` and the
    // [weak self] closures that the key handler relies on. We clean up on willClose.
    private var historicalSnapshotControllers: [DocumentWindowController] = []

    func openDocument(url: URL) {
        let key = DocumentKey(url: url)
        if let existing = windows[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            existing.window?.orderFrontRegardless()
            return
        }
        let doc: MarkdownDocument
        do {
            doc = try MarkdownDocument(url: url)
        } catch {
            showError("Cannot open \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        let controller = DocumentWindowController(document: doc)
        windows[key] = controller
        controller.showWindow(nil)
        RecentDocumentsStore.shared.add(url)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { [weak self, weak controller] _ in
            // The closure may be invoked from a Sendable context; ensure main-actor
            // isolation for the mutation of the `windows` dictionary.
            Task { @MainActor in
                guard let self, let controller else { return }
                self.windows.removeValue(forKey: controller.markdownDocument.key)
            }
        }
    }

    func openDocumentURLs() -> [URL] {
        windows.values.map(\.markdownDocument.fileURL)
    }

    func focusedController() -> DocumentWindowController? {
        guard let win = NSApp.keyWindow else { return nil }
        return windows.values.first { $0.window === win }
    }

    /// Returns whether a live (non-historical) window for this document key is currently open.
    func hasLiveWindow(for key: DocumentKey) -> Bool {
        windows[key] != nil
    }

    /// If a live window for the key exists, bring it forward and return true.
    /// Otherwise, adopt the given controller as the canonical live window for the document
    /// (so future opens of the live file will raise this window) and wire its close observer.
    @discardableResult
    func activateOrAdoptAsLive(_ controller: DocumentWindowController) -> Bool {
        let key = controller.markdownDocument.key
        if let existing = windows[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            existing.window?.orderFrontRegardless()
            return true
        }

        // Adopt this controller as the live one.
        windows[key] = controller

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { [weak self, weak controller] _ in
            // The closure may be invoked from a Sendable context; ensure main-actor
            // isolation for the mutation of the `windows` dictionary.
            Task { @MainActor in
                guard let self, let controller else { return }
                self.windows.removeValue(forKey: controller.markdownDocument.key)
            }
        }

        return false
    }

    /// Opens a new window showing a specific historical git revision of the document
    /// at the given URL. The window is independent (does not participate in live-document
    /// deduplication via the registry) so you can have the live version + multiple historical
    /// snapshots visible at the same time.
    func openHistoricalVersion(for url: URL, version: GitVersion) {
        let doc: MarkdownDocument
        do {
            doc = try MarkdownDocument(url: url)
        } catch {
            showError("Cannot open \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }

        let controller = DocumentWindowController(document: doc)
        // Keep a strong reference so the DWC (and its weak back-pointers + [weak self]
        // closures for the < > key handler) stay alive for the lifetime of the window.
        // These are *not* registered in the main live-doc `windows` dict.
        historicalSnapshotControllers.append(controller)

        // Intentionally not inserting into `windows` — historical snapshot windows are
        // allowed to coexist with the live viewer for the same document.
        controller.showWindow(nil)

        // Clean up the strong ref when the window goes away (prevents leaks, allows
        // the DWC to be released after close).
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { [weak self, weak controller] _ in
            Task { @MainActor in
                guard let self, let controller else { return }
                self.historicalSnapshotControllers.removeAll { $0 === controller }
            }
        }

        // Fetch the blob content and configure the controller as a historical viewer.
        Task { @MainActor in
            do {
                let client = GitClient()
                let text = try await client.content(at: version.sha, for: url)
                controller.configureAsInitialHistorical(version: version, text: text)
            } catch {
                // The window is already visible; show a banner on it.
                controller.showTransientHistoricalError("Could not load revision: \(error.localizedDescription)")
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MarkView"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
