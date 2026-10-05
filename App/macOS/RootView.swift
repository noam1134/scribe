import ScribeCore
import SwiftUI

/// The Mac window (spec §9.3): a glass sidebar (Upcoming, Inbox, categories)
/// and the item list with inline editing, search in the toolbar and the
/// quick-add field at the bottom. No third column.
struct RootView: View {
    let store: SwiftDataItemStore

    @State private var router: MacRouter
    @FocusState private var focus: MacRouter.Focus?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager
    @Environment(StoreLoader.self) private var loader

    init(store: SwiftDataItemStore) {
        self.store = store
        _router = State(initialValue: MacRouter(store: store))
    }

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            ItemListView(store: store, focus: $focus)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MacQuickAddBar(store: store, focus: $focus)
                }
        }
        .searchable(text: $router.searchText, placement: .toolbar, prompt: "Search")
        .searchFocused($focus, equals: .search)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Item", systemImage: "plus") { router.run(.newItem) }
                    .help("New Item (⌘N)")
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .alert("Couldn’t Save", isPresented: Binding(
            get: { router.alertMessage != nil },
            set: { if !$0 { router.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.alertMessage ?? "")
        }
        .environment(router)
        .focusedSceneValue(router)
        .onChange(of: focus) { _, focus in router.focus = focus }
        .onChange(of: router.focusRequest) { _, request in
            guard let request else { return }
            focus = request
            router.focusRequest = nil
        }
        .onChange(of: undoManager, initial: true) { _, manager in router.undoManager = manager }
        .onChange(of: loader.pendingLink, initial: true) { _, link in
            guard let link else { return }
            loader.pendingLink = nil
            router.open(link)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        // Links (widgets, the menu bar) go to this window instead of opening
        // a new one each time.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #if DEBUG
        .task {
            // Not during the first layout: writing while the lists build
            // their first rows makes AppKit warn about reentrancy.
            try? await Task.sleep(for: .milliseconds(200))
            DemoData.seedIfRequested(store)
            DemoData.applyLaunchState(to: router)
        }
        #endif
    }
}
