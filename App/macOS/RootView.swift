import ScribeCore
import SwiftUI

/// The Mac app arrives in Phase 3.
struct RootView: View {
    let store: SwiftDataItemStore

    var body: some View {
        ContentUnavailableView("Scribe for Mac is coming soon", systemImage: "macwindow")
            .frame(minWidth: 420, minHeight: 280)
    }
}
