import Foundation

// MARK: - HRV Log

/// Heart Rate Variability log
public struct HRVLog: Codable, Sendable, Equatable {
    public let date: Date
    public let readings: [Int]  // HRV values in ms
    
    public init(date: Date, readings: [Int]) {
        self.date = date
        self.readings = readings
    }
    
    /// Filter out invalid (0 or > 200) readings
    public var validReadings: [Int] {
        readings.filter { $0 > 0 && $0 <= 200 }
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

// MARK: - HRV Log Parser

/// Multi-packet parser for HRV log data
public final class HRVLogParser: @unchecked Sendable {
    private var rawData: [Int] = []
    private var timestamp: Date?
    private var expectedPackets = 0
    private var receivedPackets = 0
    
    public init() {}
    
    public func reset() {
        rawData = []
        timestamp = nil
        expectedPackets = 0
        receivedPackets = 0
    }
    
    /// Parse a packet. Returns HRVLog when complete, nil when more packets expected.
    public func parse(_ data: Data) -> HRVLog? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .readHRV else {
            return nil
        }
        
        let subType = data[1]
        
        // Error response
        if subType == 0xff {
            reset()
            return nil
        }
        
        // Header packet
        if subType == 0 {
            expectedPackets = Int(data[2])
            rawData = []
            receivedPackets = 1
            return nil
        }
        
        // First data packet has timestamp
        if subType == 1 {
            timestamp = ColmiPacket.parseTimestamp(data, offset: 2)
            
            // HRV values are 2 bytes each (little endian)
            for i in stride(from: 6, to: 14, by: 2) {
                let hrv = Int(data[i]) | (Int(data[i+1]) << 8)
                rawData.append(hrv)
            }
            receivedPackets += 1
            return nil
        }
        
        // Subsequent data packets - HRV values are 2 bytes each
        for i in stride(from: 2, to: 14, by: 2) {
            let hrv = Int(data[i]) | (Int(data[i+1]) << 8)
            rawData.append(hrv)
        }
        receivedPackets += 1
        
        // Check if complete
        if expectedPackets > 0,
           subType == UInt8(truncatingIfNeeded: expectedPackets - 1),
           let ts = timestamp {
            let result = HRVLog(date: ts, readings: rawData)
            reset()
            return result
        }
        
        return nil
    }
    
    /// Create request packet for HRV data
    /// - Parameter dayOffset: 0 = today, 1 = yesterday, etc.
    public static func requestPacket(dayOffset: Int = 0) -> Data {
        let payload = Data([UInt8(truncatingIfNeeded: dayOffset)])
        return ColmiPacket.make(command: .readHRV, payload: payload)
    }
}

// MARK: - HRV Settings

/// HRV monitoring settings
public enum HRVSettings {
    /// Enable HRV monitoring
    public static func enablePacket() -> Data {
        ColmiPacket.make(command: .hrvSettings, payload: Data([0x02, 0x01]))
    }
    
    /// Disable HRV monitoring
    public static func disablePacket() -> Data {
        ColmiPacket.make(command: .hrvSettings, payload: Data([0x02, 0x00]))
    }
    
    /// Read current settings
    public static var readPacket: Data {
        ColmiPacket.make(command: .hrvSettings, payload: Data([0x01]))
    }
    
    /// Parse settings response
    public static func parse(_ data: Data) -> Bool? {
        guard data.count >= 3,
              ColmiPacket.commandType(data) == .hrvSettings else {
            return nil
        }
        return data[2] == 0x01
    }
}
