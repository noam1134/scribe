import Foundation
import SwiftData

/// Phase 0 only. Deleted after the sync spike.
@Model
final class ProbeNote {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date.now

    init(text: String) {
        self.text = text
    }
}
