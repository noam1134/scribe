import ScribeCore
import SwiftUI

/// "Deleted “X” · Undo" floating above the tab bar for five seconds.
struct UndoToast: View {
    @Environment(UndoCenter.self) private var undo
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let offer = undo.current {
            HStack(spacing: 12) {
                Text(offer.message)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") {
                    router.perform { try undo.performUndo() }
                }
                .bold()
                .accessibilityIdentifier("undoButton")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(offer.id)
        }
    }
}
