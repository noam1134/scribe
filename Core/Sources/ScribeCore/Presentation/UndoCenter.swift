import Foundation
import Observation

/// Holds the single "Deleted · Undo" offer the UI shows (spec §13). A new
/// offer replaces the old one; offers expire after `duration`.
@MainActor
@Observable
public final class UndoCenter {
    public struct Offer: Identifiable {
        public let id = UUID()
        public let message: String
        fileprivate let undo: @MainActor () throws -> Void
    }

    public private(set) var current: Offer?
    @ObservationIgnored public let duration: Duration
    @ObservationIgnored private var expiry: Task<Void, Never>?

    public init(duration: Duration = .seconds(5)) {
        self.duration = duration
    }

    public func offer(_ message: String, undo: @escaping @MainActor () throws -> Void) {
        let offer = Offer(message: message, undo: undo)
        current = offer
        expiry?.cancel()
        expiry = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.current?.id == offer.id else { return }
            self.current = nil
        }
    }

    /// Runs the undo and clears the offer (also when the undo throws).
    public func performUndo() throws {
        guard let offer = current else { return }
        dismiss()
        try offer.undo()
    }

    public func dismiss() {
        expiry?.cancel()
        expiry = nil
        current = nil
    }
}
