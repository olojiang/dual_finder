import Foundation

public enum TabDragPayload {
    public static let prefix = "dualfinder-tab|"

    public static func encode(tabID: UUID, side: PaneSide) -> String {
        "\(prefix)\(side.rawValue)|\(tabID.uuidString)"
    }

    public static func decode(_ string: String) -> (tabID: UUID, side: PaneSide)? {
        guard string.hasPrefix(prefix) else { return nil }
        let remainder = String(string.dropFirst(prefix.count))
        let parts = remainder.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let side = PaneSide(rawValue: parts[0]),
              let tabID = UUID(uuidString: parts[1]) else {
            return nil
        }
        return (tabID, side)
    }
}
