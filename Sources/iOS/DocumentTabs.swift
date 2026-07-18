import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    // Declared in Info-iPad.plist UTImportedTypeDeclarations.
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

// One open document (tab). fileURL is nil for inline markview:// content.
struct OpenDocument: Identifiable {
    let id = UUID()
    let fileURL: URL?
    let displayName: String
    var text: String
    let fileType: MarkdownDocument.FileType
    let usedLossyEncoding: Bool
    let holdsSecurityScope: Bool
    let canonicalPath: String?   // dedupe key for file-backed tabs
    // Sender-requested cleanup (markview://...&deleteonclose=1): the file is
    // deleted when this tab closes. Best-effort; not applied if the app
    // terminates with the tab still open.
    var deleteOnClose: Bool
}

// All open documents in the single MarkView window, plus the selection.
// Files-app opens, the file picker, markview:// URLs, and internal .md
// links all funnel through here so every document becomes a tab.
@MainActor
final class DocumentTabsModel: ObservableObject {

    @Published private(set) var documents: [OpenDocument] = []
    @Published var selectedID: OpenDocument.ID?

    // Scroll positions per tab. Deliberately not @Published: scroll events
    // arrive continuously and must not invalidate the whole view tree.
    private var scrollPositions: [OpenDocument.ID: Double] = [:]

    var selectedDocument: OpenDocument? {
        documents.first { $0.id == selectedID }
    }

    func scrollBinding(for id: OpenDocument.ID) -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.scrollPositions[id] ?? 0 },
            set: { [weak self] y in self?.scrollPositions[id] = y }
        )
    }

    /// Opens a file-backed tab (Files app, file picker, internal links,
    /// markview://...?file=). Re-selects an existing tab for the same file.
    /// Returns an error message on failure.
    @discardableResult
    func openFile(_ url: URL, deleteOnClose: Bool = false) -> String? {
        let canonical = DocumentKey(url: url).canonicalPath
        if let index = documents.firstIndex(where: { $0.canonicalPath == canonical }) {
            if deleteOnClose { documents[index].deleteOnClose = true }
            selectedID = documents[index].id
            return nil
        }

        // Files-app / picker URLs are security-scoped; the scope is held for
        // the life of the tab (released in close). Returns false for plain
        // paths already inside our sandbox, which is fine.
        let scoped = url.startAccessingSecurityScopedResource()

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return "Cannot open \(url.lastPathComponent): no access to that file from here."
        }

        let text: String
        let lossy: Bool
        if let clean = String(data: data, encoding: .utf8) {
            text = clean
            lossy = false
        } else {
            text = String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            lossy = true
        }

        let doc = OpenDocument(
            fileURL: url,
            displayName: url.lastPathComponent,
            text: text,
            fileType: url.pathExtension.lowercased() == "txt" ? .plainText : .markdown,
            usedLossyEncoding: lossy,
            holdsSecurityScope: scoped,
            canonicalPath: canonical,
            deleteOnClose: deleteOnClose
        )
        documents.append(doc)
        selectedID = doc.id
        return nil
    }

    /// Opens (or updates) a tab for a markview:// payload. Inline content
    /// replaces an existing inline tab with the same name, so an app that
    /// repeatedly sends updated content reuses its tab.
    func open(payload: SchemePayload) {
        if let fileURL = payload.fileURL {
            _ = openFile(fileURL, deleteOnClose: payload.deleteOnClose)
            return
        }
        if let index = documents.firstIndex(where: {
            $0.fileURL == nil && $0.displayName == payload.name
        }) {
            documents[index].text = payload.text
            selectedID = documents[index].id
            return
        }
        let doc = OpenDocument(
            fileURL: nil,
            displayName: payload.name,
            text: payload.text,
            fileType: payload.fileType,
            usedLossyEncoding: payload.usedLossyEncoding,
            holdsSecurityScope: false,
            canonicalPath: nil,
            deleteOnClose: false
        )
        documents.append(doc)
        selectedID = doc.id
    }

    func close(_ id: OpenDocument.ID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let doc = documents[index]
        if let url = doc.fileURL {
            // Delete while any security scope is still active, then release it.
            if doc.deleteOnClose {
                try? FileManager.default.removeItem(at: url)
            }
            if doc.holdsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        documents.remove(at: index)
        scrollPositions[id] = nil
        if selectedID == id {
            let neighbor = min(index, documents.count - 1)
            selectedID = neighbor >= 0 ? documents[neighbor].id : nil
        }
    }
}

// Root view of the single MarkView window: tab strip + selected document.
struct DocumentTabsView: View {

    @StateObject private var model = DocumentTabsModel()
    @State private var showImporter = false
    @State private var bannerText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.documents.isEmpty {
                    tabStrip
                    Divider()
                }
                content
            }
            .navigationTitle(model.selectedDocument?.displayName ?? "MarkView")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "folder")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.markdownDocument, .plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    if let error = model.openFile(url) { showBanner(error) }
                }
            }
        }
        .onOpenURL { url in handleIncoming(url) }
        .overlay(alignment: .top) { bannerOverlay }
        #if DEBUG
        // Headless test hook: space-separated URLs injected via the launch
        // environment travel the same path as real markview:// opens.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let raw = env["MARKVIEW_TEST_URLS"] {
                for part in raw.split(separator: " ") {
                    if let url = URL(string: String(part)) { handleIncoming(url) }
                }
            }
            // Exercises the tab-close path (incl. deleteonclose) headlessly.
            if let delay = env["MARKVIEW_TEST_CLOSE_SELECTED_AFTER"].flatMap(Double.init) {
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    if let id = model.selectedID { model.close(id) }
                }
            }
        }
        #endif
    }

    // MARK: - Incoming URLs (Files app opens + markview:// scheme)

    private func handleIncoming(_ url: URL) {
        if url.scheme?.lowercased() == "markview" {
            switch MarkViewURLParser.parse(url) {
            case .success(let payload):
                model.open(payload: payload)
            case .failure(let error):
                showBanner(error.message)
            }
        } else if url.isFileURL {
            if let error = model.openFile(url) { showBanner(error) }
        }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.documents) { doc in
                    tabChip(doc)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }

    private func tabChip(_ doc: OpenDocument) -> some View {
        let isSelected = doc.id == model.selectedID
        return HStack(spacing: 6) {
            Text(doc.displayName)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
            Button {
                model.close(doc.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                       : AnyShapeStyle(Color.clear),
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture { model.selectedID = doc.id }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let doc = model.selectedDocument {
            DocumentViewerView(
                text: doc.text,
                fileURL: doc.fileURL,
                usedLossyEncoding: doc.usedLossyEncoding,
                fileTypeOverride: doc.fileType,
                scrollY: model.scrollBinding(for: doc.id),
                onOpenMarkdownFile: { url in
                    if let error = model.openFile(url) { showBanner(error) }
                }
            )
            .id(doc.id)
        } else {
            ContentUnavailableView {
                Label("No Document Open", systemImage: "doc.text")
            } description: {
                Text("Open a Markdown file with the folder button, from the "
                    + "Files app, or from another app's share sheet. Apps can "
                    + "also send content via markview:// URLs.")
            } actions: {
                Button("Open Markdown File") { showImporter = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var bannerOverlay: some View {
        if let bannerText {
            Text(bannerText)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: bannerText) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { self.bannerText = nil }
                }
        }
    }

    private func showBanner(_ message: String) {
        withAnimation { bannerText = message }
    }
}
