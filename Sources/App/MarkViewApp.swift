import SwiftUI

@main
struct MarkViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            // About panel with build timestamp
            CommandGroup(replacing: .appInfo) {
                Button("About MarkView") {
                    appDelegate.showAboutPanel()
                }
            }

            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appDelegate.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                OpenRecentMenu()
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Markdown Cheat Sheet") {
                    appDelegate.openCheatSheet()
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            // Visual zoom (magnifying glass / pinch-to-zoom equivalent).
            // Scales the current layout visually without reflowing text or affecting
            // shrink-to-fit code blocks.
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    visualZoomIn()
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])

                Button("Zoom Out") {
                    visualZoomOut()
                }
                .keyboardShortcut("-", modifiers: [.command, .shift])

                Button("Actual Size") {
                    visualZoomReset()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }

            // Font size / reflow zoom.
            // Changes the effective font size (via --zoom CSS), causing layout reflow
            // and affecting code block shrink-to-fit behavior.
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Font Size") {
                    zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Font Size") {
                    zoomReset()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            // Reload (useful for debugging with Web Inspector attached,
            // since closing the window would close the inspector too).
            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    NSApp.sendAction(#selector(AppDelegate.reloadDocument(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                // Temporary H1 debug hook. Opens the first prior git version of the
                // current document (if any) using the new historical recall path.
                Button("Debug: View First Historical (git)") {
                    NSApp.sendAction(#selector(AppDelegate.debugViewFirstHistoricalVersion(_:)), to: nil, from: nil)
                }

                // H2 debug: basic side-by-side comparison surface (live vs first commit).
                // Uses GitClient.diffHunks + dual MarkdownRenderer + synthetic comparison HTML.
                Button("Debug: Compare live vs first historical (git)") {
                    NSApp.sendAction(#selector(AppDelegate.debugCompareLiveWithFirstHistorical(_:)), to: nil, from: nil)
                }
            }
        }
    }
}

// MARK: - Open Recent submenu

private struct OpenRecentMenu: View {
    @ObservedObject private var recent = RecentDocumentsStore.shared

    var body: some View {
        Menu("Open Recent") {
            if recent.urls.isEmpty {
                Text("No Recent Documents")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent.urls, id: \.absoluteString) { url in
                    RecentDocumentItem(url: url)
                }
                Divider()
                Button("Clear Menu") {
                    recent.clear()
                }
            }
        }
    }
}

private struct RecentDocumentItem: View {
    let url: URL

    // Show parent dir when files have the same name as another recent file
    // (handled simply by always showing just the filename here;
    //  full path is shown in the tooltip)
    var body: some View {
        Button(url.lastPathComponent) {
            Task { @MainActor in
                DocumentWindowRegistry.shared.openDocument(url: url)
            }
        }
        .help(url.path)
    }
}
