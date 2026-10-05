import AppIntents
import ScribeCore
import SwiftUI
import WidgetKit

/// Lays out one entry for the widget's family (spec §10.1).
struct AgendaWidgetView: View {
    let entry: WidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
            .widgetURL(DeepLink.upcoming.url)
    }

    @ViewBuilder private var content: some View {
        switch entry.content {
        case .agenda(let agenda):
            switch family {
            case .systemSmall:
                SmallAgendaView(entry: entry, agenda: agenda)
            case .systemLarge:
                ListAgendaView(entry: entry, agenda: agenda, lines: 14)
            #if os(iOS)
            case .accessoryRectangular:
                RectangularAgendaView(entry: entry, agenda: agenda)
            case .accessoryCircular:
                CircularAgendaView(agenda: agenda)
            #endif
            default:
                ListAgendaView(entry: entry, agenda: agenda, lines: 5)
            }
        case .categoryMissing:
            MessageView(title: "Category deleted", detail: "Edit the widget to choose another.")
        case .storeUnavailable:
            MessageView(title: "Can’t open your notes", detail: "Open Scribe to try again.")
        }
    }
}

// MARK: Home screen and desktop

/// Medium and large: header, day sections, "+N more".
private struct ListAgendaView: View {
    let entry: WidgetEntry
    let agenda: WidgetAgenda
    /// Section headers and rows that fit under the header.
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(entry: entry, add: .link)
            if agenda.isEmpty {
                EmptyAgendaText()
            } else {
                let page = agenda.fitting(lines: lines)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(page.sections) { section in
                        SectionTitle(section: section)
                        ForEach(section.rows) { AgendaRow(row: $0, linksToItem: true) }
                    }
                    if page.hiddenCount > 0 { MoreText(count: page.hiddenCount) }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Small: today's count, then the next three items.
private struct SmallAgendaView: View {
    let entry: WidgetEntry
    let agenda: WidgetAgenda

    private var overdueCount: Int { agenda.sections.first { $0.isOverdue }?.rows.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(entry: entry, add: .intent)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(agenda.todayCount, format: .number)
                    .font(.title2.bold())
                Text("today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if overdueCount > 0 {
                    Text("· \(overdueCount) overdue")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            let first = agenda.firstRows(3)
            ForEach(first.rows) { AgendaRow(row: $0, linksToItem: false) }
            if agenda.isEmpty {
                EmptyAgendaText()
            }
            Spacer(minLength: 0)
        }
    }
}

private struct WidgetHeader: View {
    enum AddButton {
        /// `scribe://add` — medium and large.
        case link
        /// Small widgets can't hold links; an intent opens the composer.
        case intent
    }

    let entry: WidgetEntry
    let add: AddButton

    var body: some View {
        HStack(spacing: 6) {
            ScopeTitle(category: entry.category)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            if let stale = entry.staleLabel {
                Text(stale)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            addButton
        }
    }

    private var plus: some View {
        Image(systemName: "plus.circle.fill")
            .font(.title3)
            .foregroundStyle(entry.category?.color ?? .accentColor)
            .widgetAccentable()
            .accessibilityLabel("Add")
    }

    @ViewBuilder private var addButton: some View {
        switch add {
        case .link:
            Link(destination: DeepLink.add(categoryID: entry.category?.id).url) { plus }
        case .intent:
            Button(intent: OpenQuickAddIntent(category: entry.category.map(CategoryEntity.init))) { plus }
                .buttonStyle(.plain)
        }
    }
}

/// "Upcoming", or the configured category with its color dot.
private struct ScopeTitle: View {
    let category: CategorySnapshot?

    var body: some View {
        if let category {
            HStack(spacing: 4) {
                Circle()
                    .fill(category.color)
                    .frame(width: 7, height: 7)
                    .widgetAccentable()
                Text(category.displayName)
                    .lineLimit(1)
            }
        } else {
            Text("Upcoming")
                .widgetAccentable()
        }
    }
}

private struct SectionTitle: View {
    let section: WidgetSection

    var body: some View {
        Text(section.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(section.isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .padding(.top, 2)
    }
}

/// Checkbox (tasks) or note glyph (memos), title in its own direction
/// (spec §9.4), and the time — red once a task is late.
private struct AgendaRow: View {
    let row: WidgetRow
    /// Small widgets take one tap target only, so their rows can't link.
    let linksToItem: Bool

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: 6) {
            marker
            if linksToItem {
                Link(destination: DeepLink.item(row.id).url) { label }
            } else {
                label
            }
        }
        .font(.footnote)
    }

    private var label: some View {
        HStack(spacing: 4) {
            Text(row.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutDirection(of: row.title)
            if let detail = row.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(row.isLate ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
    }

    @ViewBuilder private var marker: some View {
        switch row.kind {
        case .task:
            Button(intent: CompleteTaskIntent(itemID: row.id)) {
                Image(systemName: "circle")
                    .foregroundStyle(checkboxColor)
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark done")
        case .memo:
            Image(systemName: "note.text")
                .foregroundStyle(.tertiary)
        }
    }

    /// Category colors yield to the system tint outside full color (spec §10.1).
    private var checkboxColor: Color {
        renderingMode == .fullColor ? (row.category?.color ?? .accentColor) : .primary
    }
}

private struct MoreText: View {
    let count: Int

    var body: some View {
        Text("+\(count) more")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct EmptyAgendaText: View {
    var body: some View {
        Text("Nothing in the next 7 days")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MessageView: View {
    let title: String
    let detail: String

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(family == .systemSmall || isAccessory ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            if !isAccessory {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isAccessory: Bool {
        #if os(iOS)
        family == .accessoryRectangular || family == .accessoryCircular
        #else
        false
        #endif
    }
}

// MARK: Lock screen

#if os(iOS)
/// The scope, then the next two items. Lock-screen widgets aren't
/// interactive: a tap opens Upcoming.
private struct RectangularAgendaView: View {
    let entry: WidgetEntry
    let agenda: WidgetAgenda

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ScopeTitle(category: entry.category)
                .font(.headline)
            if agenda.isEmpty {
                Text("Nothing in the next 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(agenda.firstRows(2).rows) { row in
                HStack(spacing: 4) {
                    Image(systemName: row.kind == .task ? "circle" : "note.text")
                        .font(.caption2)
                    Text(row.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutDirection(of: row.title)
                    if let detail = row.detail {
                        Text(detail)
                    }
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Open tasks due today plus overdue ones.
private struct CircularAgendaView: View {
    let agenda: WidgetAgenda

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(agenda.dueTaskCount, format: .number)
                    .font(.title2.bold())
                    .widgetAccentable()
                Image(systemName: "checklist")
                    .font(.caption2)
            }
        }
        .accessibilityLabel("\(agenda.dueTaskCount) tasks due")
    }
}
#endif
