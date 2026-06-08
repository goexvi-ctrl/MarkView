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

    // MARK: - Comparison (H2 basic surface)

    /// Builds a self-contained side-by-side comparison document.
    /// The two bodies are already rendered via MarkdownRenderer (so they contain
    /// the full <h1>, <p>, <pre> etc. + sanitized HTML). We wrap them in panes.
    @MainActor
    static func buildComparison(
        leftBody: String,
        rightBody: String,
        leftLabel: String,
        rightLabel: String,
        stats: String,
        settings: SettingsStore,
        zoomFactor: Double
    ) -> String {
        let cssVars = buildCSSVars(settings: settings, zoomFactor: zoomFactor)
        let leftEsc = MarkdownRenderer.htmlEscape(leftLabel)
        let rightEsc = MarkdownRenderer.htmlEscape(rightLabel)
        let statsEsc = MarkdownRenderer.htmlEscape(stats)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(cssVars)</style>
        <link rel="stylesheet" href="asset://theme.css">
        <link rel="stylesheet" href="asset://vendor/katex.min.css">
        <link rel="stylesheet" href="asset://vendor/highlight-github.min.css">
        <style>
          /* Base comparison layout (full viewport, flex columns) */
          html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            overflow: hidden;
            box-sizing: border-box;
          }
          body {
            font-family: var(--body-font);
            font-size: calc(var(--base-font-size) * var(--zoom));
            display: flex;
            flex-direction: column;
            background: var(--bg, #fff);
            color: var(--fg, #24292f);
          }
          .compare-header {
            flex-shrink: 0;
            padding: 4px 10px;
            background: #f6f8fa;
            border-bottom: 1px solid #d0d7de;
            font-family: var(--code-font);
            font-size: 10px;
            display: flex;
            align-items: center;
            gap: 8px;
            white-space: nowrap;
            box-sizing: border-box;
          }
          .compare-panes {
            display: flex;
            flex: 1 1 0;
            min-height: 0;
            width: 100%;
            box-sizing: border-box;
          }
          .compare-pane {
            flex: 1 1 0;
            min-width: 0; /* crucial: allows pane to shrink below intrinsic content width on resize */
            overflow: auto;
            padding: 12px 16px;
            box-sizing: border-box;
          }
          .compare-pane + .compare-pane { border-left: 1px solid #d0d7de; }
          .pane-label {
            font-family: var(--code-font);
            font-size: 11px;
            font-weight: 600;
            margin: 0 0 8px 0;
            padding-bottom: 4px;
            border-bottom: 1px solid #eaeef2;
            opacity: 0.85;
          }
          /* Basic block-level hinting for H2.2 (refined in H2.3) */
          .compare-pane .older-hint { background: #ffebe9; }
          .compare-pane .newer-hint { background: #dafbe1; }
        </style>
        <!-- Strong override after theme.css so comparison always uses full window width
             (no "page" max-width cap, and no auto side margins). This also ensures
             the flex panes can grow to 50% each when the window is widened. -->
        <style>
          body {
            max-width: none !important;
            margin: 0 !important;
            padding: 0 !important;
          }
          .compare-panes { width: 100% !important; }
        </style>
        </head>
        <body>
        <div class="compare-header">
          <span>Older: <strong>\(leftEsc)</strong></span>
          <span style="opacity:0.6">•</span>
          <span>\(statsEsc)</span>
          <span style="opacity:0.6">•</span>
          <span>Newer: <strong>\(rightEsc)</strong></span>
        </div>
        <div class="compare-panes">
          <div class="compare-pane">
            <div class="pane-label">\(leftEsc)</div>
            \(leftBody)
          </div>
          <div class="compare-pane">
            <div class="pane-label">\(rightEsc)</div>
            \(rightBody)
          </div>
        </div>
        <script src="asset://vendor/highlight.min.js"></script>
        <script src="asset://vendor/katex.min.js"></script>
        <script src="asset://vendor/katex-auto-render.min.js"></script>
        <script src="asset://vendor/mermaid.min.js"></script>
        <script>const BRIDGE_NONCE = 'compare-only';</script>
        </body>
        </html>
        """
    }
}
