import SwiftUI

// Minimal iPad settings sheet backed by the shared SettingsStore.
// Font size and code mode propagate live via applySettings; the unsafe-HTML
// toggle triggers a re-render through PadWebView's updateUIView.
struct PadSettingsView: View {

    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    Stepper(
                        "Base font size: \(settings.defaultFontSize) pt",
                        value: $settings.defaultFontSize, in: 9...30
                    )
                }
                Section("Code Blocks") {
                    Picker("Wide code blocks", selection: $settings.defaultCodeMode) {
                        Text("Scroll").tag(CodeViewMode.scroll)
                        Text("Shrink to fit").tag(CodeViewMode.shrink)
                    }
                }
                Section("Appearance") {
                    Picker("Theme", selection: $settings.appTheme) {
                        Text("System").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }
                }
                Section {
                    Toggle("Allow unsafe HTML", isOn: $settings.allowUnsafeHTML)
                } footer: {
                    Text("Renders raw HTML in documents without sanitizing. Only enable for trusted files.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
