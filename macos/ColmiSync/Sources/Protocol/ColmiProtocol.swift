import Foundation

/// BLE UUIDs for Colmi rings (Nordic UART Service variant)
enum ColmiUUID {
    static let service = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"
    static let rxCharacteristic = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // Write to ring
    static let txCharacteristic = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // Notifications from ring
    
    // Device Info Service
    static let deviceInfoService = "0000180A-0000-1000-8000-00805F9B34FB"
    static let hardwareRevision = "00002A27-0000-1000-8000-00805F9B34FB"
    static let firmwareRevision = "00002A26-0000-1000-8000-00805F9B34FB"
}

/// Command IDs for Colmi ring protocol
enum ColmiCommand: UInt8 {
    case setTime = 0x01
    case battery = 0x03
    case powerOff = 0x08
    case readHeartRate = 0x15       // 21 - Daily heart rate logs
    case readSpO2Log = 0x2C         // 44 - Daily SpO2 logs
    case readStress = 0x37          // 55 - Stress data
    case readActivity = 0x43        // 67 - Steps/activity
    case findDevice = 0x50          // 80 - Make ring vibrate
    case realTimeHR = 0x69          // 105 - Real-time heart rate
    case realTimeSpO2 = 0x6A        // 106 - Real-time SpO2
}

/// Protocol for building and parsing Colmi ring packets
enum ColmiPacket {
    
    /// Create a 16-byte packet with command, optional payload, and checksum
    static func make(command: ColmiCommand, payload: Data = Data()) -> Data {
        var packet = Data(count: 16)
        packet[0] = command.rawValue
        
        // Copy payload (max 14 bytes)
        let payloadBytes = min(payload.count, 14)
        if payloadBytes > 0 {
            packet.replaceSubrange(1..<(1 + payloadBytes), with: payload.prefix(payloadBytes))
        }
        
        // Calculate and set checksum (last byte)
        packet[15] = checksum(packet)
        
        return packet
    }
    
    /// Calculate checksum: sum of first 15 bytes mod 255
    static func checksum(_ data: Data) -> UInt8 {
        let sum = data.prefix(15).reduce(0) { $0 + UInt16($1) }
        return UInt8(sum & 0xFF)
    }
    
    /// Validate packet checksum
    static func isValid(_ data: Data) -> Bool {
        guard data.count == 16 else { return false }
        return data[15] == checksum(data)
    }
    
    /// Get command type from packet
    static func commandType(_ data: Data) -> ColmiCommand? {
        guard data.count >= 1 else { return nil }
        return ColmiCommand(rawValue: data[0] & 0x7F)  // Mask error bit
    }
    
    /// Check if packet has error bit set
    static func hasError(_ data: Data) -> Bool {
        guard data.count >= 1 else { return true }
        return (data[0] & 0x80) != 0
    }
}

// MARK: - Battery

struct BatteryInfo {
    let level: Int        // 0-100
    let isCharging: Bool
    
    static func parse(_ data: Data) -> BatteryInfo? {
        guard data.count >= 3,
              ColmiPacket.commandType(data) == .battery else {
            return nil
        }
        return BatteryInfo(
            level: Int(data[1]),
            isCharging: data[2] != 0
        )
    }
    
    static var requestPacket: Data {
        ColmiPacket.make(command: .battery)
    }
}

// MARK: - Real-time Heart Rate

enum RealTimeType: UInt8 {
    case heartRate = 0x00
    case spO2 = 0x02
}

struct RealTimeReading {
    let type: RealTimeType
    let value: Int
    let isError: Bool
    
    static func parse(_ data: Data) -> RealTimeReading? {
        guard data.count >= 4,
              let cmd = ColmiPacket.commandType(data),
              cmd == .realTimeHR || cmd == .realTimeSpO2 else {
            return nil
        }
        
        // Packet format: [cmd, readingType, errorCode, value, ...]
        // byte 1 = reading type (1=HR, 3=SpO2)
        // byte 2 = error code (0 = no error)
        // byte 3 = actual value
        let type: RealTimeType = cmd == .realTimeHR ? .heartRate : .spO2
        let isError = data[2] != 0
        let value = Int(data[3])
        
        return RealTimeReading(type: type, value: value, isError: isError)
    }
    
    static func startPacket(type: RealTimeType) -> Data {
        let cmd: ColmiCommand = type == .heartRate ? .realTimeHR : .realTimeSpO2
        return ColmiPacket.make(command: cmd, payload: Data([0x01, type.rawValue]))
    }
    
    static func stopPacket(type: RealTimeType) -> Data {
        let cmd: ColmiCommand = type == .heartRate ? .realTimeHR : .realTimeSpO2
        return ColmiPacket.make(command: cmd, payload: Data([0x00, type.rawValue]))
    }
}

// MARK: - Heart Rate Log

struct HeartRateLog {
    let date: Date
    let readings: [Int]  // 288 readings (5-min intervals for 24 hours)
    
    /// Get readings with timestamps
    var readingsWithTimes: [(bpm: Int, time: Date)] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        return readings.enumerated().map { index, bpm in
            let time = startOfDay.addingTimeInterval(TimeInterval(index * 5 * 60))
            return (bpm: bpm, time: time)
        }
    }
    
    /// Filter to only non-zero readings
    var validReadings: [(bpm: Int, time: Date)] {
        readingsWithTimes.filter { $0.bpm > 0 }
    }
}

/// Parser for multi-packet heart rate log response
class HeartRateLogParser {
    private var rawData: [Int] = []
    private var timestamp: Date?
    private var expectedPackets = 0
    private var receivedPackets = 0
    private var dataIndex = 0
    
    func reset() {
        rawData = []
        timestamp = nil
        expectedPackets = 0
        receivedPackets = 0
        dataIndex = 0
    }
    
    /// Parse a packet. Returns HeartRateLog when complete, nil when more packets expected.
    func parse(_ data: Data) -> HeartRateLog? {
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
            _ = Int(data[3])  // Interval in minutes (usually 5), unused for now
            rawData = Array(repeating: -1, count: expectedPackets * 13)
            dataIndex = 0
            receivedPackets = 1
            return nil
        }
        
        // First data packet (subType 1) - contains timestamp
        if subType == 1 {
            // Bytes 2-5: Unix timestamp (little-endian)
            let ts = data[2..<6].withUnsafeBytes { $0.load(as: UInt32.self) }
            timestamp = Date(timeIntervalSince1970: TimeInterval(ts))
            
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
        if subType == UInt8(expectedPackets - 1), let ts = timestamp {
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
    
    static func requestPacket(for date: Date) -> Data {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let timestamp = UInt32(startOfDay.timeIntervalSince1970)
        
        var payload = Data(count: 4)
        payload.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: timestamp.littleEndian, as: UInt32.self)
        }
        
        return ColmiPacket.make(command: .readHeartRate, payload: payload)
    }
}

// MARK: - Set Time

extension ColmiPacket {
    static func setTimePacket(_ date: Date = Date()) -> Data {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        
        var payload = Data(count: 7)
        payload[0] = UInt8((components.year ?? 2024) - 2000)
        payload[1] = UInt8(components.month ?? 1)
        payload[2] = UInt8(components.day ?? 1)
        payload[3] = UInt8(components.hour ?? 0)
        payload[4] = UInt8(components.minute ?? 0)
        payload[5] = UInt8(components.second ?? 0)
        payload[6] = 0x00  // Week day (0 = auto)
        
        return make(command: .setTime, payload: payload)
    }
}

// MARK: - Find Device (Vibrate)

extension ColmiPacket {
    static var findDevicePacket: Data {
        make(command: .findDevice)
    }
}

// MARK: - Steps/Activity (SportDetail)

/// Activity data for a 15-minute interval
struct SportDetail: Codable, Equatable {
    let timestamp: Date
    let steps: Int
    let calories: Int      // In calories
    let distance: Int      // In meters
    
    /// Time index within day (0-95 for 15-min intervals)
    var timeIndex: Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        let minute = calendar.component(.minute, from: timestamp)
        return hour * 4 + minute / 15
    }
}

/// Daily activity summary
struct DailyActivity: Codable {
    let date: Date
    let details: [SportDetail]
    
    var totalSteps: Int { details.reduce(0) { $0 + $1.steps } }
    var totalCalories: Int { details.reduce(0) { $0 + $1.calories } }
    var totalDistance: Int { details.reduce(0) { $0 + $1.distance } }
}

/// Parser for multi-packet activity/steps response
class ActivityParser {
    private var details: [SportDetail] = []
    private var newCalorieProtocol = false
    private var index = 0
    private var totalPackets = 0
    
    func reset() {
        details = []
        newCalorieProtocol = false
        index = 0
        totalPackets = 0
    }
    
    /// Parse a packet. Returns DailyActivity when complete, nil when more packets expected.
    func parse(_ data: Data) -> DailyActivity? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .readActivity else {
            return nil
        }
        
        // No data response
        if index == 0 && data[1] == 0xFF {
            reset()
            return DailyActivity(date: Date(), details: [])
        }
        
        // Header packet (byte 1 == 0xF0)
        if index == 0 && data[1] == 0xF0 {
            // byte 3 indicates calorie protocol version
            newCalorieProtocol = data[3] == 1
            totalPackets = Int(data[2])
            index += 1
            return nil
        }
        
        // Data packet - parse BCD-encoded date and values
        let year = bcdToDecimal(data[1]) + 2000
        let month = bcdToDecimal(data[2])
        let day = bcdToDecimal(data[3])
        let timeIndex = Int(data[4])
        
        // Create timestamp from date + time index
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = timeIndex / 4
        dateComponents.minute = (timeIndex % 4) * 15
        
        guard let timestamp = Calendar.current.date(from: dateComponents) else {
            return nil
        }
        
        // Parse values (little-endian 16-bit)
        var calories = Int(data[7]) | (Int(data[8]) << 8)
        if newCalorieProtocol {
            calories *= 10
        }
        let steps = Int(data[9]) | (Int(data[10]) << 8)
        let distance = Int(data[11]) | (Int(data[12]) << 8)
        
        let detail = SportDetail(
            timestamp: timestamp,
            steps: steps,
            calories: calories,
            distance: distance
        )
        details.append(detail)
        index += 1
        
        // Check if this is the last packet (byte 5 == byte 6 - 1)
        if data[5] == data[6] - 1 {
            let date = Calendar.current.startOfDay(for: timestamp)
            let result = DailyActivity(date: date, details: details)
            reset()
            return result
        }
        
        return nil
    }
    
    /// Convert BCD byte to decimal
    private func bcdToDecimal(_ byte: UInt8) -> Int {
        return Int((byte >> 4) & 0x0F) * 10 + Int(byte & 0x0F)
    }
    
    /// Create request packet for steps data
    /// - Parameter dayOffset: 0 = today, 1 = yesterday, etc.
    static func requestPacket(dayOffset: Int = 0) -> Data {
        let payload = Data([
            UInt8(dayOffset),   // Day offset
            0x0F,               // Constant
            0x00,               // Unknown
            0x5F,               // Threshold?
            0x01                // Constant
        ])
        return ColmiPacket.make(command: .readActivity, payload: payload)
    }
}

// MARK: - SpO2 Log

/// SpO2 reading with timestamp
struct SpO2Reading: Codable, Equatable {
    let timestamp: Date
    let value: Int  // SpO2 percentage (0-100)
}

/// Daily SpO2 log (similar structure to HR log)
struct SpO2Log {
    let date: Date
    let readings: [Int]  // Values throughout the day
    
    /// Get readings with timestamps (5-minute intervals)
    var readingsWithTimes: [(spO2: Int, time: Date)] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        return readings.enumerated().map { index, value in
            let time = startOfDay.addingTimeInterval(TimeInterval(index * 5 * 60))
            return (spO2: value, time: time)
        }
    }
    
    /// Filter to only valid readings (non-zero)
    var validReadings: [(spO2: Int, time: Date)] {
        readingsWithTimes.filter { $0.spO2 > 0 }
    }
}

/// Parser for multi-packet SpO2 log response
class SpO2LogParser {
    private var rawData: [Int] = []
    private var timestamp: Date?
    private var expectedPackets = 0
    private var receivedPackets = 0
    private var dataIndex = 0
    
    func reset() {
        rawData = []
        timestamp = nil
        expectedPackets = 0
        receivedPackets = 0
        dataIndex = 0
    }
    
    /// Parse a packet. Returns SpO2Log when complete, nil when more packets expected.
    func parse(_ data: Data) -> SpO2Log? {
        guard data.count == 16,
              ColmiPacket.commandType(data) == .readSpO2Log else {
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
            rawData = Array(repeating: -1, count: expectedPackets * 13)
            dataIndex = 0
            receivedPackets = 1
            return nil
        }
        
        // First data packet (subType 1) - contains timestamp
        if subType == 1 {
            // Bytes 2-5: Unix timestamp (little-endian)
            let ts = data[2..<6].withUnsafeBytes { $0.load(as: UInt32.self) }
            timestamp = Date(timeIntervalSince1970: TimeInterval(ts))
            
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
        if subType == UInt8(expectedPackets - 1), let ts = timestamp {
            let result = SpO2Log(date: ts, readings: normalizeReadings())
            reset()
            return result
        }
        
        return nil
    }
    
    private func normalizeReadings() -> [Int] {
        // Replace negative values with 0
        return rawData.map { max(0, $0) }
    }
    
    static func requestPacket(for date: Date) -> Data {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let timestamp = UInt32(startOfDay.timeIntervalSince1970)
        
        var payload = Data(count: 4)
        payload.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: timestamp.littleEndian, as: UInt32.self)
        }
        
        return ColmiPacket.make(command: .readSpO2Log, payload: payload)
    }
}
