import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Reads file URLs from the system pasteboard (Finder / Dual Finder file copy).
public enum FilePasteboardReader {
#if canImport(AppKit)
    public static func fileURLs(from pasteboard: NSPasteboard = .general) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []

        return objects.compactMap { object in
            if let url = object as? URL {
                return url.standardizedFileURL
            }
            return (object as? NSURL)?.filePathURL?.standardizedFileURL
        }
    }

    public static var hasFileURLs: Bool {
        !fileURLs().isEmpty
    }
#else
    public static func fileURLs() -> [URL] { [] }
    public static var hasFileURLs: Bool { false }
#endif
}
