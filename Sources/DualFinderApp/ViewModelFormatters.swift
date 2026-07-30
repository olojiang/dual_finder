import Foundation
import DualFinderCore

enum ViewModelFormatters {
    static func folderSizeProgress(
        _ progress: (completed: Int, computed: Int, cached: Int, failures: Int),
        total: Int
    ) -> String {
        var parts = [
            "\(progress.completed)/\(total) done",
            "\(progress.computed) computed",
            "\(progress.cached) cached"
        ]
        if progress.failures > 0 {
            parts.append("\(progress.failures) failed")
        }
        return "Folder size: " + parts.joined(separator: ", ")
    }

    static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func opposite(_ side: PaneSide) -> PaneSide {
        side == .left ? .right : .left
    }
}
