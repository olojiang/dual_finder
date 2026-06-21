import AppKit
import Testing
@testable import DualFinderApp

@Suite("TextEditingCommandRouter")
@MainActor
struct TextEditingCommandRouterTests {
    @Test("identifies AppKit text responders")
    func identifiesTextResponders() {
        #expect(TextEditingCommandRouter.isTextResponder(NSTextView()))
    }

    @Test("ignores non-text responders")
    func ignoresNonTextResponders() {
        #expect(!TextEditingCommandRouter.isTextResponder(NSView()))
    }
}
