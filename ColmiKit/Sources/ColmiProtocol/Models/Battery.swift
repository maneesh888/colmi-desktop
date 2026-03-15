import Foundation

/// Battery information from ring
public struct BatteryInfo: Codable, Sendable, Equatable {
    public let level: Int        // 0-100
    public let isCharging: Bool
    
    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
    
    /// Parse battery response packet
    public static func parse(_ data: Data) -> BatteryInfo? {
        guard data.count >= 3,
              ColmiPacket.commandType(data) == .battery else {
            return nil
        }
        return BatteryInfo(
            level: Int(data[1]),
            isCharging: data[2] != 0
        )
    }
    
    /// Request packet for battery level
    public static var requestPacket: Data {
        ColmiPacket.make(command: .battery)
    }
}
