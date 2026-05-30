import Foundation

enum FileNameUtilities {
    private static let invalidPathComponentCharacters = CharacterSet(charactersIn: "/:")

    static func isBlank(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func containsInvalidPathComponentCharacters(_ name: String) -> Bool {
        name.rangeOfCharacter(from: invalidPathComponentCharacters) != nil
    }

    static func normalizedExtension(_ rawExtension: String) -> String {
        rawExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    static func baseName(for name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    static func extensionName(for name: String) -> String {
        (name as NSString).pathExtension
    }

    static func extensionWithDot(for name: String) -> String {
        let ext = extensionName(for: name)
        return ext.isEmpty ? "" : ".\(ext)"
    }

    static func numberedCopyName(for name: String, index: Int) -> String {
        let base = baseName(for: name)
        let ext = extensionName(for: name)
        return ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
    }
}
