import Foundation

// MARK: - Activity/Steps

/// Single activity record
public struct SportDetail: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let steps: Int
    public let calories: Int      // kcal
    public let distance: Int      // meters
    
    public init(timestamp: Date, steps: Int, calories: Int, distance: Int) {
        self.timestamp = timestamp
        self.steps = steps
        self.calories = calories
        self.distance = distance
    }
}

/// Daily activity summary
public struct DailyActivity: Codable, Sendable, Equatable {
    public let date: Date
    public let details: [SportDetail]
    
    public init(date: Date, details: [SportDetail]) {
        self.date = date
        self.details = details
    }
    
    public var totalSteps: Int { details.reduce(0) { $0 + $1.steps } }
    public var totalCalories: Int { details.reduce(0) { $0 + $1.calories } }
    public var totalDistance: Int { details.reduce(0) { $0 + $1.distance } }
    
    /// Distance in km
    public var totalDistanceKm: Double { Double(totalDistance) / 1000.0 }
}

// MARK: - Activity Parser

/// Multi-packet parser for activity data
/// Based on: https://github.com/tahnok/colmi_r02_client/blob/main/colmi_r02_client/steps.py
public final class ActivityParser: @unchecked Sendable {
    private var details: [SportDetail] = []
    private var newCalorieProtocol = false
    private var index = 0
    
    public init() {}
    
    public func reset() {
        details = []
        newCalorieProtocol = false
        index = 0
    }
    
    /// Parse a packet. Returns DailyActivity when complete, nil when more packets expected.
    public func parse(_ data: Data) -> DailyActivity? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .readActivity else {
            return nil
        }
        
        // No data response (0xFF at start)
        if index == 0 && data[1] == 0xFF {
            reset()
            return nil
        }
        
        // Header packet: subType == 0xF0 (240)
        if index == 0 && data[1] == 0xF0 {
            // data[2] = number of packets following
            // data[3] = 1 means new calorie protocol (multiply by 10)
            newCalorieProtocol = (data[3] == 1)
            index += 1
            return nil
        }
        
        // Data packet: parse activity record
        // Byte layout:
        // [0] = command (0x43)
        // [1] = year (BCD, add 2000)
        // [2] = month (BCD)
        // [3] = day (BCD)
        // [4] = time_index (0-95, each = 15 minutes)
        // [5] = packet index
        // [6] = total packets
        // [7-8] = calories (little endian)
        // [9-10] = steps (little endian)
        // [11-12] = distance in meters (little endian)
        
        // Parse date - RTL8762 chips may send 0x00 for year, so fallback to current year
        var year = bcdToDecimal(data[1])
        if year == 0 {
            // RTL8762 quirk: year byte is 0x00, use current year
            year = Calendar.current.component(.year, from: Date()) - 2000
        }
        year += 2000
        
        let month = bcdToDecimal(data[2])
        let day = bcdToDecimal(data[3])
        let timeIndex = Int(data[4])
        let packetIndex = Int(data[5])
        let totalPackets = Int(data[6])
        
        var calories = Int(data[7]) | (Int(data[8]) << 8)
        if newCalorieProtocol {
            calories *= 10
        }
        let steps = Int(data[9]) | (Int(data[10]) << 8)
        let distance = Int(data[11]) | (Int(data[12]) << 8)
        
        // Build timestamp from time_index (15-min intervals)
        let hour = timeIndex / 4
        let minute = (timeIndex % 4) * 15
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        let timestamp = Calendar.current.date(from: components) ?? Date()
        
        if steps > 0 || calories > 0 || distance > 0 {
            details.append(SportDetail(
                timestamp: timestamp,
                steps: steps,
                calories: calories,
                distance: distance
            ))
        }
        
        index += 1
        
        // Check if this is the last packet: packetIndex == totalPackets - 1
        if packetIndex == totalPackets - 1 {
            // Build date from first record or use current date
            let date: Date
            if let first = details.first {
                var dc = Calendar.current.dateComponents([.year, .month, .day], from: first.timestamp)
                dc.hour = 0
                dc.minute = 0
                date = Calendar.current.date(from: dc) ?? Date()
            } else {
                date = Date()
            }
            
            let result = DailyActivity(date: date, details: details)
            reset()
            return result
        }
        
        return nil
    }
    
    /// Convert BCD byte to decimal (e.g., 0x23 -> 23)
    private func bcdToDecimal(_ b: UInt8) -> Int {
        return Int(((b >> 4) & 0x0F) * 10 + (b & 0x0F))
    }
    
    /// Create request packet for activity data
    /// - Parameter dayOffset: 0 = today, 1 = yesterday, etc.
    public static func requestPacket(dayOffset: Int = 0) -> Data {
        // Format: [dayOffset, 0x0F, 0x00, 0x5F, 0x01]
        // The magic bytes 0x0F 0x00 0x5F 0x01 are required for proper response
        let payload = Data([UInt8(truncatingIfNeeded: dayOffset), 0x0F, 0x00, 0x5F, 0x01])
        return ColmiPacket.make(command: .readActivity, payload: payload)
    }
}
