import Foundation
import Darwin
import Testing
@testable import DualFinderCore

@Suite("InstanceActivation resources")
struct InstanceActivationResourceTests {
    @Test("closes the socket when the Unix path is invalid")
    func closesSocketWhenUnixPathIsInvalid() {
        let closeRecorder = CloseDescriptorRecorder()
        let path = URL(fileURLWithPath: "/tmp/\(String(repeating: "x", count: 200)).sock")
        let listener = InstanceActivationListener(
            socketURL: path,
            fileManager: .default,
            socketFactory: { 42 },
            closeDescriptor: { closeRecorder.record($0) },
            onRequest: {}
        )

        #expect(listener.start() == false)
        #expect(closeRecorder.values == [42])
    }

    @Test("closes an active socket exactly once when stopped")
    func closesActiveSocketExactlyOnceWhenStopped() async throws {
        let closeRecorder = CloseDescriptorRecorder()
        let listener = InstanceActivationListener(
            socketURL: URL(fileURLWithPath: "/tmp/df-\(UUID().uuidString).sock"),
            fileManager: .default,
            socketFactory: { socket(AF_UNIX, SOCK_STREAM, 0) },
            closeDescriptor: { descriptor in
                closeRecorder.record(descriptor)
                close(descriptor)
            },
            onRequest: {}
        )

        #expect(listener.start())
        listener.stop()

        for _ in 0..<20 where closeRecorder.values.count < 1 {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(closeRecorder.values.count == 1)
    }
}

private final class CloseDescriptorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Int32] = []

    var values: [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }

    func record(_ descriptor: Int32) {
        lock.lock()
        recordedValues.append(descriptor)
        lock.unlock()
    }
}
