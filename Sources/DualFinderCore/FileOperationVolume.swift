import Foundation

enum FileOperationVolume {
    static func isOnSameDevice(_ source: URL, as destinationDirectory: URL) -> Bool {
        guard let sourceDevice = deviceIdentifier(source),
              let destinationDevice = deviceIdentifier(destinationDirectory) else {
            return false
        }
        return sourceDevice == destinationDevice
    }

    static func canRenameMove(
        sources: [URL],
        to destinationDirectory: URL
    ) -> Bool {
        sources.allSatisfy { isOnSameDevice($0, as: destinationDirectory) }
    }

    static func deviceIdentifier(_ url: URL) -> dev_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_dev
    }
}
