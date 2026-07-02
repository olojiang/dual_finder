import Foundation
import Testing
@testable import DualFinderApp

@Suite("PathBreadcrumbBuilder")
struct PathBreadcrumbBuilderTests {
    @Test("builds root-to-leaf components")
    func buildsRootToLeafComponents() {
        let url = URL(fileURLWithPath: "/Users/demo/project/src")
        let components = PathBreadcrumbBuilder.components(for: url)

        #expect(components.first?.url.path == "/")
        #expect(components.last?.url.path == "/Users/demo/project/src")
        #expect(components.map(\.title) == ["/", "Users", "demo", "project", "src"])
    }

    @Test("caps traversal depth to avoid unbounded memory use")
    func capsTraversalDepth() {
        var path = "/"
        for index in 0..<80 {
            path += "segment\(index)/"
        }
        let url = URL(fileURLWithPath: String(path.dropLast()))
        let components = PathBreadcrumbBuilder.components(for: url)

        #expect(components.count == 64)
        #expect(components.last?.title.hasPrefix("segment") == true)
    }
}
