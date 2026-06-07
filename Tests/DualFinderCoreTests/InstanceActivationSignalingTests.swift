import Foundation
import Testing
@testable import DualFinderCore

@Suite("InstanceActivationSignaling")
struct InstanceActivationSignalingTests {
    @Test("show window message is stable")
    func showWindowMessage() {
        #expect(InstanceActivationSignaling.showWindowMessage == "SHOW_WINDOW\n")
    }

    @Test("socket lives under application support")
    func socketURLPlacement() throws {
        let socketURL = InstanceActivationSignaling.socketURL()
        #expect(socketURL.lastPathComponent == InstanceActivationSignaling.socketFileName)
        #expect(socketURL.path.contains(InstanceActivationSignaling.bundleIdentifier))
    }

    @Test("send returns false when listener is absent")
    func sendWithoutListener() throws {
        let temp = try TemporaryDirectory()
        let socketURL = temp.url.appendingPathComponent("missing.sock")
        #expect(
            InstanceActivationSignaling.sendShowWindowRequest(
                socketURL: socketURL,
                fileManager: .default
            ) == false
        )
    }

    @Test("listener delivers show window requests")
    func listenerDeliversRequests() async throws {
        let socketURL = URL(fileURLWithPath: "/tmp/dualfinder-\(UUID().uuidString).sock")
        var listener: InstanceActivationListener?
        defer { try? FileManager.default.removeItem(at: socketURL) }
        defer { listener?.stop() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = OnceGate(continuation: continuation)
            let activeListener = InstanceActivationListener(socketURL: socketURL, fileManager: .default) {
                gate.resumeSuccess()
            }
            listener = activeListener
            guard activeListener.start() else {
                gate.resumeFailure(ActivationTestError.listenerStartFailed)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                let delivered = InstanceActivationSignaling.sendShowWindowRequest(socketURL: socketURL)
                if !delivered {
                    gate.resumeFailure(ActivationTestError.sendFailed)
                }
            }

            Task {
                try await Task.sleep(for: .seconds(2))
                activeListener.stop()
                gate.resumeFailure(ActivationTestError.timeout)
            }
        }
    }
}

private enum ActivationTestError: Error {
    case timeout
    case sendFailed
    case listenerStartFailed
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Error>

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resumeSuccess() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume()
    }

    func resumeFailure(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(throwing: error)
    }
}
