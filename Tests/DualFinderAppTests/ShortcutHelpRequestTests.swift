import Foundation
import Testing
import DualFinderCore
@testable import DualFinderApp

@Suite("Shortcut help request")
@MainActor
struct ShortcutHelpRequestTests {
    @Test("opens the in-app shortcut help request")
    func opensShortcutHelpRequest() {
        let model = DualFinderViewModel(
            initialURL: FileManager.default.temporaryDirectory,
            logger: ShortcutHelpTestLogger()
        )

        model.requestShortcutHelp()

        #expect(model.shortcutHelpRequest != nil)
    }
}

private final class ShortcutHelpTestLogger: AppLogging, @unchecked Sendable {
    func log(_ level: LogLevel, _ category: String, _ message: String, metadata: [String: String]) {}
}
