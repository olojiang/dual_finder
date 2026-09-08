import Foundation
import DualFinderCore

enum TextEncodingReportFormatter {
    static func summary(
        _ result: TextEncodingBatchConversionResult,
        problemReportURL: URL? = nil
    ) -> String {
        let parts = [
            result.convertedCount > 0 ? "\(result.convertedCount) converted to UTF-8" : nil,
            result.alreadyUTF8Count > 0 ? alreadyUTF8Summary(for: result) : nil,
            result.renamedUnknownCount > 0 ? "\(result.renamedUnknownCount) moved to unknown_encode" : nil,
            result.skippedCount > 0 ? "\(result.skippedCount) skipped" : nil,
            result.failedCount > 0 ? "\(result.failedCount) failed" : nil
        ].compactMap { $0 }

        var summary = parts.isEmpty ? "No text encoding changes" : "Encoding check complete: \(parts.joined(separator: ", "))"
        if let problemReportURL {
            summary += ". Problem list: \(problemReportURL.lastPathComponent)"
        }
        return summary
    }

    static func progress(
        completedCount: Int,
        totalCount: Int,
        result: TextEncodingConversionResult
    ) -> String {
        if result.usedCache {
            return "Encoding \(completedCount)/\(totalCount): skipping cached UTF-8 files (\(completedCount) checked)"
        }
        let action = statusLabel(for: result.status)
        return "Encoding \(completedCount)/\(totalCount): \(result.finalURL.lastPathComponent) \(action)"
    }

    static func alreadyUTF8Summary(for result: TextEncodingBatchConversionResult) -> String {
        guard result.cachedUTF8Count > 0 else {
            return "\(result.alreadyUTF8Count) already UTF-8"
        }
        return "\(result.alreadyUTF8Count) already UTF-8 (\(result.cachedUTF8Count) cached)"
    }

    static func statusLabel(for status: TextEncodingConversionStatus) -> String {
        switch status {
        case .alreadyUTF8:
            "already UTF-8"
        case .converted:
            "converted to UTF-8"
        case .renamedUnknown:
            "moved to unknown_encode"
        case .skipped:
            "skipped"
        case .failed:
            "failed"
        }
    }

    static func reportLines(for result: TextEncodingBatchConversionResult, timestamp: String) -> [String] {
        var lines = [
            "DualFinder text encoding problem files",
            "Generated: \(timestamp)",
            "Unknown: \(result.renamedUnknownCount)",
            "Failed: \(result.failedCount)",
            ""
        ]

        for item in result.problemResults {
            lines.append("Status:   \(statusLabel(for: item.status))")
            lines.append("Original: \(item.originalURL.path)")
            lines.append("Current:  \(item.finalURL.path)")
            if let diagnostic = item.diagnostic {
                lines.append("Reason:   \(diagnostic)")
            }
            lines.append("")
        }
        return lines
    }

    static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
