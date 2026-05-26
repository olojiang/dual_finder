import Foundation
import Darwin

final class SingleInstanceGuard {
    private let lockPath: String
    private var descriptor: Int32 = -1

    init(identifier: String) {
        lockPath = NSTemporaryDirectory().appending("\(identifier).lock")
    }

    func acquire() -> Bool {
        descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            ftruncate(descriptor, 0)
            let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
            _ = pid.withCString { write(descriptor, $0, strlen($0)) }
            return true
        }
        close(descriptor)
        descriptor = -1
        return false
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
