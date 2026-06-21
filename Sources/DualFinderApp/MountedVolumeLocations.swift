import Foundation

struct MountedVolumeLocation: Identifiable, Hashable {
    let url: URL
    let isEjectable: Bool

    var id: String { url.standardizedFileURL.path }

    var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var iconName: String {
        isEjectable ? "externaldrive" : "internaldrive"
    }
}

enum MountedVolumeLocations {
    static func current() -> [MountedVolumeLocation] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey
        ]
        let volumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumeURLs
            .filter { url in
                let path = url.standardizedFileURL.path
                return path.hasPrefix("/Volumes/") && path != "/Volumes"
            }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isEjectable = values?.volumeIsEjectable == true || values?.volumeIsRemovable == true
                return MountedVolumeLocation(url: url.standardizedFileURL, isEjectable: isEjectable)
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }
}
