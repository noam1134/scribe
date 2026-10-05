import ScribeCore
import SwiftUI

/// Settings on iPhone and Mac (spec §16 Phase 6): iCloud sync, this
/// device's notifications, the Mac's quick-add shortcut, export and the
/// version. The iPhone shows it in a sheet (`SettingsButton`), the Mac in
/// its Settings window (`MacSettingsScene`).
struct SettingsView: View {
    let loader: StoreLoader

    @State private var exportFailure: String?

    var body: some View {
        Form {
            SyncSection()
            NotificationsSection()
            #if os(macOS)
            QuickAddHotkeySection()
            #endif
            ExportSection(loader: loader, failure: $exportFailure)
            AboutSection()
        }
        .formStyle(.grouped)
        .alert("Couldn’t Export", isPresented: Binding(
            get: { exportFailure != nil },
            set: { if !$0 { exportFailure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportFailure ?? "")
        }
    }
}

// MARK: iCloud

/// Spec §13: "Sync off — sign in to iCloud" with how to fix it, "Last
/// synced …", and the last failure.
private struct SyncSection: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let monitor = SyncMonitor.shared
        Section("iCloud") {
            // Keeps "just now" and "at 09:14" honest while Settings stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let text = SyncStatusText(account: monitor.account, log: monitor.log, now: context.date, device: .current)
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.headline)
                            .accessibilityIdentifier("syncHeadline")
                        if let detail = text.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("syncDetail")
                        }
                        if let lastSynced = text.lastSynced {
                            Text(lastSynced)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("lastSynced")
                        }
                        if let problem = text.problem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("syncProblem")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: text.symbol.systemImage)
                        .foregroundStyle(text.symbol.tint)
                }
            }
        }
        .onAppear {
            monitor.start()
            monitor.refreshAccount()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system's settings, maybe signed in.
            if phase == .active { monitor.refreshAccount() }
        }
    }
}

private extension SyncStatusText.Symbol {
    var systemImage: String {
        switch self {
        case .on: "checkmark.icloud"
        case .off: "icloud.slash"
        case .warning: "exclamationmark.icloud"
        case .checking: "icloud"
        }
    }

    var tint: Color {
        switch self {
        case .on: .green
        case .off, .checking: .secondary
        case .warning: .orange
        }
    }
}

// MARK: Notifications

/// Spec §11: per-device switch and morning summary; §13: how to allow them
/// again when the system blocks them. Bound to `NotificationCoordinator`,
/// which saves each change and re-plans.
private struct NotificationsSection: View {
    @Environment(\.openURL) private var openURL

    private var permission: NotificationPermission {
        #if DEBUG
        if let demo = SettingsDemo.permission { return demo }
        #endif
        return NotificationCoordinator.shared.permission
    }

    var body: some View {
        @Bindable var notifications = NotificationCoordinator.shared
        let text = NotificationSectionText(settings: notifications.settings, permission: permission, device: .current)
        Section {
            Toggle(text.switchTitle, isOn: Binding(
                get: { notifications.settings.isEnabled },
                set: { isOn in
                    notifications.settings.isEnabled = isOn
                    // The prompt comes from the switch (the Mac starts off and never asks otherwise).
                    if isOn { Task { await notifications.requestPermission() } }
                }
            ))
            .accessibilityIdentifier("notificationsToggle")

            if text.showsPermissionProblem {
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text.permissionProblem)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("permissionProblem")
                        Button(text.openSettingsTitle) {
                            if let url = NotificationCoordinator.systemSettingsURL { openURL(url) }
                        }
                        .accessibilityIdentifier("openNotificationSettings")
                    }
                } icon: {
                    Image(systemName: "bell.slash").foregroundStyle(.orange)
                }
            }

            Toggle("Morning Summary", isOn: $notifications.settings.morningSummaryEnabled)
                .disabled(!text.summaryToggleEnabled)
                .accessibilityIdentifier("morningSummaryToggle")

            if text.showsSummaryTime {
                DatePicker("Summary Time", selection: Binding(
                    get: { notifications.settings.summaryTime(calendar: .autoupdatingCurrent) },
                    set: { notifications.settings.setSummaryTime($0, calendar: .autoupdatingCurrent) }
                ), displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("summaryTimePicker")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(text.footer)
        }
    }
}

// MARK: Export

private struct ExportSection: View {
    let loader: StoreLoader
    @Binding var failure: String?

    #if os(macOS)
    @State private var export: JSONExport?
    @State private var isExporting = false
    #endif

    private var store: (any ItemStore)? {
        if case .ready(let store) = loader.state { return store }
        return nil
    }

    var body: some View {
        Section {
            Button(action: run) {
                Label(exportTitle, systemImage: "square.and.arrow.up")
            }
            .disabled(store == nil)
            .accessibilityIdentifier("exportButton")
        } header: {
            Text("Export")
        } footer: {
            Text("Every category and item, done ones included, as one JSON file — a backup you can keep anywhere.")
        }
        #if os(macOS)
        .fileExporter(isPresented: $isExporting, item: export, contentTypes: [.json], defaultFilename: SettingsExport.filenameWithoutExtension) { result in
            if case .failure(let error) = result { failure = error.localizedDescription }
            export = nil
        } onCancellation: {
            export = nil
        }
        #endif
    }

    private var exportTitle: String {
        #if os(macOS)
        "Export All as JSON…"
        #else
        "Export All as JSON"
        #endif
    }

    private func run() {
        guard let store else { return }
        do {
            #if os(iOS)
            try ShareSheet.present(try SettingsExport.writeFile(from: store))
            #else
            export = JSONExport(data: try store.exportJSON())
            isExporting = true
            #endif
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: About

private struct AboutSection: View {
    var body: some View {
        let info = Bundle.main.infoDictionary
        Section("About") {
            LabeledContent("Version", value: AppVersion.text(
                shortVersion: info?["CFBundleShortVersionString"] as? String,
                build: info?["CFBundleVersion"] as? String
            ))
            .accessibilityIdentifier("versionRow")
        }
    }
}
