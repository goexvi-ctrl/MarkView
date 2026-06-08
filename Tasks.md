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
- [CODED] M10.5 Developer-ID sign, notarize, staple.
  - Notarization deferred: no Developer ID certificate available in this
    environment. Release build compiled (-configuration Release), ad-hoc
    signed, and packaged as ~/Desktop/MarkView-1.0.dmg (6.8 MB).
    First-launch requires right-click > Open to bypass Gatekeeper.
    Full notarization can be done once a Developer ID cert is imported.

---

## Future Enhancements

- Dark mode polish pass. Basic `@media (prefers-color-scheme: dark)` CSS variables
  are in place in theme.css, but no systematic verification or visual polish has
  been done. Mermaid now re-renders on appearance changes via the JS path.

---

## Known Bugs

- [PARTIALLY FIXED] BUG-2 Pinch-to-zoom (magnifying-glass visual scale of current
  layout) is now functional via WKWebView's native magnification (allowsMagnification=true
  + built-in gesture recognizer). This is deliberately separate from the reflow
  "font size" zoom (CSS --zoom variable on html font-size, which affects layout,
  shrink-to-fit code blocks, etc.).

  Menu support under View (added in this session):
  - Zoom In / Zoom Out / Actual Size (drive native magnification; use Cmd+Shift
    equivalents to avoid clashing with font-size commands).
  - Increase Font Size / Decrease Font Size / Actual Font Size (the original
    reflow path via setZoom / JS --zoom; Cmd without Shift).

  Independent resets are provided ("Actual Size" for visual magnification;
  "Actual Font Size" for the reflow zoom). This was chosen over a single combined
  reset.

  Menu zoom (Cmd+/- / 0) was historically tied only to the reflow path (sometimes
  labeled "font size"). Pinch previously did almost nothing useful, or (after an
  earlier mistaken custom gesture implementation) would incorrectly drive the
  reflow zoom, produce selection-dependent snapping, and only have effect for one
  gesture after highlighting text.

  Live (during-gesture) visual feedback for the magnification path may still be
  limited or absent (see original platform notes below); final value applies on
  gesture end. The old experimental attempts (pageZoom, JS transform during
  .changed, CALayer wrapper) are no longer relevant since we now rely on native
  magnification for the visual path.

  (Mermaid diagrams remain broken / non-functional per separate note; not addressed
  in this session.)

  Live (during-gesture) visual feedback for the magnification path may still be
  limited or absent due to WebKit's asynchronous rendering and gesture handling
  (see historical platform notes in prior version of this entry). The final
  magnification value applies on gesture end.

  (Mermaid diagrams remain broken / non-functional per separate note; not addressed
  in this session.)

- [DONE] BUG-1 (was) Mermaid diagrams rendered via BeautifulMermaid (a from-scratch
  reimplementation) produced poor results and only supported a subset of syntax.
  Fixed by restoring client-side rendering with the real vendored mermaid.js
  (as originally specified in Design.md 5.4). Diagrams now use the reference
  engine for full syntax support and high visual fidelity. Theme switches
  re-render diagrams in JS without a full document reload. The BeautifulMermaid
  package is no longer imported or used.

---

## H - Git History & Comparison

Support recalling previous versions of a document when its file lives in a git
repository, plus side-by-side comparison of two versions (rendered Markdown view,
red for removals on the older side, green for additions on the newer side,
with later polish for scroll alignment of unchanged sections).

See the approved implementation plan (session plan.md) for architecture,
phasing (A then B then C), and constraints from Design.md.

- [CODED] H1.1 Add GitClient (Process + /usr/bin/env git, no shell) + GitError.
  Operations needed for a document fileURL: is inside work tree, get toplevel +
  relative path, list history (git log limited, --follow), cat a blob at rev.
  Silent graceful degradation + friendly banner when git missing or file untracked.
- [CODED] H1.2 GitVersion struct (full/short sha, subject, authorDate, ...).
  GitFileHistory (array of versions + working-tree sentinel). Limited fetch +
  "load more".
- [CODED] H1.3 Historical "recall" view: from a live window, load a past revision's
  text as a read-only snapshot (via renderer), show a persistent InfoBanner
  ("Viewing <short> - <subject>") with "Return to current version" action.
  Suspend FileWatcher while viewing history; title augmentation. Return restores
  live disk content + re-arms watcher.
- [CODED] H1.4 "Open this historical revision in a new window" (synthetic identity
  so it does not collide with the live DocumentKey in the registry).
  Keyboard Shift-< / Shift-> (and Arrow / , . equivalents) opens independent
  pure-historical snapshot windows that can coexist with the live viewer for
  the same document. Revision pop-up performs in-place jumps (current behavior
  accepted for H1; selector re-used for H2 version picking).
- [TESTED] H1.5 Manual smoke + error cases for H1 (no git, untracked, huge blob,
  lossy decode of old content, etc.). Debug menu item ("Debug: View First Historical (git)")
  provides immediate test coverage. Key flows (in-place < >, Shift new windows,
  fast-path from live, WT sentinel exit, revision selector, info panel reuse +
  auto-dismiss on revision change, Return-to-current for both normal and pure
  snapshots) exercised via Xcode console logs + debug menu. Updated X.2 checklist.
- [CODED] H2.1 (after H1) GitClient diff support + small unified-diff hunk parser.
  Added `diffHunks(base:target:for:)` (and GitVersion overload) + `GitDiffHunk`
  struct. Parser extracts @@ ranges from `git diff --no-color -U3`. Supports WT
  sentinel (empty sha) on either side. Build verified.
- [CODED] H2.2 Basic side-by-side comparison surface (new window or synthetic diff
  HTML page loaded into the webview) showing two rendered versions side-by-side
  (older left) using the normal MarkdownRenderer pipeline. Header with metadata
  and +/- stats.
  Implemented via debug trigger ("Debug: Compare live vs first historical (git)"):
  fetches texts (content() or live), dual `MarkdownRenderer.render`, builds
  comparison HTML via new `HTMLTemplate.buildComparison` (flex panes, labels,
  stats from hunk count, theme + vendor scripts for rich content inside panes),
  loads via dedicated `loadComparisonHTML`. Native InfoBanner with "Return to
  document" action that exits and reloads. Title updated. Basic (no full picker
  or hunk-driven tinting yet).
- [NEW] H2.3 Red/green visual treatment on the rendered content (hunk/block level
  tints, borders, or markers using new CSS vars in theme.css that respect light/dark;
  leverage existing del/ins where helpful). "Compare with previous" and picker.
- [NEW] H2.4 From compare surface: open either side as a normal (or historical)
  document window; swap sides.
- [NEW] H3.1 (after H2) Scroll sync + prev/next hunk navigation so unchanged
  sections stay roughly side-by-side (hunk-row layout or sampled mapping in JS).
- [NEW] H3.2 Collapse large unchanged context hunks; finer intra-hunk word
  highlights (optional); loading states, accessibility, perf caps, empty states.

---

## Cross-cutting / Definition of Done
- [DONE] X.1 All unit test suites green (Renderer, DocumentKey, LinkClassifier,
  HeadingSlugger).
  - SPM suite (15 tests): DocumentKey, HeadingSlugger, LinkClassifier all pass.
  - Xcode suite: GoldenRendererTests.swift added (16 tests covering cmark-gfm
    output, sanitizer, math pre-processing, plain-text path). Runs as host-app
    bundle test against the full MarkView module.
- [CODED] X.2 Manual smoke checklist (D-17) passes: live reload, window dedup,
  zoom persistence, per-block toggle/copy, settings live-update, external link
  to browser, internal anchor scroll, git history navigation (< > / , . in-place
  from live into history and back; Shift for new independent snapshot windows),
  titlebar revision selector (scrollable NSPopUp with short SHA + commit message
  prefix; direct jump), info panel (ⓘ button: single reusable per window, shows
  full commit message or "Live", auto-dismisses on revision change), Return to
  current banner action (normal exit + special adopt/close logic for pure
  historical snapshots), graceful no-git / untracked cases.
- [DONE] X.3 No remote network fetch except remote images (all libs bundled).
  - All JS/CSS vendored in WebAssets/vendor/. Mermaid rendered in-page via the
    vendored mermaid.js (no CDN). No network calls for any rich content at runtime.
