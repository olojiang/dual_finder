import XCTest
@testable import DualFinderCore

final class PathWithSizeClipboardFormatTests: XCTestCase {
    func testCompactSizeUsesThreeFractionalDigits() {
        XCTAssertEqual(PathWithSizeClipboardFormat.compactSize(699_000), "699.000k")
        XCTAssertEqual(PathWithSizeClipboardFormat.compactSize(1_234_567), "1.235m")
        XCTAssertEqual(PathWithSizeClipboardFormat.compactSize(46_283_000_000), "46.283g")
    }

    func testCompactSizeUsesBytesBelowOneKilobyte() {
        XCTAssertEqual(PathWithSizeClipboardFormat.compactSize(512), "512b")
        XCTAssertEqual(PathWithSizeClipboardFormat.compactSize(1), "1b")
    }

    func testLineJoinsPathAndSize() {
        XCTAssertEqual(
            PathWithSizeClipboardFormat.line(path: "/Volumes/thinkplus/Android", size: 46_283_000_000),
            "/Volumes/thinkplus/Android 46.283g"
        )
        XCTAssertEqual(
            PathWithSizeClipboardFormat.line(path: "/tmp/example", size: nil),
            "/tmp/example --"
        )
    }
}
