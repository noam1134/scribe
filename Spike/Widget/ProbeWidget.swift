import AppIntents
import SwiftUI
import WidgetKit

/// Phase 0 only.
struct ProbeEntry: TimelineEntry {
    let date: Date
    let summary: ProbeSummary
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: .now, summary: ProbeSummary(total: 0, latest: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(ProbeEntry(date: .now, summary: ProbeStore.summary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        let entry = ProbeEntry(date: .now, summary: ProbeStore.summary())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Probe notes: \(entry.summary.total)").font(.headline)
                Spacer()
                Button(intent: AddProbeNoteIntent(source: "widget")) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(entry.summary.latest.enumerated()), id: \.offset) { _, text in
                Text(text).font(.caption2).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("Rendered \(entry.date.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProbeWidget", provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
        }
        .configurationDisplayName("Scribe Sync Probe")
        .supportedFamilies([.systemMedium])
    }
}

struct ProbeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.noamchuri.scribe.probe-control") {
            ControlWidgetButton(action: AddProbeNoteIntent(source: "control")) {
                Label("Add Probe", systemImage: "plus.circle")
            }
        }
        .displayName("Add Probe Note")
    }
}
