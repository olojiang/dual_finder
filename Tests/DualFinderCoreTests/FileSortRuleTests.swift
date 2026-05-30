import Testing
@testable import DualFinderCore

@Suite("FileSortRule")
struct FileSortRuleTests {
    @Test("uses modified date descending as the default sort")
    func usesModifiedDateDescendingDefault() {
        let rule = FileSortRule()

        #expect(rule.field == .modifiedAt)
        #expect(rule.direction == .descending)
    }

    @Test("selecting the same field toggles direction")
    func selectingSameFieldTogglesDirection() {
        let rule = FileSortRule(field: .name, direction: .ascending)

        #expect(rule.selecting(.name) == FileSortRule(field: .name, direction: .descending))
    }

    @Test("selecting a different field uses that field default direction")
    func selectingDifferentFieldUsesDefaultDirection() {
        let rule = FileSortRule(field: .name, direction: .descending)

        #expect(rule.selecting(.modifiedAt) == FileSortRule(field: .modifiedAt, direction: .descending))
        #expect(rule.selecting(.size) == FileSortRule(field: .size, direction: .ascending))
        #expect(rule.selecting(.type) == FileSortRule(field: .type, direction: .ascending))
    }
}
