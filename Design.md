# MarkView - macOS Markdown Viewer

A native macOS application (Swift) that renders Markdown files with GitHub
fidelity, live-reloads on change, and follows links the way a documentation
reader should.

---

## 1. Locked Decisions

These were confirmed before design and constrain everything below.

| Area              | Decision                                                        |
| ----------------- | -------------------------------------------------------------- |
| Rendering engine  | `WKWebView` - Markdown compiled to HTML, styled with CSS, small JS layer for interactivity |
| Markdown dialect  | CommonMark + GitHub Flavored Markdown (tables, task lists, strikethrough, autolinks, footnotes, emoji) |
| Extra features    | Code syntax highlighting, LaTeX math, Mermaid diagrams         |
| Distribution      | Direct / Developer-ID notarized, **non-sandboxed**            |
| Minimum OS        | macOS 15 Sequoia                                               |
| Language / UI     | Swift 6, SwiftUI `App` lifecycle with AppKit interop where needed |

Because distribution is non-sandboxed, the app has full filesystem access.
This removes the need for security-scoped bookmarks and lets the file watcher
and link-follower work against any path the user can read.

---

## 2. Goals and Non-Goals

### Goals
- Render Markdown produced by Claude and by GitHub with high visual fidelity.
- Live refresh when the open file changes on disk, preserving scroll position.
- Resolve internal anchors, open linked local Markdown in managed windows, and
  send external links to the default browser.
- One window per document (open-again brings the existing window forward).
- Responsive reflow on window resize.
- Per-code-block controls: copy, and a toggle between "shrink to fit" and
  "horizontal scroll".
- Full inline styling: regular, *italic*, **bold**, ***bold italic***,
  ~~strikethrough~~, underline, and `fixed/code` font.
- Settings for body font, code font, and default font size.
- Command-`+` / Command-`-` live zoom (plus Command-`0` reset).

### Non-Goals (v1)
- Editing Markdown (viewer only).
- Exporting to PDF/HTML (candidate for v2).
- Remote (http) Markdown documents - only `file://` and bundled assets are
  loaded as documents; remote images are still fetched for display.
- Multi-tab windows (one document = one window).

---

## 3. High-Level Architecture

```
                         +-------------------------------+
                         |        MarkViewApp            |
                         |  (SwiftUI App + AppKit glue)  |
                         +---------------+---------------+
                                         |
              +--------------------------+--------------------------+
              |                          |                          |
   +----------v---------+    +-----------v-----------+   +----------v---------+
   | DocumentWindow     |    |  SettingsStore        |   | OpenDocument flow |
   | Registry           |    |  (UserDefaults +      |   | (menu / dock /    |
   | (URL -> Window)    |    |   Combine publisher)  |   |  link / CLI args) |
   +----------+---------+    +-----------+-----------+   +----------+---------+
              |                          |                          |
   +----------v--------------------------v--------------------------v---------+
   |                       DocumentWindowController                          |
   |  owns: MarkdownDocument, FileWatcher, MarkdownWebView (WKWebView host)  |
   +----------+--------------------------+--------------------------+---------+
              |                          |                          |
   +----------v---------+    +-----------v-----------+   +----------v---------+
   | MarkdownDocument   |    |  FileWatcher          |   | MarkdownRenderer  |
   | (file URL, text,   |    |  (DispatchSource      |   | (cmark-gfm ->     |
   |  canonical key)    |    |   vnode + dir watch)  |   |  HTML + template) |
   +--------------------+    +-----------------------+   +---------+---------+
                                                                   |
                                              +--------------------v--------------------+
                                              |  WebAssets (bundled)                    |
                                              |  template.html, theme.css, app.js,      |
                                              |  highlight.js, katex, mermaid           |
                                              +-----------------------------------------+
```

The Swift side owns state, files, and windows. The WebView owns presentation
and fine-grained interaction; the two talk over a small, explicit message
bridge (Section 8).

---

## 4. Project / Folder Structure

```
MarkView/
  MarkView.xcodeproj
  Package.swift                 # SwiftPM deps (swift-cmark-gfm)
  Sources/
    App/
      MarkViewApp.swift         # @main, App scene, menu commands
      AppDelegate.swift         # NSApplicationDelegate: open files, dock, CLI
      Commands.swift            # Menu: File/Open, View/Zoom, etc.
    Windows/
      DocumentWindowController.swift
      DocumentWindowRegistry.swift
      MarkdownWebView.swift     # NSViewRepresentable / WKWebView host
      WebViewCoordinator.swift  # WKNavigationDelegate + WKScriptMessageHandler
    Model/
      MarkdownDocument.swift
      DocumentKey.swift         # URL canonicalization
      FileWatcher.swift
    Render/
      MarkdownRenderer.swift    # cmark-gfm -> HTML body
      HeadingSlugger.swift      # GitHub-style anchor ids (shared w/ JS spec)
      HTMLTemplate.swift        # body + settings -> full document
      AssetSchemeHandler.swift  # serves bundled libs (App-Store-safe path)
    Settings/
      SettingsStore.swift
      SettingsView.swift        # SwiftUI settings scene
      FontPicker.swift
  Resources/
    WebAssets/
      template.html
      theme.css                 # GitHub-like light + dark
      app.js                    # bridge, code controls, zoom, slugger
      vendor/
        highlight.min.js + github theme css
        katex.min.js + katex.css + auto-render.js
        mermaid.min.js
  Tests/
    RendererTests/              # markdown -> HTML golden tests
    DocumentKeyTests/
    LinkClassifierTests/
```

---

## 5. Rendering Pipeline

### 5.1 Markdown -> HTML (Swift)
- Use **cmark-gfm** (the parser GitHub itself uses) via a thin SwiftPM wrapper
  (`swift-cmark-gfm`, or a vendored C target). It is the most reliable route to
  GitHub fidelity and supports the GFM extensions natively:
  - `table`, `strikethrough`, `autolink`, `tasklist`, `tagfilter`,
    `footnotes`.
- Renderer options: `CMARK_OPT_UNSAFE` is **not** enabled by default; we keep
  raw-HTML sanitization on for safety, with a settings opt-in for users who
  trust their own files and want embedded HTML (Section 11).
- Math and Mermaid are **not** done in cmark; they pass through as text /
  fenced code and are handled client-side (5.3, 5.4).

### 5.2 Heading anchors (internal links)
GitHub auto-assigns each heading an `id` slug. We reproduce its algorithm so
`[link](#some-heading)` works:
1. lowercase the heading text,
2. remove characters that are not letters, numbers, spaces, or hyphens,
3. replace spaces with hyphens,
4. de-duplicate by appending `-1`, `-2`, ... on collision.

Implemented in `app.js` on load (simplest, matches GitHub), with the same
logic available in `HeadingSlugger.swift` for tests and for resolving incoming
fragment links.

### 5.3 Math (KaTeX)
- Bundle KaTeX + its auto-render extension.
- After each (re)load, run auto-render with delimiters:
  `$$...$$` and `\[...\]` (display), `$...$` and `\(...\)` (inline).
- Auto-render is configured to **ignore** `code`, `pre`, and `.mermaid`
  elements so code samples containing `$` are untouched.

### 5.4 Mermaid
- Fenced ```` ```mermaid ```` blocks arrive as
  `<pre><code class="language-mermaid">`.
- In `app.js`, **before** syntax highlighting: find those nodes, extract text,
  replace with a `<div class="mermaid">` and call `mermaid.render`. The
  light/dark theme is chosen from the OS appearance.
- Mermaid blocks are excluded from the copy/scroll code-block toolbar (they are
  diagrams, not code) - though a "copy source" affordance is still offered.

### 5.5 Syntax highlighting
- highlight.js runs on all `pre code[class^="language-"]` **except**
  `language-mermaid`. Unknown languages fall back to auto-detect.

### 5.6 Full document assembly
`HTMLTemplate` injects four things into `template.html`:
1. the rendered body HTML,
2. a `<style>` block of CSS variables from current settings
   (`--body-font`, `--code-font`, `--base-font-size`, `--default-code-mode`),
3. the initial zoom factor,
4. a nonce so the bridge can verify messages.

### 5.7 Plain text (`.txt`) documents
`.txt` files are **not** parsed as Markdown. They are rendered as plain
preformatted text:
- The file content is HTML-escaped and wrapped in a single `<pre>` using the
  configured code font, preserving all whitespace exactly.
- No Markdown parsing, syntax highlighting, math, Mermaid, link auto-detection,
  or heading anchors are applied.
- The shared chrome still works: live reload, Command-+/- zoom, dark mode, and
  a single "copy all" affordance. Long lines get a horizontal scrollbar
  (mouse/trackpad scrolling supported); a View-menu "Soft Wrap" toggle switches
  the block to `white-space: pre-wrap`.
- The renderer dispatches on file extension: `.md`/`.markdown` -> cmark-gfm
  pipeline (5.1-5.6), `.txt` -> this preformatted path.

---

## 6. WebView Asset Loading Strategy

Two classes of resource must load: the **document's own** relative files
(images, sibling `.md`) and the **bundled** libraries (highlight/katex/mermaid).

**Primary approach (chosen, valid because non-sandboxed):**
- Load the generated HTML with
  `webView.loadHTMLString(html, baseURL: documentDirectoryURL)` so the
  document's relative `![](images/x.png)` and `[doc](./other.md)` resolve
  against the file's own folder.
- Enable file access from the file-scheme base by setting, on the
  `WKWebViewConfiguration.preferences`,
  `allowFileAccessFromFileURLs = true` and
  `allowUniversalAccessFromFileURLs = true`. This is acceptable for a
  Developer-ID (non-App-Store) build and lets relative file assets load.
- Serve bundled libraries through a custom `asset://` scheme handled by
  `AssetSchemeHandler` (reads from `Resources/WebAssets`). The template
  references e.g. `asset://vendor/katex.min.js`. Using a scheme handler keeps
  the libs origin-stable and avoids inlining megabytes of JS.

**Fallback / App-Store-safe variant (documented, not used in v1):** route the
document HTML *and* its local resources through the `asset://` handler with the
real path encoded, instead of relying on the file-access prefs. Kept in the
design so a future sandboxed build is a small change, not a rewrite.

Remote images (`https://...`) load normally through the network.

---

## 7. Link Handling

All navigation is intercepted in
`webView(_:decidePolicyFor:decisionHandler:)`. The initial document load is
allowed; every subsequent navigation is classified and **cancelled** after the
app takes the appropriate action.

| Link form                                   | Action                                                                 |
| ------------------------------------------- | --------------------------------------------------------------------- |
| `#fragment` only                            | `cancel`; tell JS to `scrollIntoView` the slug (smooth)               |
| Local path/`file://` ending `.md`/`.markdown` | `cancel`; resolve against doc dir, hand to **OpenDocument** flow (new or existing window) |
| Other local file (`.png`, `.pdf`, ...)      | `cancel`; `NSWorkspace.shared.open` (default app)                     |
| `http`/`https`/`mailto`/`tel`               | `cancel`; `NSWorkspace.shared.open` (default browser/mail)            |
| Anything unresolvable                        | `cancel`; show a transient banner ("file not found: ...")            |

Relative links are resolved with
`URL(string:relativeTo:)` against the document directory and then
standardized. `LinkClassifier` is a pure function (testable) returning a
`LinkAction` enum; the navigation delegate just executes it.

---

## 8. Swift <-> JavaScript Bridge

A single `WKScriptMessageHandler` named `bridge`. Every message is
`{ nonce, type, payload }`; the handler drops messages whose nonce does not
match the document's nonce.

### JS -> Swift

| `type`            | `payload`                       | Swift handles by...                                |
| ----------------- | ------------------------------- | ------------------------------------------------- |
| `openLink`        | `{ href }`                      | running `LinkClassifier` (Section 7)              |
| `copyCode`        | `{ text }`                      | writing to `NSPasteboard`, flashing the button    |
| `requestZoom`     | `{ direction: in/out/reset }`   | updating zoom (also bound to menu, see Section 9) |
| `domReady`        | `{ height }`                    | clearing the loading state                        |
| `scrollPosition`  | `{ y }`                         | caching scrollY for refresh restore (Section 10) |

(Code-block copy/toggle can also be handled purely in JS; the bridge is used
for copy so the native pasteboard is authoritative and works under all
clipboard policies.)

### Swift -> JS (`webView.evaluateJavaScript`)

| Function                       | When                                            |
| ------------------------------ | ----------------------------------------------- |
| `applySettings(json)`          | settings changed (fonts, base size, default code mode) |
| `setZoom(factor)`              | Command-+/-/0 from the menu                      |
| `restoreScroll(y)`             | after a live-reload                              |
| `scrollToAnchor(slug)`         | incoming fragment link                          |
| `setAppearance(light/dark)`    | OS appearance change (mermaid + theme)           |

---

## 9. Fonts and Zoom

### 9.1 Inline styling map
The CSS theme covers every required style; cmark emits standard tags:

| Markdown                  | HTML            | CSS treatment                          |
| ------------------------- | --------------- | -------------------------------------- |
| `*italic*`                | `<em>`          | `font-style: italic`                   |
| `**bold**`                | `<strong>`      | `font-weight: 600`                     |
| `***bold italic***`       | `<em><strong>`  | both                                   |
| `~~strike~~`              | `<del>`         | `text-decoration: line-through`        |
| underline                 | `<u>` / `<ins>` | `text-decoration: underline` (raw HTML `<u>` or `<ins>`; GFM has no native underline) |
| `` `code` ``              | `<code>`        | code font, tinted background           |

Note on underline: standard Markdown has no underline syntax. We honor `<u>`
and `<ins>` HTML via the default sanitized HTML subset (Section 11) - no
"unsafe HTML" toggle required - matching how GitHub renders these tags. This is
documented in the in-app Help so the behavior is predictable.

### 9.2 Settings-driven fonts
- Body font, code font, and default size are CSS variables on `:root`.
- Font pickers list installed families filtered to those usable for body vs.
  monospace (code picker prefers fixed-pitch families).

### 9.3 Zoom (Command-+/-/0)
- Menu items in `Commands.swift`: **Increase (Cmd-=)**, **Decrease (Cmd--)**,
  **Actual Size (Cmd-0)**. (`Cmd-=` is the conventional "+" without Shift.)
- Zoom multiplies a `--zoom` factor (e.g. 0.5 ... 3.0 in 10% steps) applied to
  `font-size` on `html`, so **layout reflows** and code-block fit recomputes.
  We scale font-size rather than `pageZoom` so the "shrink to fit" math stays
  correct.
- Zoom is **per window** at runtime; the default size lives in Settings.
- Per-document zoom is **persisted across launches**: on change, the current
  factor is written to a `ZoomMemory` store (UserDefaults, keyed by
  `DocumentKey`); on open, the saved factor is restored, falling back to the
  Settings default size when none is stored. The store is pruned LRU (cap ~256
  entries) so it cannot grow without bound.

---

## 10. Live Refresh (File Watching)

`FileWatcher` per document:
- Opens the file and arms a `DispatchSource.makeFileSystemObjectSource` for
  `.write`, `.rename`, `.delete`, `.extend`, `.attrib` on the file descriptor.
- Many editors (and atomic saves) **replace** the file, which fires
  `rename`/`delete` and invalidates the fd. On those events the watcher also
  watches the **parent directory** and re-establishes the file watch once the
  path reappears. This is the standard "atomic save" handling and is required
  for files written by Claude/editors.
- Events are **debounced** (~150 ms) to coalesce burst writes.

On a confirmed change:
1. Ask JS for current `scrollPosition`.
2. Re-read the file, re-render to HTML, reload.
3. On `domReady`, call `restoreScroll(y)`.
4. If the file was deleted and not recreated within a grace period, show a
   non-modal banner ("file removed") but keep the last content visible.

---

## 11. Security

- Raw HTML is rendered through a **GitHub-style allowlist sanitizer** by
  default. cmark runs with raw HTML enabled, then the output passes through a
  sanitizer that mirrors GitHub's allowed-tag/attribute set:
  - **Keep** safe presentational/semantic tags incl. the underline-producing
    `<ins>` and `<u>`, plus `<kbd>`, `<sub>`, `<sup>`, `<del>`, etc.
  - **Strip** `<script>`, `<iframe>`, `<object>`, `on*=` event handlers, and
    `javascript:`/`data:` URLs.
  This gives underline (and the rest of GitHub's HTML behavior) safely, even
  though documents auto-reload. The exact allowlist is mirrored against
  GitHub's current sanitization set so parity holds; `<u>` is included only if
  GitHub still permits it (otherwise `<ins>` is the canonical underline tag).
- A separate power-user setting, **"Allow unsafe HTML (beyond GitHub subset)"**
  (default off), bypasses the sanitizer via `CMARK_OPT_UNSAFE` for users who
  fully trust their own files. This is *not* required for underline.
- `asset://` scheme handler only serves files under the bundled `WebAssets`
  directory; path traversal is rejected.
- The bridge validates a per-load nonce, so injected scripts in remote-image
  responses cannot drive native actions.
- JavaScript is enabled (required for KaTeX/Mermaid/highlight) but the document
  is local; no remote script is loaded except none - all libs are bundled.

---

## 12. Open-Document Flow and Window Deduplication

`DocumentKey` canonicalizes a URL: `resolvingSymlinksInPath()` +
`standardizedFileURL` + case-normalization appropriate to the volume. This is
the dictionary key.

`DocumentWindowRegistry` (singleton, main-actor) maps
`DocumentKey -> DocumentWindowController`.

Open request sources, all funneled through `openDocument(url:)`:
- `File > Open...` (NSOpenPanel, `.md`/`.markdown`/`.txt`),
- Finder "Open With" / double-click (`application(_:open:)`),
- Dock drop, command-line argument,
- internal local-`.md` link clicks (Section 7).

`openDocument(url:)`:
1. compute `DocumentKey`,
2. if registry has it -> `makeKeyAndOrderFront`, done,
3. else build `DocumentWindowController`, register, show,
4. on window close -> deregister.

Registered as the handler for `.md`/`.markdown`/`.txt` UTIs in `Info.plist` so
the app appears in "Open With".

---

## 13. Code Block Controls (detail)

Each `<pre>` (except mermaid) gets an absolutely-positioned toolbar (visible on
hover, always visible on touch/no-hover) with two icon buttons:

- **Copy** - copies the raw block text via the native bridge; the icon flashes
  a check on success.
- **Toggle view mode** - switches that block between:
  - **Scroll mode**: `white-space: pre; overflow-x: auto;` with a horizontal
    scrollbar; trackpad/shift-wheel horizontal scrolling works natively.
  - **Shrink mode**: reduce the block's `font-size` until
    `scrollWidth <= clientWidth`. Algorithm: start at base size, measure, and
    scale `newSize = floor(currentSize * clientWidth / scrollWidth)` clamped to
    a floor (e.g. 7px); if the floor still overflows, fall back to scroll mode.

Per-block mode is stored in a `Map<blockIndex, mode>` in JS and re-applied
after live-reload when the block count/content is unchanged (best-effort, keyed
by block index + a hash of its text). The **default** mode comes from Settings.
A `ResizeObserver` recomputes shrink-mode blocks when the window resizes.

---

## 14. Settings

`SettingsStore` is an `ObservableObject` backed by `UserDefaults`, published so
all open windows update live (via `applySettings`).

| Setting                 | Type        | Default                      |
| ----------------------- | ----------- | ---------------------------- |
| Body font family        | String      | system (SF / -apple-system)  |
| Code font family        | String      | SF Mono                      |
| Default font size (pt)  | Int         | 14                           |
| Default code view mode  | scroll/shrink | scroll                     |
| Theme                   | system/light/dark | system                 |
| Allow unsafe HTML*      | Bool        | false                        |

\* "Allow unsafe HTML" lifts the GitHub-style sanitizer (Section 11) for fully
trusted files. Underline and the rest of GitHub's HTML subset work with this
**off**.

Presented via SwiftUI `Settings` scene (Cmd-,) with native `Form` controls and
a live preview pane rendering a sample document.

---

## 15. Edge Cases and Error Handling

- **Huge files**: render off the main thread; show a progress/loading state.
- **Invalid UTF-8**: fall back to `latin1`/lossy decode with a warning banner.
- **Broken/empty Markdown**: render whatever cmark produces (it is tolerant).
- **Symlinked / hardlinked duplicates**: handled by `DocumentKey` canonical.
- **External monitor / appearance change**: re-theme mermaid + CSS via
  `setAppearance`.
- **File replaced by a directory / permissions lost**: banner + keep last view.
- **Anchor not found**: no-op scroll + transient toast.

---

## 16. Dependencies

| Dependency      | Source        | Purpose                              |
| --------------- | ------------- | ------------------------------------ |
| swift-cmark-gfm | SwiftPM / vendored C target | GitHub-grade MD -> HTML  |
| highlight.js    | bundled JS    | code syntax highlighting             |
| KaTeX           | bundled JS/CSS | LaTeX math                          |
| Mermaid         | bundled JS    | diagrams                             |

All web libraries are vendored into `Resources/WebAssets/vendor` (no runtime
network fetch), pinned to specific versions recorded in a `VENDOR.md`.

---

## 17. Testing Plan

- **Golden renderer tests**: a corpus of Markdown inputs (GFM tables, task
  lists, nested lists, code fences, footnotes, math, mermaid) -> expected HTML
  fragments. Includes real Claude- and GitHub-generated samples.
- **DocumentKey tests**: symlinks, `.`/`..`, trailing slash, case.
- **LinkClassifier tests**: every row of the Section 7 table.
- **HeadingSlugger tests**: collisions, punctuation, unicode.
- **Manual / UI smoke**: live-reload on save, window dedup, zoom, per-block
  toggle, copy, settings live-update, external link to browser.

A `Tasks.md` will track milestones (Section 18) with the
NEW/STARTED/CODED/TESTED/DONE lifecycle.

---

## 18. Implementation Milestones

1. **Skeleton**: app, window, NSOpenPanel, load a hardcoded HTML into WKWebView.
2. **Renderer**: cmark-gfm wrapper + template + theme.css; static render of a
   file with correct GFM and inline styles.
3. **Asset loading**: `asset://` handler + file-access prefs; images and
   bundled libs load.
4. **Highlight + KaTeX + Mermaid** wired in `app.js`.
5. **Link handling**: classifier + navigation delegate + window registry/dedup.
6. **Live reload**: FileWatcher with atomic-save handling + scroll restore.
7. **Code-block controls**: toolbar, copy via bridge, scroll/shrink toggle,
   ResizeObserver.
8. **Zoom**: menu commands + `setZoom`, reflow + shrink recompute.
9. **Settings**: store, SwiftUI settings scene, live `applySettings`.
10. **Polish**: dark mode, error banners, Info.plist UTIs, notarization.

---

## 19. Open Questions

- **Q1 Underline** (resolved): render a **GitHub-style sanitized HTML subset**
  that includes `<ins>`/`<u>` by default; no "unsafe HTML" toggle needed. A
  separate opt-in lifts the sanitizer for fully trusted files. See Section 11.
- **Q2 Per-document zoom** (resolved): **persisted across launches**, on by
  default. See Section 9.3.
- **Q3 .txt files** (resolved): rendered as **plain preformatted text**, not
  Markdown. See Section 5.7.

---

## 20. Implementation Model Recommendation

**Recommendation: implement with Sonnet 4.6.**

Rationale for cost-effectiveness:
- This design is intentionally prescriptive - module boundaries, the bridge
  message contract, the link-classification table, the asset-loading strategy,
  and the file-watching edge cases are all specified. The hard *design*
  thinking (where models differ most) is already done; what remains is
  well-trodden macOS/WebKit implementation work.
- Every component maps to standard, well-documented patterns: `WKWebView` +
  `WKScriptMessageHandler`, `DispatchSource` file watching, `NSWorkspace.open`,
  `NSWindowController` management, SwiftUI `Settings`. Sonnet 4.6 is strong on
  exactly this kind of conventional, pattern-following code, at a small
  fraction of Opus 4.8's per-token cost.
- The riskiest spots (the JS<->Swift bridge, atomic-save re-watching, and the
  shrink-to-fit measurement loop) are isolated and individually small. Even if
  they need an extra debugging iteration, the total Sonnet spend stays well
  below a single Opus 4.8 high-effort pass.

**Escalation rule**: if Sonnet stalls on a specific sub-problem - most likely
the WKWebView file-access/asset wiring or mermaid+highlight ordering - escalate
*only that sub-task* to Opus 4.8 high effort rather than switching the whole
build. This keeps the expensive model targeted at genuine difficulty.

Opus 4.8 high effort would also produce a working result, and likely with fewer
iterations, but the marginal quality gain on this well-specified, convention-
heavy app does not justify the cost premium for the primary build.

---

## 21. Build, Run, Distribution

- Xcode project, Swift 6, deployment target macOS 15.0.
- SwiftPM for `swift-cmark-gfm`; web libs vendored (no CDN).
- `Info.plist`: document types for `net.daringfireball.markdown` (`.md`,
  `.markdown`) and `public.plain-text` (`.txt`), `CFBundleDocumentTypes` +
  `Viewer` role so the app shows in "Open With".
- Sign with Developer ID, **notarize**, staple. Non-sandboxed entitlements;
  no special entitlement needed for arbitrary file reads outside the sandbox.
