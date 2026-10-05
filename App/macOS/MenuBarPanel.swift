import AppKit
import ScribeCore
import SwiftUI

/// The menu bar extra (spec §8): quick-add plus today's agenda.
struct MacMenuBarScene: Scene {
    let loader: StoreLoader

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(loader: loader)
        } label: {
            MenuBarLabel(loader: loader)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon. It is always there, so it hands `MacWindows` the
/// action that opens a main window, and opens one for a link that arrives
/// while every window is closed — a notification tap, an App Intent; the
/// window's root takes the link from there.
private struct MenuBarLabel: View {
    let loader: StoreLoader

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "checklist")
            .accessibilityLabel("Scribe")
            .onAppear { MacWindows.openWindow = openWindow }
            .onChange(of: loader.pendingLink) { _, link in
                guard link != nil, !MacWindows.hasMainWindow else { return }
                MacWindows.showMain()
            }
    }
}

/// Opening it activates the app — the Mac imports from iCloud when it
/// becomes active (spec §18), and the quick-add field needs it for typing.
/// Closing it hands activation back to the app that was in front, unless
/// the user went on in Scribe (opened it, or clicked into its window) or
/// already switched elsewhere.
struct MenuBarPanel: View {
    let loader: StoreLoader

    @State private var previousApp: NSRunningApplication?

    var body: some View {
        Group {
            switch loader.state {
            case .ready(let store):
                MenuBarContent(store: store, open: open, showScribe: showScribe)
            case .failed:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Can’t open your notes").font(.headline)
                    Button("Open Scribe", action: showScribe)
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
        .onDisappear(perform: handBack)
    }

    private func handBack() {
        defer { previousApp = nil }
        guard let previousApp, !previousApp.isTerminated, NSApp.isActive else { return }
        let keyWindowID = NSApp.keyWindow?.identifier?.rawValue ?? ""
        guard !keyWindowID.hasPrefix(MacWindows.mainID) else { return }
        previousApp.activate(from: .current, options: [])
    }

    /// Brings the main window forward as it was (opening one if needed).
    private func showScribe() {
        previousApp = nil
        MacWindows.showMain()
    }

    /// Shows an item (or the agenda) in the main window.
    private func open(_ link: DeepLink) {
        loader.pendingLink = link
        showScribe()
    }
}

private struct MenuBarContent: View {
    let store: SwiftDataItemStore
    let open: (DeepLink) -> Void
    let showScribe: () -> Void

    private enum Field: Hashable { case quickAdd }

    @State private var composer: QuickAddComposer
    @State private var message: String?
    @State private var messageIsError = false
    @FocusState private var focus: Field?

    init(store: SwiftDataItemStore, open: @escaping (DeepLink) -> Void, showScribe: @escaping () -> Void) {
        self.store = store
        self.open = open
        self.showScribe = showScribe
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

            if let hotkey = QuickAddHotkey.status {
                hotkeyNote(.menuBar(shortcut: hotkey.shortcut, isTakenBySystem: hotkey.isTakenBySystem))
            }

            HStack {
                Button("Open Scribe", action: showScribe)
                Spacer()
                Button("Quit Scribe") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .defaultFocus($focus, .quickAdd)
        .onAppear { focus = .quickAdd }
    }

    /// Where the quick-add shortcut is, and a warning when macOS uses the
    /// same keys (it gets them first). Follows Settings' recorder.
    @ViewBuilder private func hotkeyNote(_ note: QuickAddHotkeyNote) -> some View {
        if note.isWarning {
            Label(note.text, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(note.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
