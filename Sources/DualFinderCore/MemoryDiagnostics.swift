import Foundation

public enum MemoryDiagnostics {
    public static func metadata(
        snapshot: ProcessMemorySnapshot,
        context: [String: String]
    ) -> [String: String] {
        var metadata = context
        metadata["memory"] = ProcessMemorySampler.formatBytes(snapshot.displayBytes)
        metadata["resident"] = ProcessMemorySampler.formatBytes(snapshot.residentSize)
        if let footprint = snapshot.physicalFootprint {
            metadata["footprint"] = ProcessMemorySampler.formatBytes(footprint)
        }
        return metadata
    }
}
