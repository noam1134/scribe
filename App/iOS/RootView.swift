import ScribeCore
import SwiftUI

/// iPhone app: floating glass tab bar with Upcoming, Categories and Search,
/// and the quick-add capsule above it on every tab (spec §9.2).
struct RootView: View {
    let store: SwiftDataItemStore

    @State private var router = AppRouter()
    @State private var undo = UndoCenter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Upcoming", systemImage: "calendar", value: AppRouter.Tab.upcoming) {
                NavigationStack {
                    ComingNext(title: "Upcoming")
                }
            }
            Tab("Categories", systemImage: "square.stack", value: AppRouter.Tab.categories) {
                NavigationStack(path: $router.categoriesPath) {
                    ComingNext(title: "Categories")
                }
            }
            Tab(value: AppRouter.Tab.search, role: .search) {
                NavigationStack {
                    ComingNext(title: "Search")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .bottom) {
            UndoToast()
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { router.alertMessage != nil },
            set: { if !$0 { router.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.alertMessage ?? "")
        }
        .environment(router)
        .environment(undo)
        .onOpenURL { url in
            if let link = DeepLink(url: url) { router.open(link, store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}

/// Stands in for a tab whose screen a later task builds. Task 10 deletes it.
private struct ComingNext: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer")
            .navigationTitle(title)
    }
}
