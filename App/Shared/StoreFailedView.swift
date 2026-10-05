import SwiftUI

struct StoreFailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can't open your notes", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Nothing was deleted. Try again, or restart the app.\n\n\(message)")
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.glassProminent)
        }
    }
}
