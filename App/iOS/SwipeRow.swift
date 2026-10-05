import SwiftUI

/// A list's swipe actions for a row outside a `List` (the Lists home): swipe
/// right for Done, left for Delete. A short swipe opens the row on its
/// button; a long one runs it. One row is open at a time, and a tap on an
/// open row closes it.
struct SwipeRow<Content: View>: View {
    let id: UUID
    @Binding var open: UUID?
    /// Off while the row's editor is open: its text fields own the drags.
    var isEnabled = true
    /// nil for memos: nothing to complete.
    let done: (() -> Void)?
    let delete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    /// Decided by a drag's first movement; a vertical drag scrolls instead.
    @State private var isHorizontal: Bool?

    private let buttonWidth: CGFloat = 76
    private let runDistance: CGFloat = 170

    var body: some View {
        content
            .background(Color(.secondarySystemGroupedBackground))
            .overlay {
                if offset != 0 {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { settle(at: 0) }
                }
            }
            .offset(x: offset)
            .background { actions }
            .simultaneousGesture(drag, including: isEnabled ? .all : .subviews)
            .onChange(of: open) { _, open in
                if open != id && offset != 0 { withAnimation(.snappy) { offset = 0 } }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { settle(at: 0) }
            }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if let done, offset > 0 {
                Button { run(done) } label: {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .frame(width: offset)
                        .frame(maxHeight: .infinity)
                }
                .background(.green)
            }
            Spacer(minLength: 0)
            if offset < 0 {
                Button { run(delete) } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .frame(width: -offset)
                        .frame(maxHeight: .infinity)
                }
                .background(.red)
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if isHorizontal == nil {
                    isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                    startOffset = offset
                    if isHorizontal == true { open = id }
                }
                guard isHorizontal == true else { return }
                let x = startOffset + value.translation.width
                offset = done == nil ? min(x, 0) : x
            }
            .onEnded { _ in
                defer { isHorizontal = nil }
                guard isHorizontal == true else { return }
                if offset > runDistance, let done {
                    run(done)
                } else if offset < -runDistance {
                    run(delete)
                } else if offset > buttonWidth / 2, done != nil {
                    settle(at: buttonWidth)
                } else if offset < -buttonWidth / 2 {
                    settle(at: -buttonWidth)
                } else {
                    settle(at: 0)
                }
            }
    }

    private func settle(at x: CGFloat) {
        withAnimation(.snappy) { offset = x }
        if x == 0 {
            if open == id { open = nil }
        } else {
            open = id
        }
    }

    private func run(_ action: () -> Void) {
        withAnimation(.snappy) { offset = 0 }
        if open == id { open = nil }
        action()
    }
}
