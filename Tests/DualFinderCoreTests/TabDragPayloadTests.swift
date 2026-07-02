import XCTest
@testable import DualFinderCore

final class TabDragPayloadTests: XCTestCase {
    func testEncodesAndDecodesTabDragPayload() {
        let tabID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        let encoded = TabDragPayload.encode(tabID: tabID, side: .left)
        XCTAssertEqual(encoded, "dualfinder-tab|left|550E8400-E29B-41D4-A716-446655440000")
        XCTAssertEqual(TabDragPayload.decode(encoded)?.tabID, tabID)
        XCTAssertEqual(TabDragPayload.decode(encoded)?.side, .left)
    }

    func testRejectsInvalidPayload() {
        XCTAssertNil(TabDragPayload.decode("not-a-tab-payload"))
    }
}
