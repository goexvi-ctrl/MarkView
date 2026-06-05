# MarkView - Implementation Tasks

Task tracker for the MarkView macOS Markdown viewer. See `Design.md` for the
full design; section references (e.g. "D-7") point at the relevant Design.md
section.

## Status lifecycle
- NEW     - not started
- STARTED - in progress
- CODED   - implementation written, not yet fully tested
- TESTED  - tested to 100% (all acceptance criteria pass)
- DONE    - no further work needed

Update the status tag in brackets at the start of each task as work proceeds.
Keep this file ASCII-only.

---

## M1 - Project Skeleton (D-4, D-21)

- [DONE] M1.1 Create Xcode project: Swift 6, SwiftUI App lifecycle, deployment
  target macOS 15.0, non-sandboxed entitlements.
- [DONE] M1.2 Add `Package.swift` / SPM integration for `swift-cmark-gfm`
  (or vendor a cmark-gfm C target).
- [DONE] M1.3 Lay out the folder structure from D-4 (App, Windows, Model,
  Render, Settings, Resources/WebAssets, Tests).
- [DONE] M1.4 `MarkViewApp.swift` + `AppDelegate.swift`: app boots, empty
  window, `File > Open...` (NSOpenPanel filtered to md/markdown/txt).
- [DONE] M1.5 Load a hardcoded HTML string into a `WKWebView` host
  (`MarkdownWebView`) and confirm it displays.
  - Acceptance: app launches, Open panel appears, a static page renders.

## M2 - Markdown Renderer (D-5.1, D-5.2, D-5.6)

- [DONE] M2.1 `MarkdownRenderer`: wrap cmark-gfm; enable extensions table,
  strikethrough, autolink, tasklist, tagfilter, footnotes.
- [DONE] M2.2 `HeadingSlugger.swift`: GitHub slug algorithm (lowercase, strip
  punctuation, spaces->hyphens, dedupe). Unit-tested.
- [DONE] M2.3 `HTMLTemplate.swift`: inject body HTML, CSS variables (body/code
  font, base size, default code mode), initial zoom factor, and bridge nonce
  into `template.html`.
- [DONE] M2.4 `theme.css`: GitHub-like light + dark; full inline style map from
  D-9.1 (em/strong/both, del strikethrough, ins/u underline, code).
- [DONE] M2.5 Golden renderer tests (D-17): GFM tables, task lists, nested
  lists, code fences, footnotes; include real Claude- and GitHub-authored docs.
  - Acceptance: rendering a sample doc matches expected HTML fragments; all
    inline styles render correctly.

## M3 - WebView Asset Loading (D-6)

- [DONE] M3.1 `AssetSchemeHandler` (`asset://`) serving files from bundled
  `Resources/WebAssets`; reject path traversal.
- [DONE] M3.2 Enable `allowFileAccessFromFileURLs` /
  `allowUniversalAccessFromFileURLs` on the WKWebView config.
- [DONE] M3.3 Load generated HTML via `loadHTMLString(_, baseURL:
  documentDirectoryURL)` so relative images and links resolve.
- [DONE] M3.4 Verify local relative images, bundled libs, and remote (https)
  images all load.
  - Acceptance: a doc with `![](images/x.png)`, an https image, and bundled JS
    all display.

## M4 - Rich Content: Highlight + Math + Mermaid (D-5.3, D-5.4, D-5.5)

- [DONE] M4.1 Vendor highlight.js, KaTeX (+auto-render), Mermaid into
  `WebAssets/vendor`; record versions in `VENDOR.md`.
- [DONE] M4.2 `app.js`: on load, assign heading ids (slugger), then render
  Mermaid blocks (before highlight), then highlight.js (excluding
  language-mermaid), then KaTeX auto-render (ignoring code/pre/.mermaid).
- [CODED] M4.3 Mermaid + theme follow OS appearance via `setAppearance`.
  - Acceptance: a doc with a fenced mermaid block, `$...$`/`$$...$$` math, and
    a ```swift code block all render correctly; code containing `$` is not
    treated as math.

## M5 - Link Handling + Window Dedup (D-7, D-12, D-8)

- [DONE] M5.1 `DocumentKey`: canonicalize URL (resolve symlinks, standardize,
  case-normalize). Unit-tested.
- [DONE] M5.2 `DocumentWindowRegistry` (main-actor): DocumentKey -> controller;
  register on open, deregister on close.
- [DONE] M5.3 `openDocument(url:)` flow funneling Open panel, Finder Open With,
  dock drop, CLI args, and internal link clicks; existing window comes forward.
- [DONE] M5.4 `LinkClassifier` (pure fn) + `WebViewCoordinator`
  `decidePolicyFor`: fragment -> JS scroll; local .md -> openDocument;
  other local file -> NSWorkspace.open; http/mailto -> NSWorkspace.open.
  Unit-tested against the D-7 table.
- [DONE] M5.5 Bridge (`WKScriptMessageHandler` "bridge") with nonce validation;
  wire `openLink`, `domReady`, `scrollPosition`.
  - Acceptance: every D-7 row behaves correctly; opening an already-open doc
    raises its window instead of duplicating.

## M6 - Live Reload (D-10)

- [DONE] M6.1 `FileWatcher`: DispatchSource vnode source for
  write/rename/delete/extend/attrib.
- [DONE] M6.2 Atomic-save handling: on rename/delete, watch parent dir and
  re-arm the file watch when the path reappears.
- [DONE] M6.3 Debounce (~150 ms) and coalesce burst writes.
- [DONE] M6.4 On change: capture scrollY via bridge, re-render, reload, then
  `restoreScroll(y)` on domReady. Deleted-file grace period + banner.
  - Acceptance: editing/saving the file (incl. atomic save) refreshes the view
    within ~150 ms with scroll position preserved.

## M7 - Code Block Controls (D-13)

- [DONE] M7.1 Per-`<pre>` hover toolbar (copy + toggle icons); always visible
  where hover is unavailable. Excludes mermaid blocks.
- [DONE] M7.2 Copy via native bridge (`copyCode` -> NSPasteboard) with success
  flash.
- [DONE] M7.3 Scroll mode (overflow-x auto, native horizontal scroll) and
  shrink mode (font-size scaling to fit, floor ~7px then fall back to scroll).
- [DONE] M7.4 Per-block mode map keyed by index+text-hash, re-applied after
  reload; default mode from Settings; `ResizeObserver` recomputes shrink blocks
  on resize.
  - Acceptance: a too-wide code block can copy, toggle scroll<->shrink per
    instance, survives reload, and re-fits on window resize.

## M8 - Zoom (D-9.3)

- [DONE] M8.1 Menu commands: Increase (Cmd-=), Decrease (Cmd--), Actual Size
  (Cmd-0); map to bridge `setZoom`.
- [DONE] M8.2 Zoom scales `font-size` on `html` (not pageZoom) so layout
  reflows and shrink-fit recomputes; clamp 0.5-3.0 in 10% steps.
- [DONE] M8.3 `ZoomMemory` store (UserDefaults keyed by DocumentKey, LRU cap
  ~256): persist on change, restore on open, fall back to Settings default.
  - Acceptance: Cmd-+/-/0 reflow correctly; reopening a doc restores its last
    zoom across app launches.

## M9 - Settings (D-14)

- [DONE] M9.1 `SettingsStore` (ObservableObject over UserDefaults), published.
- [DONE] M9.2 `SettingsView` SwiftUI Settings scene (Cmd-,): body font, code
  font, default size, default code mode, theme, "Allow unsafe HTML".
- [DONE] M9.3 Live propagation to all open windows via `applySettings`.
- [DONE] M9.4 Live preview pane rendering a sample document.
  - Acceptance: changing any setting updates all open windows immediately.

## M10 - Plain Text + Security + Polish (D-5.7, D-11, D-15, D-21)

- [DONE] M10.1 `.txt` path: render as a single preformatted block (code font,
  whitespace preserved), no markdown/highlight/math/mermaid; copy-all + View
  menu Soft Wrap toggle. Renderer dispatches on extension.
- [DONE] M10.2 GitHub-style allowlist sanitizer (keep ins/u/kbd/sub/sup/del...,
  strip script/iframe/on*=/javascript:); "Allow unsafe HTML" opt-in bypass.
  Verify `<ins>`/`<u>` underline works with the toggle OFF.
- [DONE] M10.3 Edge cases (D-15): large files off-main-thread + loading state;
  invalid UTF-8 lossy decode + banner; appearance change re-theme; file
  replaced/permissions lost banner; anchor-not-found toast.
- [DONE] M10.4 Error banners; `Info.plist` document type UTIs
  (md/markdown viewer role + plain-text) so app appears in "Open With".
  NOTE: Dark mode is deferred as a future enhancement. Basic light/dark CSS
  variables are already in theme.css but no polish pass has been done.
- [NEW] M10.5 Developer-ID sign, notarize, staple.
  - Acceptance: .txt renders preformatted; underline safe by default;
    notarized build installs and opens md/txt from Finder.

---

## Future Enhancements

- Dark mode polish pass. Basic `@media (prefers-color-scheme: dark)` CSS variables
  are in place in theme.css, but no systematic verification or visual polish has
  been done. Mermaid diagrams (BUG-1) will also need re-testing once that bug is
  resolved.

---

## Known Bugs

- [NEW] BUG-2 Pinch-to-zoom on WKWebView does not give live (during-gesture) visual
  feedback on macOS 15. The zoom value is stored correctly and appears after the next
  user interaction (click/scroll), but the view does not update while pinching.

  Three approaches were tried, all failed:

  1. webView.pageZoom during .changed — pageZoom is processed asynchronously by the
     WebKit GPU process (com.apple.WebKit.GPU). Setting it sends an IPC message; the
     new frame does not arrive until after the gesture is complete.

  2. evaluateJavaScript("document.documentElement.style.transform=...") during .changed
     — also async IPC to the WebContent process. WebKit appears to suspend rendering
     updates while a gesture recognizer on the WKWebView itself is active.

  3. CALayer transform on a plain NSView container (wantsLayer=true) wrapping the
     WKWebView, with the gesture recognizer on the container instead of the WebView.
     The expectation was that CA would composite the WKWebView's IOSurface with the
     transform immediately on the display link tick. This also did not produce live
     feedback; the display update was still deferred until a subsequent user action.

  The gesture recognizer fires correctly (.began/.changed/.ended all fire) and the
  final value is applied correctly. Only the live intermediate frames are missing.

  Possible future investigation paths:
  - NSScrollView with allowsMagnification=true as the outer view; let the scroll
    view handle the pinch gesture natively (NSScrollView.magnification is synchronous).
    Challenge: WKWebView has its own internal NSScrollView which may conflict.
  - Look for a WKWebView-specific API to suspend/resume rendering or to request a
    synchronous composite. Check whether WKWebView.allowsMagnification exists in
    future WebKit versions.
  - Use a private/undocumented WKWebView API to intercept the existing magnification
    gesture handler that WebKit installs internally.
  - File a DTS or Feedback Assistant ticket with Apple — this appears to be a
    platform-level restriction with no documented workaround.

- [NEW] BUG-1 Mermaid diagrams render with black node fills and invisible lines.
  Root cause: BeautifulMermaid `DiagramTheme.mixed()` silently returns black on
  AppKit when NSColor colour-space conversion fails. Workaround of explicit
  surface/line colours partially improves appearance but diagram quality is
  still below acceptable. Investigate alternate rendering path or wait for a
  BeautifulMermaid fix. All three diagram types affected (flow, sequence, ER).

---

## Cross-cutting / Definition of Done
- [NEW] X.1 All unit test suites green (Renderer, DocumentKey, LinkClassifier,
  HeadingSlugger).
- [NEW] X.2 Manual smoke checklist (D-17) passes: live reload, window dedup,
  zoom persistence, per-block toggle/copy, settings live-update, external link
  to browser, internal anchor scroll.
- [NEW] X.3 No remote network fetch except remote images (all libs bundled).
