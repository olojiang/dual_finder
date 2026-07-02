import Foundation

public enum ConditionalFileSelection {
    public static func matchingExtension(
        _ extensionName: String,
        in items: [FileItem],
        referenceURL: URL?
    ) -> Set<URL> {
        let normalized = extensionName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }

        let referenceExtension = referenceURL.map { $0.pathExtension.lowercased() }
        let targetExtension = referenceExtension?.isEmpty == false ? referenceExtension! : normalized

        return Set(
            items.filter { item in
                item.url.pathExtension.lowercased() == targetExtension
            }.map(\.url)
        )
    }

    public static func modifiedToday(in items: [FileItem], calendar: Calendar = .current) -> Set<URL> {
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        return Set(
            items.filter { item in
                guard let modified = item.modifiedAt else { return false }
                return modified >= today && modified < tomorrow
            }.map(\.url)
        )
    }

    public static func largerThan(bytes: Int64, in items: [FileItem]) -> Set<URL> {
        guard bytes > 0 else { return [] }
        return Set(
            items.filter { item in
                guard let size = item.size else { return false }
                return size > bytes
            }.map(\.url)
        )
    }
}
