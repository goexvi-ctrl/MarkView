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
          .pane-wrapper {
            position: relative;
            flex: 1 1 0;
            min-height: 0;
            min-width: 0;
            display: flex;
          }
          .compare-pane {
            flex: 1 1 0;
            min-width: 0;
            overflow: auto;
            padding: 12px 16px;
            box-sizing: border-box;
            scrollbar-width: none; /* Firefox */
          }
          .compare-pane::-webkit-scrollbar {
            display: none; /* Chrome/Safari/Edge */
          }
          .scrollbar-track {
            position: absolute;
            top: 0;
            right: 0;
            bottom: 0;
            width: 12px;
            background-color: #f1f1f1;
            z-index: 10;
            cursor: pointer;
          }
          .scrollbar-thumb {
            position: absolute;
            left: 1px;
            right: 1px;
            background-color: #c1c1c1;
            border-radius: 6px;
            min-height: 20px;
            cursor: grab;
          }
          .diff-marker {
            position: absolute;
            left: 0;
            right: 0;
            height: 4px;
            border-radius: 2px;
            pointer-events: none;
            z-index: 11;
          }
          .left-track .diff-marker { background-color: #d73a49; }
          .right-track .diff-marker { background-color: #28a745; }
          .compare-pane {
            flex: 1 1 0;
            min-width: 0;
            overflow: auto;
            padding: 12px 16px;
            box-sizing: border-box;
          }
          .pane-with-gutter + .pane-with-gutter .compare-pane {
            border-left: 1px solid #d0d7de;
          }
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

          /* Visual diff highlighting for math formulas (and text).
             For any math formula that differs at all between the two sides, we wrap the
             *entire clean* formula (the actual content from that version) in a <span class="diff-removed">
             or <span class="diff-added">. This gives a whole-formula red tint on the left/older side
             and green tint on the right/newer side, without ever putting HTML or extra LaTeX
             commands inside the math delimiters (so KaTeX always renders the real content cleanly).
             No strikethrough or underline is applied to the math itself. */
          .diff-removed {
            background: #ffcccc !important;
            padding: 1px 3px;
            border-radius: 3px;
            /* no strikethrough on math areas */
            text-decoration: none !important;
          }
          .diff-added {
            background: #ccffcc !important;
            padding: 1px 3px;
            border-radius: 3px;
            text-decoration: none !important;
          }
          /* Ensure the background tint shows through the KaTeX rendering */
          .diff-removed .katex,
          .diff-added .katex,
          .diff-removed .katex * ,
          .diff-added .katex * {
            background: inherit !important;
            text-decoration: none !important;
          }
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
          .compare-panes { width: 100% !important; display: flex !important; }
          .pane-with-gutter { flex: 1 1 0 !important; min-width: 0 !important; }
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
          <div class="pane-wrapper">
            <div class="compare-pane" id="left-pane">
              <div class="pane-label">\(leftEsc)</div>
              \(leftBody)
            </div>
            <div class="scrollbar-track left-track" id="left-track">
              <div class="scrollbar-thumb" id="left-thumb"></div>
              <!-- diff markers added by JS -->
            </div>
          </div>
          <div class="pane-wrapper">
            <div class="compare-pane" id="right-pane">
              <div class="pane-label">\(rightEsc)</div>
              \(rightBody)
            </div>
            <div class="scrollbar-track right-track" id="right-track">
              <div class="scrollbar-thumb" id="right-thumb"></div>
              <!-- diff markers added by JS -->
            </div>
          </div>
        </div>
        <script src="asset://vendor/highlight.min.js"></script>
        <script src="asset://vendor/katex.min.js"></script>
        <script src="asset://vendor/katex-auto-render.min.js"></script>
        <script src="asset://vendor/mermaid.min.js"></script>
        <script>
        const BRIDGE_NONCE = 'compare-only';

        (function() {
          function initCustomScrollbar(paneId, trackId, thumbId, isLeft) {
            const pane = document.getElementById(paneId);
            const track = document.getElementById(trackId);
            const thumb = document.getElementById(thumbId);
            if (!pane || !track || !thumb) return;

            function updateThumb() {
              const scrollHeight = pane.scrollHeight;
              const clientHeight = pane.clientHeight;
              if (scrollHeight <= clientHeight) {
                thumb.style.display = 'none';
                return;
              }
              thumb.style.display = 'block';
              const ratio = clientHeight / scrollHeight;
              const thumbHeight = Math.max(20, ratio * track.clientHeight);
              thumb.style.height = thumbHeight + 'px';

              const scrollRatio = pane.scrollTop / (scrollHeight - clientHeight);
              const maxThumbTop = track.clientHeight - thumbHeight;
              thumb.style.top = (scrollRatio * maxThumbTop) + 'px';
            }

            // Sync thumb when content scrolls
            pane.addEventListener('scroll', updateThumb);
            window.addEventListener('resize', updateThumb);

            // Click on track (not thumb) to jump
            track.addEventListener('click', function(ev) {
              if (ev.target === thumb) return;
              const rect = track.getBoundingClientRect();
              const clickFrac = (ev.clientY - rect.top) / rect.height;
              const targetScroll = clickFrac * (pane.scrollHeight - pane.clientHeight);
              pane.scrollTo({ top: targetScroll, behavior: 'smooth' });
            });

            // Drag the thumb
            let isDragging = false;
            let dragStartY = 0;
            let dragStartScroll = 0;

            thumb.addEventListener('mousedown', function(ev) {
              isDragging = true;
              dragStartY = ev.clientY;
              dragStartScroll = pane.scrollTop;
              document.body.style.userSelect = 'none';
              ev.preventDefault();
            });

            document.addEventListener('mousemove', function(ev) {
              if (!isDragging) return;
              const deltaY = ev.clientY - dragStartY;
              const trackHeight = track.clientHeight;
              const thumbHeight = thumb.clientHeight;
              const scrollableHeight = pane.scrollHeight - pane.clientHeight;
              const dragRatio = deltaY / (trackHeight - thumbHeight);
              pane.scrollTop = dragStartScroll + dragRatio * scrollableHeight;
            });

            document.addEventListener('mouseup', function() {
              if (isDragging) {
                isDragging = false;
                document.body.style.userSelect = '';
                updateThumb();
              }
            });

            // Initial position
            setTimeout(updateThumb, 0);
          }

          function placeDiffMarkers(paneId, trackId, isLeft) {
            const pane = document.getElementById(paneId);
            const track = document.getElementById(trackId);
            if (!pane || !track) return;

            // Remove old markers (keep the thumb)
            track.querySelectorAll('.diff-marker').forEach(m => m.remove());

            const selector = isLeft ? '.diff-removed' : '.diff-added';
            const changedElements = pane.querySelectorAll(selector);
            const scrollHeight = pane.scrollHeight;
            if (scrollHeight <= 0) return;

            changedElements.forEach(el => {
              // Use the top of the changed element relative to the scrollable content
              const frac = el.offsetTop / scrollHeight;
              const marker = document.createElement('div');
              marker.className = 'diff-marker ' + (isLeft ? 'removed' : 'added');
              marker.style.top = (frac * 100) + '%';
              track.appendChild(marker);
            });
          }

          function initAll() {
            initCustomScrollbar('left-pane', 'left-track', 'left-thumb', true);
            initCustomScrollbar('right-pane', 'right-track', 'right-thumb', false);

            // Rich content post-processing for the comparison panes.
            // The comparison document loads the vendor scripts (highlight / katex+auto-render / mermaid)
            // but does not load app.js, so we must explicitly drive the same pipeline here
            // (math, diagrams, syntax highlighting) before the diff markers are placed.
            (function processRichContent() {
              // 1. Mermaid: convert fenced mermaid code blocks inside the panes to renderable divs.
              //    We do a lightweight version of the app.js mermaid handling.
              if (typeof mermaid !== 'undefined' && mermaid) {
                try {
                  // Initialize (safe to call multiple times in modern mermaid).
                  if (typeof mermaid.initialize === 'function') {
                    mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' });
                  }
                  // Find candidates in both panes (the bodies contain the cmark output).
                  const panes = [document.getElementById('left-pane'), document.getElementById('right-pane')];
                  panes.forEach(function(pane) {
                    if (!pane) return;
                    const codes = pane.querySelectorAll('pre code');
                    codes.forEach(function(code) {
                      const cls = code.className || '';
                      const text = (code.textContent || '').trim();
                      const isMermaid = cls.indexOf('language-mermaid') !== -1 || /^graph |^sequenceDiagram|^classDiagram|^stateDiagram|^erDiagram|^flowchart |^gantt |^pie |^journey |^gitGraph |^mindmap |^quadrantChart /i.test(text);
                      if (!isMermaid) return;
                      const pre = code.parentElement;
                      if (!pre || pre.tagName !== 'PRE') return;
                      const div = document.createElement('div');
                      div.className = 'mermaid';
                      div.textContent = text;  // let mermaid read the source
                      // Preserve a data attribute so re-themes (if ever added) could work.
                      div.setAttribute('data-mermaid-source', text);
                      pre.parentNode.replaceChild(div, pre);
                    });
                  });
                  // Render all .mermaid divs we just created.
                  if (typeof mermaid.run === 'function') {
                    mermaid.run();
                  } else if (typeof mermaid.init === 'function') {
                    mermaid.init(undefined, document.querySelectorAll('.mermaid'));
                  }
                } catch (e) {
                  // Non-fatal; diagrams will just show their source.
                }
              }

              // 2. Syntax highlighting (after mermaid conversion so we don't highlight mermaid source).
              if (typeof hljs !== 'undefined' && hljs && typeof hljs.highlightElement === 'function') {
                try {
                  const codes = document.querySelectorAll('#left-pane pre code, #right-pane pre code');
                  codes.forEach(function(block) {
                    const cls = block.className || '';
                    if (cls.indexOf('language-mermaid') !== -1) return;
                    // If it already looks highlighted, skip.
                    if (block.className.indexOf('hljs') === -1) {
                      hljs.highlightElement(block);
                    }
                  });
                } catch (e) {}
              }

              // 3. KaTeX math (the main thing reported as broken in diff mode).
              //    Must run after the bodies are in the DOM and after mermaid (so ignoredClasses works).
              //    We use a more permissive config here (trust + macros) so that annotation
              //    commands commonly used to highlight changes inside formulas work:
              //      $E = {\\color{red}M}c^2$
              //      $E = {\\color{red}\\cancel{M}}c^2$
              //    The atomization in the Swift diff code ensures that even when only part
              //    of a formula differs, the LaTeX source fed to KaTeX stays clean.

              // Debug: log the exact math formulas (as they appear in the DOM text nodes / .math-display)
              // *before* we call renderMathInElement. This lets us see whether \\color, \\cancel etc.
              // survived the diff source rewriting and the Swift math protection pass.
              console.log('=== [MarkView Diff Debug] Math source reaching KaTeX (before render) ===');
              const debugPanes = [
                { el: document.getElementById('left-pane'), side: 'LEFT (older)' },
                { el: document.getElementById('right-pane'), side: 'RIGHT (newer)' }
              ];
              debugPanes.forEach(function(p) {
                if (!p.el) return;
                // Display math (protected by Swift into .math-display divs)
                p.el.querySelectorAll('.math-display').forEach(function(div) {
                  const src = (div.textContent || div.innerText || '').trim();
                  if (src) console.log(p.side + ' [DISPLAY]: ' + src);
                });
                // Inline math: walk text nodes for anything that still has $ \\( \\[ after cmark
                const walker = document.createTreeWalker(p.el, NodeFilter.SHOW_TEXT);
                let n;
                while ((n = walker.nextNode())) {
                  const t = n.textContent || '';
                  if (t.indexOf('$') !== -1 || t.indexOf('\\\\(') !== -1 || t.indexOf('\\\\[') !== -1) {
                    // Log the raw text chunk (may contain surrounding text + the $math$)
                    const short = t.length > 300 ? t.substring(0, 300) + '...' : t;
                    console.log(p.side + ' [inline-ish]: ' + short);
                  }
                }
              });
              console.log('=== end math debug log ===');

              if (typeof renderMathInElement === 'function') {
                try {
                  renderMathInElement(document.body, {
                    delimiters: [
                      { left: '$$',  right: '$$',  display: true  },
                      { left: '\\[', right: '\\]', display: true  },
                      { left: '$',   right: '$',   display: false },
                      { left: '\\(', right: '\\)', display: false },
                    ],
                    ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code', 'option'],
                    ignoredClasses: ['mermaid'],
                    throwOnError: false,
                    trust: true,
                    macros: {
                      // Approximate cancel package using enclose (supported in KaTeX with trust)
                      "\\cancel": "\\enclose{horizontalstrike}{#1}",
                      "\\bcancel": "\\enclose{updiagonalstrike}{#1}",
                      "\\xcancel": "\\enclose{updiagonalstrike horizontalstrike}{#1}",
                      "\\cancelto": "\\enclose{horizontalstrike}{#1 \\rightarrow}" // simplified
                    }
                  });
                } catch (e) {}
              }
            })();

            // Place markers after everything (including mermaid/katex/highlight) has rendered.
            // The rich content above may change heights, so markers are intentionally after.
            setTimeout(function() {
              placeDiffMarkers('left-pane', 'left-track', true);
              placeDiffMarkers('right-pane', 'right-track', false);
            }, 180);

            // Re-place on resize in case layout changes heights
            window.addEventListener('resize', function() {
              setTimeout(function() {
                placeDiffMarkers('left-pane', 'left-track', true);
                placeDiffMarkers('right-pane', 'right-track', false);
              }, 50);
            });
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initAll);
          } else {
            initAll();
          }
        })();
        </script>
        </body>
        </html>
        """
    }
}
