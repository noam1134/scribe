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
    /// UI tests reach Settings without the iPhone screens placing the button
    /// (they do so at merge time): `-settingsButton` puts the real button
    /// over the app, `-showSettings` opens Settings at launch (screenshots).
    /// `-uiTesting` runs only.
    func settingsTestEntry() -> some View {
        modifier(SettingsTestEntry())
    }
}

private struct SettingsTestEntry: ViewModifier {
    @State private var showsAtLaunch = SettingsDemo.showsSettingsAtLaunch

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if SettingsDemo.showsSettingsButton {
                    SettingsButton()
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .padding(.leading, 16)
                }
            }
            .sheet(isPresented: $showsAtLaunch) { SettingsSheet() }
    }
}
#endif
