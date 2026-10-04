import SwiftUI
import WidgetKit

@main
struct ScribeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

/// Keeps the extension buildable until the real agenda widget (Phase 4).
struct PlaceholderWidget: Widget {
    struct Entry: TimelineEntry {
        let date: Date
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .never))
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Placeholder", provider: Provider()) { _ in
            Text("Scribe")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Scribe")
        .supportedFamilies([.systemSmall])
    }
}
