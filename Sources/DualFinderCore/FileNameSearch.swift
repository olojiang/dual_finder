import Foundation

public enum FileNameSearch {
    public static func matches(_ name: String, query rawQuery: String) -> Bool {
        Matcher(query: rawQuery).matches(name)
    }

    public struct Matcher: Sendable {
        private let query: String
        private let normalizedQuery: String

        public init(query rawQuery: String) {
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            self.query = query
            self.normalizedQuery = FileNameSearch.normalizedCompactLatin(query)
        }

        public var isEmpty: Bool {
            query.isEmpty
        }

        public func matches(_ name: String) -> Bool {
            guard !query.isEmpty else { return true }

            if name.localizedStandardContains(query) {
                return true
            }

            guard !normalizedQuery.isEmpty else { return false }

            let latinName = normalizedLatin(name)
            if compactAlphanumerics(latinName).contains(normalizedQuery) {
                return true
            }

            return initials(from: latinName).contains(normalizedQuery)
        }
    }

    private static func normalizedLatin(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return stripped.lowercased()
    }

    private static func normalizedCompactLatin(_ text: String) -> String {
        compactAlphanumerics(normalizedLatin(text))
    }

    private static func compactAlphanumerics(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func initials(from text: String) -> String {
        var result = String.UnicodeScalarView()
        var isAtTokenStart = true

        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if isAtTokenStart {
                    result.append(scalar)
                }
                isAtTokenStart = false
            } else {
                isAtTokenStart = true
            }
        }

        return String(result)
    }
}
