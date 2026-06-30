import SwiftUI
import AppKit
import Combine

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

            // Find (Edit menu). Standard macOS Cmd-F / Cmd-G / Cmd-Shift-G.
            CommandGroup(after: .textEditing) {
                Section {
                    Button("Find…") {
                        NSApp.sendAction(#selector(AppDelegate.performFind(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Button("Find Next") {
                        NSApp.sendAction(#selector(AppDelegate.performFindNext(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("g", modifiers: .command)

                    Button("Find Previous") {
                        NSApp.sendAction(#selector(AppDelegate.performFindPrevious(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                }
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

                // Compare/version commands share one section. The git-only items are
                // disabled when the focused document is not inside a git repository.
                CompareCommands()
            }
        }
    }
}

// MARK: - Compare / version commands

/// The "Compare" family of menu items, grouped in one section. "Compare with
/// File…" works for any open document; the two git items operate on the version
/// committed before the working copy and are disabled when the focused document
/// is not inside a git repository.
private struct CompareCommands: View {
    @ObservedObject private var menuState = MenuCommandState.shared

    var body: some View {
        Section {
            Button("Compare with File…") {
                NSApp.sendAction(#selector(AppDelegate.compareDocumentWithFile(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!menuState.hasDocument)

            Button("Compare with Previous Version") {
                NSApp.sendAction(#selector(AppDelegate.debugCompareLiveWithFirstHistorical(_:)), to: nil, from: nil)
            }
            .disabled(!menuState.focusedDocumentInGit)

            Button("View Previous Version") {
                NSApp.sendAction(#selector(AppDelegate.debugViewFirstHistoricalVersion(_:)), to: nil, from: nil)
            }
            .disabled(!menuState.focusedDocumentInGit)
        }
    }
}

/// Observable enabled-state for document-scoped menu commands. AppKit owns the
/// document windows, so SwiftUI's `@FocusedValue` can't see them; instead we
/// recompute from the focused window controller whenever key-window focus
/// changes (and when a window's git detection finishes — see
/// DocumentWindowController).
@MainActor
final class MenuCommandState: ObservableObject {
    static let shared = MenuCommandState()

    @Published private(set) var hasDocument = false
    @Published private(set) var focusedDocumentInGit = false

    private init() {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    /// Recompute from the currently focused document window.
    func refresh() {
        let controller = DocumentWindowRegistry.shared.focusedController()
        hasDocument = controller != nil
        focusedDocumentInGit = controller?.isInGitRepository ?? false
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
