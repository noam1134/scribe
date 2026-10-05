import Foundation
import ScribeCore

/// Phase 0 only. Mirrors probe events to a file in the App Group container
/// so they can be read off the device with `devicectl device copy from`.
enum ProbeLogFile {
    static let fileName = "probe-log.txt"

    static let url: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: ScribeIDs.appGroup)?
        .appending(path: fileName)

    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    static func append(_ text: String) {
        guard let url else { return }
        let line = Data("\(Date.now.formatted(timestamp)) [\(ProbeStore.processLabel)] \(text)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }
}
