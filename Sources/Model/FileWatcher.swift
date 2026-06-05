import Foundation

// Watches a file URL for changes using DispatchSource vnode events.
// Handles atomic saves (rename/delete) by watching the parent dir
// and re-arming once the file reappears. Debounce ~150 ms.
@MainActor
final class FileWatcher {

    private let url: URL
    private let callback: @MainActor () -> Void
    // nonisolated(unsafe): accessed only from DispatchSource handlers (main queue),
    // scheduleCallback (@MainActor), and deinit.
    nonisolated(unsafe) private var fileSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var dirSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var debounceWorkItem: DispatchWorkItem?
    private static let debounceMs: Int = 150

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.callback = onChange
        armFileWatch()
    }

    deinit {
        debounceWorkItem?.cancel()
        fileSource?.cancel()
        dirSource?.cancel()
    }

    // MARK: - Watch setup

    private func armFileWatch() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            armDirWatch()
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.handleFileEvent(src) }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }

    private func armDirWatch() {
        let dirPath = url.deletingLastPathComponent().path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.handleDirEvent() }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirSource = src
    }

    // MARK: - Event handlers

    private func handleFileEvent(_ src: DispatchSourceFileSystemObject) {
        let data = src.data
        if data.contains(.rename) || data.contains(.delete) {
            fileSource?.cancel()
            fileSource = nil
            armDirWatch()
        }
        scheduleCallback()
    }

    private func handleDirEvent() {
        if FileManager.default.fileExists(atPath: url.path) {
            dirSource?.cancel()
            dirSource = nil
            armFileWatch()
            scheduleCallback()
        }
    }

    private func scheduleCallback() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.callback()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.debounceMs),
            execute: work
        )
    }
}
