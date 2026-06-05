import Foundation
import Combine

// Tracks recently opened files, persisted in UserDefaults.
// Max count is read from SettingsStore.shared.maxRecentDocuments.
@MainActor
final class RecentDocumentsStore: ObservableObject {

    static let shared = RecentDocumentsStore()

    private let udKey = "RecentDocuments"
    @Published private(set) var urls: [URL] = []

    private var settingsCancellable: AnyCancellable?

    private init() {
        load()
        // Truncate list whenever the max count setting changes
        settingsCancellable = SettingsStore.shared.$maxRecentDocuments
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.trimAndSave() }
    }

    // MARK: - Mutations

    func add(_ url: URL) {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        urls.removeAll { $0.resolvingSymlinksInPath().standardizedFileURL == canonical }
        urls.insert(canonical, at: 0)
        trimAndSave()
    }

    func clear() {
        urls = []
        UserDefaults.standard.removeObject(forKey: udKey)
    }

    // MARK: - Private

    private func trimAndSave() {
        let cap = max(1, SettingsStore.shared.maxRecentDocuments)
        if urls.count > cap { urls = Array(urls.prefix(cap)) }
        save()
    }

    private func load() {
        guard let raw = UserDefaults.standard.array(forKey: udKey) as? [String] else { return }
        let cap = max(1, SettingsStore.shared.maxRecentDocuments)
        urls = raw.prefix(cap).compactMap { URL(string: $0) }
    }

    private func save() {
        UserDefaults.standard.set(urls.map(\.absoluteString), forKey: udKey)
    }
}
