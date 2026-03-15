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
public final class ActivityParser: @unchecked Sendable {
    private var details: [SportDetail] = []
    private var expectedPackets = 0
    private var receivedPackets = 0
    private var currentDate: Date?
    
    public init() {}
    
    public func reset() {
        details = []
        expectedPackets = 0
        receivedPackets = 0
        currentDate = nil
    }
    
    /// Parse a packet. Returns DailyActivity when complete, nil when more packets expected.
    public func parse(_ data: Data) -> DailyActivity? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .readActivity else {
            return nil
        }
        
        let subType = data[1]
        
        // Error/no data response
        if subType == 0xFF {
            reset()
            return nil
        }
        
        // Header packet (subType 0)
        if subType == 0 {
            expectedPackets = Int(data[2])
            details = []
            receivedPackets = 1
            currentDate = Date()
            
            if expectedPackets == 0 {
                let result = DailyActivity(date: currentDate!, details: [])
                reset()
                return result
            }
            return nil
        }
        
        // Data packets contain activity records
        // Each record is typically: timestamp (4 bytes), steps (2), calories (2), distance (2)
        // Format varies by firmware, this is a simplified parser
        
        if currentDate == nil {
            currentDate = Date()
        }
        
        // Parse basic activity data from packet
        // Bytes 2-5: timestamp or day offset info
        // Bytes 6+: activity data
        
        let calendar = Calendar.current
        let baseDate = currentDate!
        
        // Simplified: treat byte 4 as hour indicator
        let hour = Int(data[4] / 4)  // Approximate hour
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = 0
        let recordTime = calendar.date(from: components) ?? baseDate
        
        // Parse values (little-endian)
        let steps = Int(data[6]) | (Int(data[7]) << 8)
        let calories = Int(data[8]) | (Int(data[9]) << 8)
        let distance = Int(data[10]) | (Int(data[11]) << 8)
        
        if steps > 0 || calories > 0 || distance > 0 {
            details.append(SportDetail(
                timestamp: recordTime,
                steps: steps,
                calories: calories,
                distance: distance
            ))
        }
        
        receivedPackets += 1
        
        // Check if complete
        if expectedPackets > 0, subType == UInt8(truncatingIfNeeded: expectedPackets - 1) {
            let result = DailyActivity(date: currentDate!, details: details)
            reset()
            return result
        }
        
        return nil
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
