import Foundation

// MARK: - Set Time

/// Utilities for syncing time with the ring
public enum SetTime {
    
    /// Create a packet to set the ring's time
    /// - Parameter date: The date/time to set (defaults to now)
    /// - Returns: 16-byte packet for command 0x01
    public static func packet(for date: Date = Date()) -> Data {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        
        // Extract components with defaults
        let year = UInt8((components.year ?? 2026) - 2000)
        let month = UInt8(components.month ?? 1)
        let day = UInt8(components.day ?? 1)
        let hour = UInt8(components.hour ?? 0)
        let minute = UInt8(components.minute ?? 0)
        let second = UInt8(components.second ?? 0)
        
        let payload = Data([year, month, day, hour, minute, second, 0x00])
        
        return ColmiPacket.make(command: .setTime, payload: payload)
    }
    
    /// Parse a time sync response
    /// - Parameter data: Response packet
    /// - Returns: true if the ring acknowledged the time sync
    public static func parseResponse(_ data: Data) -> Bool {
        guard data.count >= 2,
              ColmiPacket.commandType(data) == .setTime else {
            return false
        }
        // Success if no error bit set
        return !ColmiPacket.hasError(data)
    }
}
