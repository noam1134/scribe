import CoreTransferable
import Foundation
import ScribeCore
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// Settings → Export All as JSON (spec §2): every category and item, done
/// ones included, as `ExportDocument` JSON. The export runs when the button
/// is tapped, so a failure can be shown before any sheet or panel opens.
@MainActor
enum SettingsExport {
    /// "Scribe-2026-10-05.json".
    static var filename: String {
        ExportDocument.suggestedFilename(now: Date(), calendar: .autoupdatingCurrent)
    }

    /// "Scribe-2026-10-05": the save panel adds the extension for JSON.
    static var filenameWithoutExtension: String {
        (filename as NSString).deletingPathExtension
    }

    #if os(iOS)
    /// The export as a file in a fresh temporary folder (the previous one
    /// is removed), for the share sheet.
    static func writeFile(from store: any ItemStore) throws -> URL {
        let data = try store.exportJSON()
        let files = FileManager.default
        let folder = files.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? files.removeItem(at: folder)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: filename)
        try data.write(to: url, options: .atomic)
        return url
    }
    #endif
}

#if os(iOS)
/// The system share sheet (AirDrop, Save to Files, Mail…), presented over
/// whatever is on screen — here the Settings sheet. SwiftUI's `ShareLink`
/// can't be opened from code, and it would only export once the sheet is up.
@MainActor
enum ShareSheet {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "The share sheet couldn’t be opened. Try again." }
    }

    static func present(_ url: URL) throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var top = scene.keyWindow?.rootViewController else { throw Unavailable() }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }
}
#endif

#if os(macOS)
/// The export for the save panel (`fileExporter`).
struct JSONExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
    }
}
#endif
