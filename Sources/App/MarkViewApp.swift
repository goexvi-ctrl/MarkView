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

            // View zoom commands
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Font Size") {
                    zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    zoomReset()
                }
                .keyboardShortcut("0", modifiers: .command)
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
