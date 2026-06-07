import Foundation
import Darwin

private func copyUnixSocketPath(_ path: String, into storage: UnsafeMutablePointer<sockaddr_un>) -> Bool {
    let maxLength = MemoryLayout.size(ofValue: storage.pointee.sun_path) - 1
    guard !path.isEmpty, path.utf8.count <= maxLength else { return false }
    storage.pointee.sun_family = sa_family_t(AF_UNIX)
    path.withCString { cString in
        withUnsafeMutablePointer(to: &storage.pointee.sun_path) { sunPathPointer in
            let base = UnsafeMutableRawPointer(sunPathPointer).assumingMemoryBound(to: CChar.self)
            strncpy(base, cString, maxLength)
            base[maxLength] = 0
        }
    }
    return true
}

public enum InstanceActivationSignaling {
    public static let showWindowMessage = "SHOW_WINDOW\n"
    public static let bundleIdentifier = "com.local.dualfinder"
    public static let socketFileName = "activation.sock"

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    public static func socketURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(socketFileName)
    }

    @discardableResult
    public static func sendShowWindowRequest(
        socketURL: URL? = nil,
        timeout: TimeInterval = 0.35,
        fileManager: FileManager = .default
    ) -> Bool {
        let url = socketURL ?? Self.socketURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        guard withUnsafeMutablePointer(to: &addr, { copyUnixSocketPath(url.path, into: $0) }) else {
            return false
        }

        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, length) == 0
            }
        }
        guard connected else { return false }

        var timeoutVal = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutVal, socklen_t(MemoryLayout<timeval>.size))

        let payload = Data(showWindowMessage.utf8)
        let sent = payload.withUnsafeBytes { buffer in
            send(fd, buffer.baseAddress, buffer.count, 0)
        }
        return sent == payload.count
    }
}

public final class InstanceActivationListener: @unchecked Sendable {
    private let socketURL: URL
    private let fileManager: FileManager
    private let onRequest: @Sendable () -> Void
    private var serverFD: Int32 = -1
    private let queue = DispatchQueue(label: "com.local.dualfinder.activation-listener")
    private var source: DispatchSourceRead?

    public init(
        socketURL: URL? = nil,
        fileManager: FileManager = .default,
        onRequest: @escaping @Sendable () -> Void
    ) {
        self.socketURL = socketURL ?? InstanceActivationSignaling.socketURL(fileManager: fileManager)
        self.fileManager = fileManager
        self.onRequest = onRequest
    }

    @discardableResult
    public func start() -> Bool {
        stop()

        let directory = socketURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        if fileManager.fileExists(atPath: socketURL.path) {
            try? fileManager.removeItem(at: socketURL)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var addr = sockaddr_un()
        guard withUnsafeMutablePointer(to: &addr, { copyUnixSocketPath(socketURL.path, into: $0) }) else {
            return false
        }

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard bound else {
            close(fd)
            return false
        }

        guard listen(fd, 4) == 0 else {
            close(fd)
            return false
        }

        serverFD = fd
        chmod(socketURL.path, 0o600)

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.acceptPendingConnections(on: fd)
        }
        readSource.setCancelHandler { [fd] in
            close(fd)
        }
        source = readSource
        readSource.resume()
        return true
    }

    public func stop() {
        source?.cancel()
        source = nil
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        try? fileManager.removeItem(at: socketURL)
    }

    deinit {
        stop()
    }

    private func acceptPendingConnections(on serverFD: Int32) {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            defer { close(clientFD) }

            var buffer = [UInt8](repeating: 0, count: 64)
            let received = recv(clientFD, &buffer, buffer.count, 0)
            guard received > 0 else { continue }

            let message = String(decoding: buffer.prefix(received), as: UTF8.self)
            guard message.hasPrefix(InstanceActivationSignaling.showWindowMessage.trimmingCharacters(in: .newlines))
                || message.contains("SHOW_WINDOW")
            else { continue }

            onRequest()
        }
    }
}
