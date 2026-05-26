import Foundation

public enum FileSortField: String, CaseIterable, Codable, Sendable {
    case name
    case size
    case modifiedAt
    case type

    public var defaultDirection: SortDirection {
        switch self {
        case .modifiedAt:
            .descending
        case .name, .size, .type:
            .ascending
        }
    }
}

public enum SortDirection: String, Codable, Sendable {
    case ascending
    case descending

    public var toggled: SortDirection {
        self == .ascending ? .descending : .ascending
    }
}

public struct FileSortRule: Codable, Equatable, Sendable {
    public var field: FileSortField
    public var direction: SortDirection

    public init(field: FileSortField = .modifiedAt, direction: SortDirection = .descending) {
        self.field = field
        self.direction = direction
    }

    public func selecting(_ nextField: FileSortField) -> FileSortRule {
        if nextField == field {
            return FileSortRule(field: field, direction: direction.toggled)
        }
        return FileSortRule(field: nextField, direction: nextField.defaultDirection)
    }
}
