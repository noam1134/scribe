import SwiftUI

/// The way into Settings on the iPhone (spec §9.2): a gear that presents
/// `SettingsView` in a sheet. Self-contained — it brings its own sheet and
/// reads the `StoreLoader` from the environment — so any toolbar can hold it.
struct SettingsButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("Settings", systemImage: "gear") { isPresented = true }
            .accessibilityIdentifier("settingsButton")
            .sheet(isPresented: $isPresented) { SettingsSheet() }
    }
}

/// Settings in its own navigation stack, closed with the toolbar's X.
/// Changes apply as they're made; there is nothing to save.
struct SettingsSheet: View {
    @Environment(StoreLoader.self) private var loader
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView(loader: loader)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                            .accessibilityIdentifier("closeSettings")
                    }
                }
        }
    }
}

#if DEBUG
extension View {
    /// `-uiTesting -showSettings` opens Settings at launch, for screenshots.
    func settingsAtLaunchForScreenshots() -> some View {
        modifier(SettingsAtLaunch())
    }
}

private struct SettingsAtLaunch: ViewModifier {
    @State private var isPresented = SettingsDemo.showsSettingsAtLaunch

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) { SettingsSheet() }
    }
}
#endif
