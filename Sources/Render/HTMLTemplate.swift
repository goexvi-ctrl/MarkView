import Foundation

// Assembles the full HTML document from the rendered body and current settings.
// The template file (WebAssets/template.html) provides the static scaffold;
// this type injects the dynamic parts.
enum HTMLTemplate {

    @MainActor
    static func build(
        body: String,
        settings: SettingsStore,
        zoomFactor: Double,
        nonce: String
    ) -> String {
        // Load template from bundle (M3 wires the real path; stub inline for M1)
        let template = loadTemplate()
        let cssVars = buildCSSVars(settings: settings, zoomFactor: zoomFactor)
        return template
            .replacingOccurrences(of: "{{BODY}}", with: body)
            .replacingOccurrences(of: "{{CSS_VARS}}", with: cssVars)
            .replacingOccurrences(of: "{{NONCE}}", with: nonce)
    }

    private static func loadTemplate() -> String {
        if let url = Bundle.main.url(forResource: "template", withExtension: "html", subdirectory: "WebAssets"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return fallbackTemplate
    }

    @MainActor
    private static func buildCSSVars(settings: SettingsStore, zoomFactor: Double) -> String {
        let bodyFont = settings.bodyFont.isEmpty ? "-apple-system, BlinkMacSystemFont, sans-serif"
                                                 : "\"\(settings.bodyFont)\", sans-serif"
        let codeFont = settings.codeFont.isEmpty ? "\"SF Mono\", \"Fira Mono\", monospace"
                                                 : "\"\(settings.codeFont)\", monospace"
        let baseSize = settings.defaultFontSize
        return """
        :root {
          --body-font: \(bodyFont);
          --code-font: \(codeFont);
          --base-font-size: \(baseSize)px;
          --zoom: \(String(format: "%.2f", zoomFactor));
          --default-code-mode: \(settings.defaultCodeMode.rawValue);
        }
        """
    }

    // Minimal inline fallback used before WebAssets are bundled (M1 skeleton)
    private static let fallbackTemplate = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>{{CSS_VARS}}</style>
    <style>
    html { font-size: calc(var(--base-font-size) * var(--zoom)); }
    body { font-family: var(--body-font); margin: 2em auto; max-width: 860px; padding: 0 1em; }
    pre, code { font-family: var(--code-font); }
    </style>
    </head>
    <body>
    <script>const BRIDGE_NONCE = '{{NONCE}}';</script>
    {{BODY}}
    <script src="asset://app.js"></script>
    </body>
    </html>
    """
}
