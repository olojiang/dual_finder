import Foundation
import Testing
@testable import DualFinderCore

final class MoveState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MoveState")
    private var _applyAll: FileOperationConflictResolution?
    private var _didThrow: Error?
    private var _finished = false
    let didFinish = DispatchSemaphore(value: 0)

    var applyAll: FileOperationConflictResolution? { queue.sync { _applyAll } }
    var didThrow: Error? { queue.sync { _didThrow } }
    var finished: Bool { queue.sync { _finished } }

    func setApplyAll(_ value: FileOperationConflictResolution) {
        queue.sync { _applyAll = value }
    }

    func markFinished(error: Error?) {
        queue.sync {
            _finished = true
            _didThrow = error
        }
        didFinish.signal()
    }

    func waitForFinish(timeout: TimeInterval) -> Bool {
        didFinish.wait(timeout: .now() + .seconds(Int(timeout))) == .success
    }
}

@Suite("MoveWithConflictResolutionPattern")
struct MoveWithConflictResolutionPatternTests {
    @Test("move completes when first conflict returns skip and resolver short-circuits remaining")
    func moveCompletesAfterApplyAllSkip() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("src", isDirectory: true)
        let destination = root.url.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var sources: [URL] = []
        for index in 0..<50 {
            let url = source.appendingPathComponent("file-\(index).txt")
            try "payload-\(index)".write(to: url, atomically: true, encoding: .utf8)
            try "existing-\(index)".write(to: destination.appendingPathComponent("file-\(index).txt"), atomically: true, encoding: .utf8)
            sources.append(url)
        }

        let state = MoveState()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileOperationService(logger: CapturingLogger()).move(
                    sources,
                    to: destination,
                    conflictResolver: { _ in
                        if let cached = state.applyAll {
                            return cached
                        }
                        state.setApplyAll(.skip)
                        return .skip
                    }
                )
                state.markFinished(error: nil)
            } catch {
                state.markFinished(error: error)
            }
        }

        #expect(state.waitForFinish(timeout: 10), "Move should finish within timeout")
        #expect(state.finished, "Move should complete normally")
        #expect(state.didThrow == nil, "Move should not throw")
        #expect(state.applyAll == .skip, "applyAll should be set after first conflict")
    }
}