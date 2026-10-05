import ScribeCore
import SwiftUI

/// iPhone app: floating glass tab bar with Lists, Upcoming and Search, and
/// the quick-add capsule above it on every tab (spec §9.2, §20).
struct RootView: View {
    let store: SwiftDataItemStore

    @State private var router = AppRouter()
    @State private var undo = UndoCenter()
    /// For the composer's height cap.
    @State private var screenHeight: CGFloat = 800
    @Environment(\.scenePhase) private var scenePhase
    @Environment(StoreLoader.self) private var loader

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Lists", systemImage: "list.bullet", value: AppRouter.Tab.lists) {
                NavigationStack {
                    ListsView(store: store)
                }
            }
            Tab("Upcoming", systemImage: "calendar", value: AppRouter.Tab.upcoming) {
                NavigationStack {
                    UpcomingView(store: store)
                }
            }
            Tab(value: AppRouter.Tab.search, role: .search) {
                NavigationStack {
                    SearchView(store: store)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .closesKeyboardOnTapOutside()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        .tabViewBottomAccessory {
            QuickAddBar()
        }
        .overlay(alignment: .bottom) {
            UndoToast()
        }
        .sheet(isPresented: $router.isComposing) {
            QuickAddSheet(store: store, categoryID: router.composerCategoryID, maxHeight: screenHeight * 0.6)
        }
        .saveErrorAlert(router)
        .environment(router)
        .environment(undo)
        .onChange(of: loader.pendingLink, initial: true) { _, link in
            guard let link else { return }
            loader.pendingLink = nil
            router.open(link, store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        #if DEBUG
        .task { DemoData.seedIfRequested(store) }
        .settingsAtLaunchForScreenshots()
        #endif
    }
}
