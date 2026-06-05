import AppKit

// Singleton registry mapping DocumentKey -> DocumentWindowController.
// All access must happen on the main actor.
@MainActor
final class DocumentWindowRegistry {

    static let shared = DocumentWindowRegistry()
    private init() {}

    private var windows: [DocumentKey: DocumentWindowController] = [:]

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
            guard let self, let controller else { return }
            self.windows.removeValue(forKey: controller.markdownDocument.key)
        }
    }

    func openDocumentURLs() -> [URL] {
        windows.values.map(\.markdownDocument.fileURL)
    }

    func focusedController() -> DocumentWindowController? {
        guard let win = NSApp.keyWindow else { return nil }
        return windows.values.first { $0.window === win }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MarkView"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
