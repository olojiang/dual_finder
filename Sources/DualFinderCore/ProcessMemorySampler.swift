import Darwin.Mach
import Foundation

public struct ProcessMemorySnapshot: Sendable, Equatable {
    public let residentSize: UInt64
    public let physicalFootprint: UInt64?

    public init(residentSize: UInt64, physicalFootprint: UInt64?) {
        self.residentSize = residentSize
        self.physicalFootprint = physicalFootprint
    }

    public var displayBytes: UInt64 {
        physicalFootprint ?? residentSize
    }
}

public enum ProcessMemorySampler {
    public static func currentSnapshot() -> ProcessMemorySnapshot {
        ProcessMemorySnapshot(
            residentSize: currentResidentSize(),
            physicalFootprint: currentPhysicalFootprint()
        )
    }

    public static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bitPattern: bytes), countStyle: .memory)
    }

    public static func displayLabel(for snapshot: ProcessMemorySnapshot) -> String {
        let footprint = snapshot.displayBytes
        let formattedFootprint = formatBytes(footprint)
        let residentThreshold = footprint + 50 * 1024 * 1024
        if snapshot.physicalFootprint != nil,
           snapshot.residentSize > residentThreshold {
            let formattedResident = formatBytes(snapshot.residentSize)
            return "Memory \(formattedFootprint) (RSS \(formattedResident))"
        }
        return "Memory \(formattedFootprint)"
    }

    private static func currentResidentSize() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    private static func currentPhysicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }
}
