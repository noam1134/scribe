import SwiftUI

extension View {
    /// The "Couldn’t Save" alert for a store write `AppRouter.perform` caught.
    /// Attach it to every presented layer (the root and each sheet): a view
    /// that is presenting a sheet can't show an alert itself.
    func saveErrorAlert(_ router: AppRouter) -> some View {
        alert("Couldn’t Save", isPresented: Binding(
            get: { router.alertMessage != nil },
            set: { if !$0 { router.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.alertMessage ?? "")
        }
    }
}
