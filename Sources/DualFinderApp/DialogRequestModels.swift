import AppKit
import Foundation
import SwiftUI
import DualFinderCore

struct PathEditRequest: Equatable {
    let id = UUID()
    let side: PaneSide
}

struct PaneFocusRequest: Equatable {
    let id = UUID()
    let requestID: String
    let side: PaneSide
    let source: String
    let revealURL: URL?
}

struct FileSearchRequest: Equatable {
    let id = UUID()
    let side: PaneSide
}

struct NavigationRevealRequest: Equatable {
    let id = UUID()
    let side: PaneSide
    let revealURL: URL
}

struct SimilarFileDeletionMarkRequest: Equatable {
    let id = UUID()
    let side: PaneSide
    let urls: Set<URL>
}

struct FolderBookmarkDialogRequest: Identifiable, Equatable {
    let id = UUID()
}

struct BatchRenameDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let side: PaneSide
}

struct MergeFilesDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let side: PaneSide
    let sources: [URL]
    let suggestedName: String
}

struct SplitFileDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let side: PaneSide
    let preview: TextFileSplitPreview
}

struct EmptyTrashConfirmationRequest: Identifiable, Equatable {
    let id = UUID()
    let summary: TrashContentsSummary

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: summary.totalByteCount, countStyle: .file)
    }

    var message: String {
        """
        This will permanently delete \(summary.topLevelItemCount) item(s) from Trash.

        Contained files/folders: \(summary.containedItemCount)
        Total size: \(formattedTotalSize)
        """
    }
}

struct MirrorConfirmationRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceSide: PaneSide
    let sources: [URL]
    let destination: URL
    let deletionSummary: MirrorDeletionSummary

    var formattedDeletionSize: String {
        ByteCountFormatter.string(fromByteCount: deletionSummary.totalByteCount, countStyle: .file)
    }
}

struct InlineRenameRequest: Equatable {
    let id = UUID()
    let side: PaneSide
    let url: URL
}

struct ShortcutHelpRequest: Identifiable, Equatable {
    let id = UUID()
}

enum FileClipboardOperation: String {
    case copy
    case move
}

enum AndroidPaneTransferError: LocalizedError {
    case differentDevices

    var errorDescription: String? {
        switch self {
        case .differentDevices:
            "Android-to-Android transfer currently requires the same device."
        }
    }
}

final class TextEncodingScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
