import AppKit
import ScribeCore
import SwiftUI

/// The menu bar extra (spec §8): quick-add plus today's agenda.
struct MacMenuBarScene: Scene {
    let loader: StoreLoader

    var body: some Scene {
        MenuBarExtra("Scribe", systemImage: "checklist") {
            MenuBarPanel(loader: loader)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Opening it activates the app — the Mac imports from iCloud when it
/// becomes active (spec §18), and the quick-add field needs it for typing.
/// Closing it hands activation back to the app that was in front, unless
/// the user asked to open Scribe.
struct MenuBarPanel: View {
    let loader: StoreLoader

    @Environment(\.openWindow) private var openWindow
    @State private var previousApp: NSRunningApplication?

    var body: some View {
        Group {
            switch loader.state {
            case .ready(let store):
                MenuBarContent(store: store, open: open)
            case .failed:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Can’t open your notes").font(.headline)
                    Button("Open Scribe") { open(.upcoming) }
                }
                .padding(16)
            case .loading:
                ProgressView().padding(24)
            }
        }
        .frame(width: 340)
        .onAppear {
            if case .loading = loader.state { loader.load() }
            if !NSApp.isActive {
                previousApp = NSWorkspace.shared.frontmostApplication
                NSApp.activate()
            }
        }
        .onDisappear {
            if let previousApp, !previousApp.isTerminated {
                previousApp.activate(from: .current, options: [])
            }
            previousApp = nil
        }
    }

    private func open(_ link: DeepLink) {
        previousApp = nil
        loader.pendingLink = link
        MacWindows.showMain(openWindow)
    }
}

private struct MenuBarContent: View {
    let store: SwiftDataItemStore
    let open: (DeepLink) -> Void

    private enum Field: Hashable { case quickAdd }

    @State private var composer: QuickAddComposer
    @State private var message: String?
    @State private var messageIsError = false
    @FocusState private var focus: Field?

    init(store: SwiftDataItemStore, open: @escaping (DeepLink) -> Void) {
        self.store = store
        self.open = open
        _composer = State(initialValue: QuickAddComposer(store: store))
    }

    var body: some View {
        let now = Date()
        let labels = DueLabels()
        let today = LocalDay(now, calendar: labels.calendar)
        let agenda = TodayAgenda(store.agenda(.all, now: now), today: today)
        let categories = store.categories
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                MacComposer(
                    store: store,
                    composer: composer,
                    focus: $focus,
                    focusValue: .quickAdd,
                    showsChips: focus == .quickAdd || !composer.text.isEmpty,
                    perform: perform
                ) { added in
                    message = added
                    messageIsError = false
                }
                .controlSize(.small)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(messageIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
            .onChange(of: composer.text) { _, text in if !text.isEmpty { message = nil } }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.headline)
                Text(today.date(atMinute: 12 * 60, calendar: labels.calendar).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .foregroundStyle(.secondary)
            }
            if agenda.isEmpty {
                Text("Nothing due today")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(agenda.overdue) { row($0, categories: categories, overdue: true, labels: labels, today: today) }
                        ForEach(agenda.today) { row($0, categories: categories, overdue: false, labels: labels, today: today) }
                    }
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Open Scribe") { open(.upcoming) }
                Spacer()
                Button("Quit Scribe") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
    }

    private func row(_ item: ItemSnapshot, categories: [CategorySnapshot], overdue: Bool, labels: DueLabels, today: LocalDay) -> some View {
        let category = item.categoryID.flatMap { id in categories.first { $0.id == id } }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if item.kind == .task {
                Button {
                    perform { try store.setDone(item.id, !item.isDone) }
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(category?.color ?? .accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark done")
            } else {
                Image(systemName: "note.text").foregroundStyle(.tertiary)
            }
            Button {
                open(.item(item.id))
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutDirection(of: item.title)
                    let detail = overdue
                        ? item.subtitle(category: category, showsDay: true, showsCategory: true)
                        : item.subtitle(category: category, showsDay: false, showsCategory: true)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Open in Scribe")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}

enum MacWindows {
    /// The id of the main `WindowGroup` in `ScribeApp`.
    static let mainID = "main"

    /// Brings the main window forward, or opens one if they were all closed.
    @MainActor
    static func showMain(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        let main = NSApp.windows.first { window in
            window.identifier?.rawValue.hasPrefix(mainID) == true && (window.isVisible || window.isMiniaturized)
        }
        if let main {
            if main.isMiniaturized { main.deminiaturize(nil) }
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: mainID)
        }
    }
}
