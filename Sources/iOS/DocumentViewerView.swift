import SwiftUI

// Events surfaced by PadWebCoordinator that need view-level handling.
enum PadWebEvent {
    case openMarkdown(URL)   // internal link to another markdown file
    case banner(String)      // transient message for the user
}

// A linked document loaded for presentation in a sheet. iOS has no
// programmatic way to open a new DocumentGroup scene, so internal .md
// links are shown in a nested viewer instead.
private struct LinkedDocument: Identifiable {
    let url: URL
    let text: String
    let usedLossyEncoding: Bool
    var id: String { url.path }
}

// Viewer surface for one open document: web view + toolbar + banners.
struct DocumentViewerView: View {

    let text: String
    let fileURL: URL?
    let usedLossyEncoding: Bool
    let fileTypeOverride: MarkdownDocument.FileType?
    // Tab-context hooks: scroll position survives tab switches via scrollY;
    // internal .md links open as tabs when onOpenMarkdownFile is provided
    // (fallback is a nested viewer sheet).
    let scrollY: Binding<Double>?
    let onOpenMarkdownFile: ((URL) -> Void)?

    @ObservedObject private var settings = SettingsStore.shared
    @StateObject private var proxy = WebViewProxy()
    @State private var bannerText: String?
    @State private var showSettings = false
    @State private var linkedDocument: LinkedDocument?

    init(
        text: String,
        fileURL: URL?,
        usedLossyEncoding: Bool,
        fileTypeOverride: MarkdownDocument.FileType? = nil,
        scrollY: Binding<Double>? = nil,
        onOpenMarkdownFile: ((URL) -> Void)? = nil
    ) {
        self.text = text
        self.fileURL = fileURL
        self.usedLossyEncoding = usedLossyEncoding
        self.fileTypeOverride = fileTypeOverride
        self.scrollY = scrollY
        self.onOpenMarkdownFile = onOpenMarkdownFile
    }

    private var fileType: MarkdownDocument.FileType {
        fileTypeOverride
            ?? (fileURL?.pathExtension.lowercased() == "txt" ? .plainText : .markdown)
    }

    var body: some View {
        PadWebView(
            text: text,
            fileType: fileType,
            fileURL: fileURL,
            allowUnsafeHTML: settings.allowUnsafeHTML,
            proxy: proxy,
            scrollY: scrollY,
            onEvent: handle(event:)
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay(alignment: .top) { bannerOverlay }
        .sheet(isPresented: $showSettings) { PadSettingsView() }
        .sheet(item: $linkedDocument) { linked in
            NavigationStack {
                DocumentViewerView(
                    text: linked.text,
                    fileURL: linked.url,
                    usedLossyEncoding: linked.usedLossyEncoding
                )
                .navigationTitle(linked.url.lastPathComponent)
            }
        }
        .onAppear {
            if usedLossyEncoding {
                showBanner("This file contains invalid UTF-8 and was decoded with a lossy fallback.")
            }
        }
        .onChange(of: settings.defaultFontSize) { proxy.applySettings() }
        .onChange(of: settings.defaultCodeMode) { proxy.applySettings() }
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: ColorScheme? {
        switch settings.appTheme {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                proxy.presentFind()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            Menu {
                Button("Increase Font Size") { proxy.zoomIn() }
                Button("Decrease Font Size") { proxy.zoomOut() }
                Button("Actual Font Size") { proxy.zoomReset() }
            } label: {
                Image(systemName: "textformat.size")
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }

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

    private func handle(event: PadWebEvent) {
        switch event {
        case .banner(let message):
            showBanner(message)
        case .openMarkdown(let url):
            if let onOpenMarkdownFile {
                onOpenMarkdownFile(url)
            } else {
                openLinkedMarkdown(url)
            }
        }
    }

    // Reads a linked markdown file and presents it in a nested viewer sheet.
    // The read can fail when the link target is outside our sandbox access
    // (open-in-place grants access to the opened file only).
    private func openLinkedMarkdown(_ url: URL) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            showBanner("Cannot open \(url.lastPathComponent): no access to that file from here.")
            return
        }
        if let clean = String(data: data, encoding: .utf8) {
            linkedDocument = LinkedDocument(url: url, text: clean, usedLossyEncoding: false)
        } else {
            let fallback = String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            linkedDocument = LinkedDocument(url: url, text: fallback, usedLossyEncoding: true)
        }
    }

    private func showBanner(_ message: String) {
        withAnimation { bannerText = message }
    }
}
