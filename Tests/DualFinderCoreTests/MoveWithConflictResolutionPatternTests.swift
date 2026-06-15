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

    @Test("largerWins apply-all overwrites when source is larger and skips otherwise")
    func largerWinsApplyAllOverwritesWhenSourceLarger() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("src", isDirectory: true)
        let destination = root.url.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var largerSources: [URL] = []
        var smallerSources: [URL] = []
        for index in 0..<6 {
            let payloadSize = (index + 1) * 1024
            let existingSize = (index % 2 == 0) ? 64 : payloadSize * 2

            let url = source.appendingPathComponent("file-\(index).txt")
            try Data(repeating: UInt8(index), count: payloadSize).write(to: url)
            try Data(repeating: UInt8(index + 100), count: existingSize)
                .write(to: destination.appendingPathComponent("file-\(index).txt"))

            if payloadSize >= existingSize {
                largerSources.append(url)
            } else {
                smallerSources.append(url)
            }
        }

        let state = MoveState()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileOperationService(logger: CapturingLogger()).move(
                    largerSources + smallerSources,
                    to: destination,
                    conflictResolver: { conflict in
                        if let cached = state.applyAll {
                            return cached
                        }
                        state.setApplyAll(.largerWins)
                        return .largerWins
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
        #expect(state.applyAll == .largerWins, "applyAll should capture largerWins after first conflict")

        for url in largerSources {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) should be moved")
        }
        for url in smallerSources {
            #expect(FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) should be kept")
        }
    }
}