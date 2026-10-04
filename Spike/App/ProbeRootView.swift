import SwiftData
import SwiftUI

/// Phase 0 only. Shows what this device's store contains and every sync event.
struct ProbeRootView: View {
    let log: SyncEventLog

    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [Row] = []
    @State private var total = 0
    @State private var lastRefresh = Date.now
    @State private var errorText: String?

    struct Row: Identifiable {
        let id: UUID
        let text: String
    }

    private var deviceName: String {
        #if os(iOS)
        "iPhone"
        #else
        "Mac"
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                Section("This device: \(deviceName)") {
                    Button("Add probe note") { add() }
                    Button("Refresh") { refresh() }
                    LabeledContent("Notes in store", value: "\(total)")
                    LabeledContent("Last refresh", value: lastRefresh.formatted(date: .omitted, time: .standard))
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
                Section("Latest 20 notes") {
                    ForEach(rows) { Text($0.text).font(.callout) }
                }
                Section("Sync events, newest first") {
                    ForEach(log.entries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.at.formatted(date: .omitted, time: .standard)).monospacedDigit()
                            Text(entry.text)
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Scribe Sync Probe")
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onChange(of: log.remoteChangeCount) { refresh() }
    }

    private func add() {
        do {
            try ProbeStore.add(source: "\(deviceName) app button")
            refresh()
        } catch {
            errorText = "Add failed: \(error)"
        }
    }

    private func refresh() {
        let context = ModelContext(ProbeStore.container)
        var latest = FetchDescriptor<ProbeNote>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        latest.fetchLimit = 20
        do {
            total = try context.fetchCount(FetchDescriptor<ProbeNote>())
            rows = try context.fetch(latest).map { Row(id: $0.id, text: $0.text) }
            lastRefresh = .now
            errorText = nil
        } catch {
            errorText = "Refresh failed: \(error)"
        }
    }
}
