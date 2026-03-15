import Foundation

// MARK: - SpO2 Log

/// Daily SpO2 log
public struct SpO2Log: Codable, Sendable, Equatable {
    public let date: Date
    public let readings: [Int]  // SpO2 percentage values
    
    public init(date: Date, readings: [Int]) {
        self.date = date
        self.readings = readings
    }
    
    /// Filter out invalid readings (0 or > 100)
    public var validReadings: [Int] {
        readings.filter { $0 > 0 && $0 <= 100 }
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

// MARK: - SpO2 Log Parser

/// Multi-packet parser for SpO2 log data
public final class SpO2LogParser: @unchecked Sendable {
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
    
    /// Parse a packet. Returns SpO2Log when complete, nil when more packets expected.
    public func parse(_ data: Data) -> SpO2Log? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .spo2Settings else {
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
            rawData = Array(repeating: -1, count: expectedPackets * 13)
            dataIndex = 0
            receivedPackets = 1
            return nil
        }
        
        // First data packet (subType 1) - contains timestamp
        if subType == 1 {
            timestamp = ColmiPacket.parseTimestamp(data, offset: 2)
            
            // Bytes 6-14: First 9 SpO2 values
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
            let result = SpO2Log(date: ts, readings: rawData.map { max(0, $0) })
            reset()
            return result
        }
        
        return nil
    }
    
    /// Create request packet for a specific date
    public static func requestPacket(for date: Date) -> Data {
        let payload = ColmiPacket.timestampBytes(for: Calendar.current.startOfDay(for: date))
        return ColmiPacket.make(command: .spo2Settings, payload: payload)
    }
}

// MARK: - Real-time SpO2

/// Real-time SpO2 measurement packets
public enum RealTimeSpO2 {
    /// Start real-time SpO2 measurement
    public static var startPacket: Data {
        ColmiPacket.make(command: .realTimeHR, payload: Data([0x03, 0x01]))
    }
    
    /// Stop real-time SpO2 measurement
    public static var stopPacket: Data {
        ColmiPacket.make(command: .realTimeSpO2, payload: Data([0x03, 0x00]))
    }
    
    /// Parse real-time reading response
    public static func parse(_ data: Data) -> (status: Int, spo2: Int)? {
        guard data.count >= 4,
              ColmiPacket.commandType(data) == .realTimeHR,
              data[1] == 0x03 else {  // SpO2 type
            return nil
        }
        return (status: Int(data[2]), spo2: Int(data[3]))
    }
}
