import SwiftUI
import WebKit

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Controls panel
            Form {
                Section("Fonts") {
                    FontPicker(label: "Body font", selection: $settings.bodyFont, monospacedOnly: false)
                    FontPicker(label: "Code font", selection: $settings.codeFont, monospacedOnly: true)
                    Stepper("Default size: \(settings.defaultFontSize) pt",
                            value: $settings.defaultFontSize, in: 8...32)
                }

                Section("View") {
                    Picker("Default code view", selection: $settings.defaultCodeMode) {
                        ForEach(CodeViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    Picker("Theme", selection: $settings.appTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue.capitalized).tag(theme)
                        }
                    }
                }

                Section("History") {
                    Stepper("Recent documents: \(settings.maxRecentDocuments)",
                            value: $settings.maxRecentDocuments, in: 0...50)
                        .help("Maximum number of files shown in File > Open Recent.")
                }

                Section("Advanced") {
                    Toggle("Allow unsafe HTML (beyond GitHub subset)", isOn: $settings.allowUnsafeHTML)
                        .help("Lets raw HTML pass through unsanitized. Only enable for files you fully trust.")
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)

            Divider()

            // Live preview pane (M9.4)
            SettingsPreviewView(settings: settings)
                .frame(width: 360)
        }
        .frame(height: 480)
    }
}

// MARK: - Live preview

struct SettingsPreviewView: NSViewRepresentable {
    let settings: SettingsStore

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: "asset")
        let webView = WKWebView(frame: .zero, configuration: config)
        loadPreview(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadPreview(into: webView)
    }

    @MainActor
    private func loadPreview(into webView: WKWebView) {
        let body = MarkdownRenderer.renderMarkdown(previewMarkdown)
        let html = HTMLTemplate.build(body: body, settings: settings, zoomFactor: 1.0, nonce: "preview")
        webView.loadHTMLString(html, baseURL: nil)
    }

    private let previewMarkdown = """
    # Heading 1
    ## Heading 2

    Regular, *italic*, **bold**, ***bold italic***, ~~strikethrough~~, `code`.

    Underline: <u>underlined text</u>

    > Blockquote paragraph.

    ```swift
    let x = 42
    print("Hello, world!")
    ```

    | Col A | Col B |
    |-------|-------|
    | 1     | 2     |

    - [x] Task done
    - [ ] Task pending

    Math: $E = mc^2$
    """
}
