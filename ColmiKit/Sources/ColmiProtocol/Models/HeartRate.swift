import Foundation

// MARK: - Heart Rate Log

/// Daily heart rate log with 5-minute interval readings
public struct HeartRateLog: Codable, Sendable, Equatable {
    public let date: Date
    public let readings: [Int]  // 288 readings (5-min intervals for 24 hours)
    
    public init(date: Date, readings: [Int]) {
        self.date = date
        self.readings = readings
    }
    
    /// Filter out invalid (0 or > 200) readings
    public var validReadings: [Int] {
        readings.filter { $0 > 0 && $0 <= 200 }
    }
    
    /// Get readings with their timestamps
    public var readingsWithTimes: [(time: Date, bpm: Int)] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        return readings.enumerated().compactMap { index, bpm in
            guard bpm > 0 && bpm <= 200 else { return nil }
            let time = calendar.date(byAdding: .minute, value: index * 5, to: startOfDay)!
            return (time, bpm)
        }
    }
    
    /// Statistics
    public var average: Int? {
        let valid = validReadings
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / valid.count
    }
    
    public var min: Int? { validReadings.min() }
    public var max: Int? { validReadings.max() }
}

// MARK: - Heart Rate Log Parser

/// Multi-packet parser for heart rate log data
public final class HeartRateLogParser: @unchecked Sendable {
    private var rawData: [Int] = []
    private var timestamp: Date?
    private var expectedPackets = 0
    private var receivedPackets = 0
    private var dataIndex = 0
    
    public init() {}
    
    public func reset() {
        rawData = []
        timestamp = nil
        expectedPackets = 0
        receivedPackets = 0
        dataIndex = 0
    }
    
    /// Parse a packet. Returns HeartRateLog when complete, nil when more packets expected.
    public func parse(_ data: Data) -> HeartRateLog? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .readHeartRate else {
            return nil
        }
        
        let subType = data[1]
        
        // Error response
        if subType == 0xFF {
            reset()
            return nil
        }
        
        // Header packet (subType 0)
        if subType == 0 {
            expectedPackets = Int(data[2])
            _ = Int(data[3])  // Interval in minutes (usually 5)
            rawData = Array(repeating: -1, count: expectedPackets * 13)
            dataIndex = 0
            receivedPackets = 1
            return nil
        }
        
        // First data packet (subType 1) - contains timestamp
        if subType == 1 {
            timestamp = ColmiPacket.parseTimestamp(data, offset: 2)
            
            // Bytes 6-14: First 9 HR values
            for i in 6..<15 {
                if dataIndex < rawData.count {
                    rawData[dataIndex] = Int(data[i])
                    dataIndex += 1
                }
            }
            receivedPackets += 1
            return nil
        }
        
        // Subsequent data packets
        for i in 2..<15 {
            if dataIndex < rawData.count {
                rawData[dataIndex] = Int(data[i])
                dataIndex += 1
            }
        }
        receivedPackets += 1
        
        // Check if complete
        if expectedPackets > 0, 
           subType == UInt8(truncatingIfNeeded: expectedPackets - 1),
           let ts = timestamp {
            let result = HeartRateLog(date: ts, readings: normalizeReadings())
            reset()
            return result
        }
        
        return nil
    }
    
    private func normalizeReadings() -> [Int] {
        var readings = rawData
        
        // Pad or trim to exactly 288 readings
        if readings.count > 288 {
            readings = Array(readings.prefix(288))
        } else if readings.count < 288 {
            readings.append(contentsOf: Array(repeating: 0, count: 288 - readings.count))
        }
        
        // Replace negative values with 0
        return readings.map { max(0, $0) }
    }
    
    /// Create request packet for a specific date
    public static func requestPacket(for date: Date) -> Data {
        let payload = ColmiPacket.timestampBytes(for: Calendar.current.startOfDay(for: date))
        return ColmiPacket.make(command: .readHeartRate, payload: payload)
    }
}

// MARK: - HR Log Settings

/// Continuous HR monitoring settings
public struct HRLogSettings: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let intervalMinutes: Int
    
    public init(enabled: Bool, intervalMinutes: Int) {
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
    }
    
    /// Parse settings response
    public static func parse(_ data: Data) -> HRLogSettings? {
        guard data.count >= 4,
              ColmiPacket.commandType(data) == .hrLogSettings else {
            return nil
        }
        return HRLogSettings(
            enabled: data[2] == 0x01,
            intervalMinutes: Int(data[3])
        )
    }
    
    /// Read settings packet
    public static var readPacket: Data {
        ColmiPacket.make(command: .hrLogSettings, payload: Data([0x01]))
    }
    
    /// Write settings packet
    public func writePacket() -> Data {
        let payload = Data([
            0x02,  // Write subtype
            enabled ? 0x01 : 0x02,
            UInt8(intervalMinutes)
        ])
        return ColmiPacket.make(command: .hrLogSettings, payload: payload)
    }
    
    /// Common presets
    public static let every5Min = HRLogSettings(enabled: true, intervalMinutes: 5)
    public static let every10Min = HRLogSettings(enabled: true, intervalMinutes: 10)
    public static let every15Min = HRLogSettings(enabled: true, intervalMinutes: 15)
    public static let every30Min = HRLogSettings(enabled: true, intervalMinutes: 30)
    public static let every60Min = HRLogSettings(enabled: true, intervalMinutes: 60)
    public static let disabled = HRLogSettings(enabled: false, intervalMinutes: 5)
}

// MARK: - Real-time Heart Rate

/// Real-time HR measurement packets
public enum RealTimeHeartRate {
    /// Start real-time HR measurement
    public static var startPacket: Data {
        ColmiPacket.make(command: .realTimeHR, payload: Data([0x01, 0x01]))
    }
    
    /// Stop real-time HR measurement
    public static var stopPacket: Data {
        ColmiPacket.make(command: .realTimeSpO2, payload: Data([0x01, 0x00]))
    }
    
    /// Parse real-time reading response
    /// Returns (status, bpm) where status 0 = valid, 1 = worn incorrectly, 2 = temp error
    public static func parse(_ data: Data) -> (status: Int, bpm: Int)? {
        guard data.count >= 4,
              ColmiPacket.commandType(data) == .realTimeHR,
              data[1] == 0x01 else {  // HR type
            return nil
        }
        return (status: Int(data[2]), bpm: Int(data[3]))
    }
}
