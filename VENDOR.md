## Vendored Libraries

| Library | Version | Notes |
|---------|---------|-------|
| cmark-gfm | 0.29.0.gfm.13 | GitHub's Markdown parser; vendored C target at Vendor/CmarkGFM/ |
| highlight.js | 11.9.0 | Code syntax highlighting; highlight.min.js + github.min.css |
| KaTeX | 0.16.9 | LaTeX math; katex.min.js + katex-auto-render.min.js + katex.min.css + 20 woff2 fonts |
| Mermaid | 10.6.1 | Diagram rendering; mermaid.min.js |

All web libraries are in Resources/WebAssets/vendor/ and are served via the asset:// scheme
handler. No CDN fetch occurs at runtime.

cmark-gfm generated files (config.h, cmark-gfm_version.h, cmark-gfm_export.h) were created
manually from the cmake templates with values for 0.29.0.gfm.13.
