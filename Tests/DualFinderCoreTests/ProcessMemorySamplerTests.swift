import XCTest
@testable import DualFinderCore

final class ProcessMemorySamplerTests: XCTestCase {
    func testCurrentSnapshotReturnsNonZeroResidentSize() {
        let snapshot = ProcessMemorySampler.currentSnapshot()
        XCTAssertGreaterThan(snapshot.residentSize, 0)
    }

    func testDisplayBytesPrefersPhysicalFootprint() {
        let snapshot = ProcessMemorySnapshot(residentSize: 100, physicalFootprint: 200)
        XCTAssertEqual(snapshot.displayBytes, 200)
    }

    func testDisplayBytesFallsBackToResidentSize() {
        let snapshot = ProcessMemorySnapshot(residentSize: 100, physicalFootprint: nil)
        XCTAssertEqual(snapshot.displayBytes, 100)
    }

    func testFormatBytesUsesMemoryStyle() {
        let formatted = ProcessMemorySampler.formatBytes(1_048_576)
        XCTAssertTrue(formatted.contains("MB") || formatted.contains("GB"))
    }

    func testDisplayLabelShowsResidentWhenMuchHigherThanFootprint() {
        let snapshot = ProcessMemorySnapshot(
            residentSize: 1_800_000_000,
            physicalFootprint: 250_000_000
        )
        let label = ProcessMemorySampler.displayLabel(for: snapshot)
        XCTAssertTrue(label.contains("RSS"))
    }

    func testDisplayLabelOmitsResidentWhenCloseToFootprint() {
        let snapshot = ProcessMemorySnapshot(
            residentSize: 260_000_000,
            physicalFootprint: 250_000_000
        )
        let label = ProcessMemorySampler.displayLabel(for: snapshot)
        XCTAssertFalse(label.contains("RSS"))
    }
}
