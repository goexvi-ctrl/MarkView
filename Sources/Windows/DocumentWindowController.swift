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
        window.contentViewController = webVC

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
            guard let w = window else { return }
            UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: autosaveKey)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak window] _ in
            guard let w = window else { return }
            UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: autosaveKey)
        }

        setupFileWatcher()
        setupSettingsObserver()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Zoom

    func setZoom(_ factor: Double) {
        zoomFactor = factor
        ZoomMemory.shared.setZoom(factor, for: markdownDocument.key)
        webViewController?.setZoom(factor)
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
