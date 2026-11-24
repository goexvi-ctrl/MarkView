# Displaying Markdown in MarkView - Developer Guide

This guide is for developers of *other* applications (or tools) that want to
show a Markdown document to the user through MarkView. It covers both
platforms; most of it concerns the iPad app, which has a URL scheme designed
for programmatic handoff.

MarkView is a viewer. It renders GitHub Flavored Markdown (tables, task
lists, strikethrough, footnotes, autolinks) plus KaTeX math, Mermaid
diagrams, and syntax-highlighted code blocks. It never edits or writes back
to your file. Plain-text files (`.txt`) are shown preformatted without
Markdown processing.

## macOS

Anything that can open a file with a specific application works:

```sh
open -a MarkView /path/to/README.md
```

or from another app:

```swift
NSWorkspace.shared.open(
    [URL(fileURLWithPath: "/path/to/README.md")],
    withApplicationAt: markViewAppURL,   // or open(_:) and let LaunchServices pick
    configuration: NSWorkspace.OpenConfiguration()
)
```

MarkView also accepts file paths as command-line arguments. Each document
gets its own window; opening an already-open file raises its existing window.
The file stays live: if you rewrite it, the view refreshes automatically
(atomic saves included), which makes it a good progress/preview surface for
tools that keep regenerating a document.

## iPad (MarkViewPad)

On iPadOS every document MarkView shows appears as a tab in its single
window. All of the routes below funnel into those tabs, and reopening a file
that is already open selects its existing tab instead of duplicating it.

There are two fundamentally different ways to hand a document over:

1. **File-based handoff** (share sheet, Files app, drag and drop) - works
   from any app, requires user interaction, no size limit.
2. **The `markview://` URL scheme** - programmatic, launches MarkView if
   needed, but content must either fit in a URL or be a file MarkView's
   sandbox can read.

### 1. File-based handoff

MarkView declares the `net.daringfireball.markdown` and `public.plain-text`
document types (viewer role, opens documents in place), so iOS offers it
wherever a Markdown or text file is shared:

- **Share sheet**: write your markdown to a file and present the standard
  activity controller. The user picks MarkView from the sheet.

  ```swift
  let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Report.md")
  try markdownText.write(to: url, atomically: true, encoding: .utf8)
  present(UIActivityViewController(activityItems: [url],
                                   applicationActivities: nil),
          animated: true)
  ```

- **"Open in..." menu**: `UIDocumentInteractionController(url:)` +
  `presentOpenInMenu(from:in:animated:)` for a dedicated open-in flow.

- **Files app**: save into any Files-visible location (your file-provider
  domain, iCloud Drive, On My iPad). The user taps the file and MarkView
  opens it in place - later opens re-read the current content.

- **Drag and drop**: expose the markdown as a draggable `NSItemProvider`
  file representation; the user drops it on MarkView in Split View.

The file extension (`.md`, `.markdown`, `.txt`) or UTI is what routes the
file to MarkView - a markdown string typed as plain text in a share sheet
will not offer MarkView; share a *file*.

### 2. The markview:// URL scheme

For programmatic handoff, MarkView registers the `markview` scheme. Opening
one of these URLs launches MarkView if it is not running and shows the
content as a tab:

```
markview://view?text=<percent-encoded UTF-8 markdown>[&name=Title.md]
markview://view?b64=<base64 UTF-8 markdown>[&name=Title.md]
markview://view?file=<absolute path or file:// URL>[&deleteonclose=1]
```

From Swift:

```swift
var components = URLComponents()
components.scheme = "markview"
components.host = "view"
components.queryItems = [
    URLQueryItem(name: "text", value: markdownString),  // encoded for you
    URLQueryItem(name: "name", value: "Build Report.md"),
]
if let url = components.url {
    UIApplication.shared.open(url)   // async; check completion for success
}
```

Parameter reference:

| Parameter | Meaning |
| --- | --- |
| `text` | Percent-encoded UTF-8 markdown, shown directly. |
| `b64` | Base64 (standard or URL-safe alphabet, padding optional) UTF-8 markdown. Use this when percent-encoding is awkward, e.g. from shell scripts. |
| `file` | Absolute filesystem path (percent-encoded) or a `file://` URL to open. |
| `name` | Optional display name for the tab (default `Untitled.md`). A `.txt` name renders as plain text instead of Markdown. Ignored for `file=`, which uses the file's own name. |
| `deleteonclose` | Only with `file=`. `1`, `true`, or `yes`: the file is temporary; MarkView deletes it when the user closes the tab. |

Exactly one of `text`, `b64`, or `file` is required (`file` wins if several
are present). Errors - unknown action, undecodable base64, unreadable file -
are shown to the user as a transient banner in the MarkView window.

**Updating content in place**: sending inline content (`text`/`b64`) with
the same `name` again replaces that tab's content rather than opening a new
tab. A producing app can therefore keep one "live" tab up to date by
re-sending the URL. File-backed tabs are deduplicated by path the same way,
and (iPad) a file-backed tab watches its file: rewrite the file and the tab
shows the new contents, with no URL needed (opening the same `file=` again
also re-reads it).

**Size limits**: inline content travels in the URL, which is practically
limited to a few tens of kilobytes. Beyond that, hand over a file.

**Sandbox reality for `file=`**: iOS apps cannot read each other's private
containers. `file=` only works for locations MarkView itself can read:

- MarkView's own Documents folder (visible in Files as On My iPad >
  MarkView) - anything you can get written there;
- the shared app-group container `group.com.kryslix.markview`, which
  MarkView is entitled to (see below);
- development/testing contexts (see below).

For arbitrary files from your own sandbox, use the share sheet instead - the
system grants MarkView access as part of the handoff.

**Handoff via the app group**: if your app is signed by the same team and
declares the `group.com.kryslix.markview` app group in its entitlements, you
can write the file into the shared container and point MarkView at it:

```swift
let container = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.com.kryslix.markview")!
let fileURL = container.appendingPathComponent("Report.md")
try markdownText.write(to: fileURL, atomically: true, encoding: .utf8)

var components = URLComponents()
components.scheme = "markview"
components.host = "view"
components.queryItems = [
    URLQueryItem(name: "file", value: fileURL.path),
    URLQueryItem(name: "deleteonclose", value: "1"),  // optional cleanup
]
UIApplication.shared.open(components.url!)
```

This is the fully programmatic no-user-interaction-but-one-confirmation-free
route for same-team apps; combine with `deleteonclose=1` so the container
does not accumulate handoff files.

### The delete-on-close flag

`deleteonclose=1` is for handoff files that have no life outside the viewer:
a report generated just to be read once, a scratch render of something
assembled on the fly. Semantics:

- The file is deleted when the user closes that tab (the X on the tab chip).
- Deletion is best-effort. If the app terminates with the tab still open,
  the file is *not* deleted - keep such files in a location that gets
  cleaned up anyway (a temporary or caches directory) rather than relying on
  MarkView as the only cleanup.
- If the same file is opened again while its tab is already open, the tab is
  reused and the flag sticks once any opener has set it.
- The flag never applies to inline (`text=`/`b64=`) content and is never
  applied to files opened by the user through Files or the picker.

### Testing your integration in the simulator

```sh
# Inline text (note: percent-encode the markdown)
xcrun simctl openurl booted "markview://view?text=%23%20Hello&name=Test.md"

# A file inside MarkView's container, deleted when the tab closes
CONT=$(xcrun simctl get_app_container booted com.markview.MarkViewPad data)
cp report.md "$CONT/Documents/report.md"
xcrun simctl openurl booted "markview://view?file=$CONT/Documents/report.md&deleteonclose=1"
```

The first `simctl openurl` per install shows an "Open in MarkView?"
confirmation on the simulator - that prompt comes from iOS, not MarkView,
and does not appear when a real app calls `UIApplication.open`.

## Behavior reference (both platforms)

- Rendering: cmark-gfm (the parser GitHub uses) with tables, strikethrough,
  autolink, tasklist, tagfilter, and footnotes; KaTeX for `$...$` and
  `$$...$$`; Mermaid for ```` ```mermaid ```` fences; highlight.js for
  fenced code.
- Raw HTML in documents is sanitized with a GitHub-style allowlist unless
  the user has enabled "Allow unsafe HTML" in settings.
- Relative image paths resolve against the document's directory. On iPad
  this is subject to sandboxing: a document opened in place from another
  app's container cannot load sibling files.
- MarkView never modifies a displayed document (the only exception being an
  explicit `deleteonclose` request).
