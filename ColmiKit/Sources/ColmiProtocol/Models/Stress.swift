import Foundation

// MARK: - Stress Log

/// Daily stress log with 30-minute interval readings
public struct StressLog: Codable, Sendable, Equatable {
    public let date: Date
    public let readings: [Int]  // 48 readings (30-min intervals for 24 hours)
    
    public init(date: Date, readings: [Int]) {
        self.date = date
        self.readings = readings
    }
    
    /// Filter out invalid readings (0 or > 100)
    public var validReadings: [Int] {
        readings.filter { $0 > 0 && $0 <= 100 }
    }
    
    /// Get readings with their timestamps
    public var readingsWithTimes: [(time: Date, stress: Int)] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        return readings.enumerated().compactMap { index, stress in
            guard stress > 0 && stress <= 100 else { return nil }
            let time = calendar.date(byAdding: .minute, value: index * 30, to: startOfDay)!
            return (time, stress)
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

// MARK: - Stress Log Parser

/// Multi-packet parser for stress log data
public final class StressLogParser: @unchecked Sendable {
    private var rawData: [Int] = []
    private var expectedPackets = 0
    private var receivedPackets = 0
    
    public init() {}
    
    public func reset() {
        rawData = []
        expectedPackets = 0
        receivedPackets = 0
    }
    
    /// Parse a packet. Returns StressLog when complete, nil when more packets expected.
    public func parse(_ data: Data) -> StressLog? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .readStress else {
            return nil
        }
        
        let packetNr = Int(data[1] & 0xff)
        
        // Error/empty response
        if packetNr == 0xff {
            reset()
            return nil
        }
        
        // Initial response (packet 0)
        if packetNr == 0 {
            rawData = Array(repeating: 0, count: 48)  // 48 readings (30 min intervals)
            receivedPackets = 1
            return nil
        }
        
        // Data packets
        // Packet 1: bytes 3-14 = 12 values (first 6 hours)
        // Packet 2+: bytes 2-14 = 13 values
        let startByte = packetNr == 1 ? 3 : 2
        var dataIndex = packetNr == 1 ? 0 : 12 + (packetNr - 2) * 13
        
        for i in startByte..<15 {
            if dataIndex < rawData.count {
                rawData[dataIndex] = Int(data[i])
                dataIndex += 1
            }
        }
        receivedPackets += 1
        
        // Check if we have all 48 values
        if packetNr >= 3 {
            let result = StressLog(date: Date(), readings: rawData)
            reset()
            return result
        }
        
        return nil
    }
    
    /// Request packet for stress log
    public static var requestPacket: Data {
        ColmiPacket.make(command: .readStress)
    }
}

// MARK: - Stress Settings

/// Stress monitoring settings
public enum StressSettings {
    /// Enable stress monitoring
    public static func enablePacket() -> Data {
        ColmiPacket.make(command: .stressSettings, payload: Data([0x02, 0x01]))
    }
    
    /// Disable stress monitoring
    public static func disablePacket() -> Data {
        ColmiPacket.make(command: .stressSettings, payload: Data([0x02, 0x00]))
    }
    
    /// Read current settings
    public static var readPacket: Data {
        ColmiPacket.make(command: .stressSettings, payload: Data([0x01]))
    }
    
    /// Parse settings response
    public static func parse(_ data: Data) -> Bool? {
        guard data.count >= 3,
              ColmiPacket.commandType(data) == .stressSettings else {
            return nil
        }
        return data[2] == 0x01
    }
}
