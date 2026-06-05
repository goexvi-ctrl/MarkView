import Foundation
import Combine

enum CodeViewMode: String, CaseIterable {
    case scroll = "scroll"
    case shrink = "shrink"
}

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"
}

// Observable settings store backed by UserDefaults.
// All open windows observe and update live.
@MainActor
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    private let ud = UserDefaults.standard

    @Published var bodyFont: String {
        didSet { ud.set(bodyFont, forKey: "bodyFont") }
    }
    @Published var codeFont: String {
        didSet { ud.set(codeFont, forKey: "codeFont") }
    }
    @Published var defaultFontSize: Int {
        didSet { ud.set(defaultFontSize, forKey: "defaultFontSize") }
    }
    @Published var defaultCodeMode: CodeViewMode {
        didSet { ud.set(defaultCodeMode.rawValue, forKey: "defaultCodeMode") }
    }
    @Published var appTheme: AppTheme {
        didSet { ud.set(appTheme.rawValue, forKey: "appTheme") }
    }
    @Published var allowUnsafeHTML: Bool {
        didSet { ud.set(allowUnsafeHTML, forKey: "allowUnsafeHTML") }
    }
    @Published var maxRecentDocuments: Int {
        didSet { ud.set(maxRecentDocuments, forKey: "maxRecentDocuments") }
    }

    private init() {
        bodyFont           = ud.string(forKey: "bodyFont") ?? ""
        codeFont           = ud.string(forKey: "codeFont") ?? "SF Mono"
        let stored         = ud.integer(forKey: "defaultFontSize")
        defaultFontSize    = stored > 0 ? stored : 14
        defaultCodeMode    = CodeViewMode(rawValue: ud.string(forKey: "defaultCodeMode") ?? "") ?? .scroll
        appTheme           = AppTheme(rawValue: ud.string(forKey: "appTheme") ?? "") ?? .system
        allowUnsafeHTML    = ud.bool(forKey: "allowUnsafeHTML")
        let storedRecent   = ud.integer(forKey: "maxRecentDocuments")
        maxRecentDocuments = storedRecent > 0 ? storedRecent : 20
    }

    // JSON for applySettings() bridge call
    func cssVariablesJSON() -> String {
        let bodyCSS = bodyFont.isEmpty
            ? "-apple-system, BlinkMacSystemFont, sans-serif"
            : "\"\(bodyFont)\", sans-serif"
        let codeCSS = codeFont.isEmpty
            ? "\"SF Mono\", \"Fira Mono\", monospace"
            : "\"\(codeFont)\", monospace"
        return """
        {"bodyFont":"\(bodyCSS)","codeFont":"\(codeCSS)",\
        "baseFontSize":"\(defaultFontSize)px","defaultCodeMode":"\(defaultCodeMode.rawValue)"}
        """
    }
}

// Per-document zoom memory (UserDefaults, keyed by DocumentKey, LRU cap 256).
@MainActor
final class ZoomMemory {

    static let shared = ZoomMemory()
    private init() { load() }

    private let udKey = "ZoomMemory"
    private let cap   = 256
    private var store: [(path: String, zoom: Double)] = []

    func zoom(for docKey: DocumentKey) -> Double? {
        store.first { $0.path == docKey.canonicalPath }?.zoom
    }

    func setZoom(_ zoom: Double, for docKey: DocumentKey) {
        store.removeAll { $0.path == docKey.canonicalPath }
        store.insert((docKey.canonicalPath, zoom), at: 0)
        if store.count > cap { store = Array(store.prefix(cap)) }
        save()
    }

    private func load() {
        guard let raw = UserDefaults.standard.array(forKey: udKey) as? [[String: Any]] else { return }
        store = raw.compactMap { d in
            guard let p = d["path"] as? String, let z = d["zoom"] as? Double else { return nil }
            return (p, z)
        }
    }

    private func save() {
        let raw = store.map { ["path": $0.path, "zoom": $0.zoom] }
        UserDefaults.standard.set(raw, forKey: udKey)
    }
}
